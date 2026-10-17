"""Read framed board diagnostics through Windows SerialPort (no pyserial)."""
import argparse
from functools import reduce
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

from common import BUILD,ROOT,fresh_run,sha256,write_json


def decode_packets(data):
    records=[]
    offset=0
    names=('type','flags','rgb_signature','h_active','v_active','h_total','v_total',
           'h_sync','v_sync','h_front','h_back','v_front','v_back','pixel_hz','good_frames','bad_frames')
    while True:
        start=data.find(b'TRV1',offset)
        if start<0 or start+37>len(data):break
        packet=data[start:start+37]
        offset=start+1
        if reduce(int.__xor__,packet,0):continue
        if packet[4]==1:
            record=dict(zip(names,struct.unpack('<BBH10HIHH',packet[4:36])))
            flags=('tx_done','tx_error','rx_boot_done','rx_error','rx_configured',
                   'snapshot_fresh','frequency_good','mode_good')
        elif packet[4]==2:
            fields=('type','flags','phase','error_code','compared_beats','first_error_word_address',
                    'first_error_xor_low32','low_base_bytes','high_base_bytes','window_beats','heartbeat')
            record=dict(zip(fields,struct.unpack('<4B7I',packet[4:36])))
            flags=('init_done','busy','done','error','all_pll_locked')
        elif packet[4]==3:
            fields=('type','flags','reserved','vs_high_clocks','vs_period_clocks',
                    'hs_rises','hs_falls','vs_rises','vs_falls','de_rises')
            record=dict(zip(fields,struct.unpack('<BBH7I',packet[4:36])))
            flags=('tx_done','tx_error','rx_boot_done','rx_error','rx_configured',
                   'snapshot_fresh','frequency_good','mode_good')
        elif packet[4]==4:
            fields=('type','flags','phase','error_code','compared_beats','first_error_word_address',
                    'first_error_xor_low32','test_base_bytes','frame_bytes','expected_beats','heartbeat')
            record=dict(zip(fields,struct.unpack('<4B7I',packet[4:36])))
            flags=('init_done','busy','done','error','all_pll_locked')
        elif packet[4]==5:
            fields=('type','flags','phase','error_code','captured_pixels','checked_bytes',
                    'source_crc','ddr_crc','frame_tag','fifo_peak','heartbeat')
            record=dict(zip(fields,struct.unpack('<4B7I',packet[4:36])))
            flags=('init_done','busy','done','error','all_pll_locked','rx_mode_good','tx_done','overflow')
        elif packet[4] in (6,7):
            fields=(('type','flags','phase','error_code','captured_pixels','preview_pixels',
                     'source_crc','ddr_crc','preview_crc','preview_ddr_crc','heartbeat')
                    if packet[4]==6 else
                    ('type','flags','phase','error_code','frame_id','commits','completed_scans',
                     'underflows','read_lines','fifo_peak','heartbeat'))
            record=dict(zip(fields,struct.unpack('<4B7I',packet[4:36])))
            flags=('init_done','busy','done','error','all_pll_locked','rx_mode_good','tx_done','overflow')
        else:continue
        for bit,name in enumerate(flags):
            record[name]=bool(record['flags']&(1<<bit))
        records.append(record)
        offset=start+37
    return records


def qualify_ddr(records):
    rows=[r for r in records if r['type']==2]
    if len(rows)<2 or rows[-1]['heartbeat']==rows[-2]['heartbeat']:return False
    return all(r['init_done'] and r['all_pll_locked'] and r['done'] and not r['busy']
               and not r['error'] and r['error_code']==0 and r['compared_beats']==3_014_685
               and r['first_error_word_address']==0 and r['first_error_xor_low32']==0
               and r['low_base_bytes']==0 and r['high_base_bytes']==0x3ff00000
               and r['window_beats']==32768 for r in rows[-2:])


def qualify_axi_dma(records):
    rows=[r for r in records if r['type']==4]
    if len(rows)<2 or rows[-1]['heartbeat']==rows[-2]['heartbeat']:return False
    return all(r['init_done'] and r['all_pll_locked'] and r['done'] and not r['busy']
               and not r['error'] and r['error_code']==0 and r['phase']==0xa5
               and r['compared_beats']==90000 and r['expected_beats']==90000
               and r['first_error_word_address']==0 and r['first_error_xor_low32']==0
               and r['test_base_bytes']==0x87300000 and r['frame_bytes']==1440000 for r in rows[-2:])


def qualify_hdmi_capture(records):
    rows=[r for r in records if r.get('type')==5]
    if len(rows)<2 or rows[-1].get('heartbeat')==rows[-2].get('heartbeat'):return False
    return all(all(r.get(name) is True for name in
                   ('init_done','done','all_pll_locked','rx_mode_good','tx_done'))
               and all(r.get(name) is False for name in ('busy','error','overflow'))
               and r.get('phase')==0xa5 and r.get('error_code')==0
               and r.get('captured_pixels')==480000 and r.get('checked_bytes')==1440000
               and isinstance(r.get('source_crc'),int) and r['source_crc']==r.get('ddr_crc')
               and r.get('frame_tag')==1 and 1<=r.get('fifo_peak',0)<=2048
               and isinstance(r.get('heartbeat'),int) for r in rows[-2:])


def _preview_healthy(record):
    return (record.get('flags')==0x75 and all(record.get(name) is True for name in
                ('init_done','done','all_pll_locked','rx_mode_good','tx_done'))
            and all(record.get(name) is False for name in ('busy','error','overflow'))
            and record.get('phase')==0xa5 and record.get('error_code')==0
            and type(record.get('heartbeat')) is int and 0<=record['heartbeat']<=0xffffffff)


def _current_preview_records(records):
    # Both packet types describe one engine. A later fault or restart of
    # either type invalidates all earlier success samples and their epoch.
    current=[]
    for row in reversed(records):
        if row.get('type') not in (6,7):continue
        if not _preview_healthy(row):break
        current.append(row)
    return list(reversed(current))


def qualify_preview_capture(records):
    rows=[row for row in _current_preview_records(records) if row.get('type')==6][-2:]
    if len(rows)!=2 or rows[0].get('heartbeat')==rows[1].get('heartbeat'):return False
    return all(_preview_healthy(row) and row.get('captured_pixels')==480000
               and row.get('preview_pixels')==120000
               and all(type(row.get(field)) is int and 0<=row[field]<=0xffffffff
                       for field in ('source_crc','ddr_crc','preview_crc','preview_ddr_crc'))
               and row['source_crc']==row['ddr_crc']
               and row['preview_crc']==row['preview_ddr_crc'] for row in rows)


def qualify_preview_display(records):
    rows=[row for row in _current_preview_records(records) if row.get('type')==7][-2:]
    if not qualify_preview_capture(records) or len(rows)!=2:return False
    for row in rows:
        if not (_preview_healthy(row) and row.get('frame_id')==1 and row.get('commits')==1
                and row.get('underflows')==0 and type(row.get('fifo_peak')) is int
                and 1<=row['fifo_peak']<=2048
                and type(row.get('completed_scans')) is int and row['completed_scans']>=2
                and type(row.get('read_lines')) is int
                and 300*row['completed_scans']<=row['read_lines']<=300*(row['completed_scans']+2)):
            return False
    return (rows[0]['heartbeat']!=rows[1]['heartbeat']
            and rows[0]['frame_id']==rows[1]['frame_id']
            and rows[1]['completed_scans']>rows[0]['completed_scans']
            and rows[1]['read_lines']>rows[0]['read_lines'])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',required=True)
    parser.add_argument('--seconds',type=int,default=8)
    args=parser.parse_args()
    if not re.fullmatch(r'COM[1-9][0-9]*',args.port,re.IGNORECASE) or not 1<=args.seconds<=60:
        parser.error('Use explicit COM<n> and a duration from1to60seconds')
    work=fresh_run('board_serial')
    result={'status':'running','directory':str(work.relative_to(ROOT)), 'port':args.port,'records':[],
            'operation':'receive_only_uart','physical_rx_mode_verified':False,
            'physical_ddr_bist_verified':False,'physical_axi_dma_verified':False,
            'physical_hdmi_raw_capture_verified':False,
            'physical_preview_capture_verified':False,'physical_preview_display_verified':False}
    write_json(BUILD/'latest_board_serial.json',result)
    try:
        shell=shutil.which('powershell.exe')
        if shell is None:raise RuntimeError('Windows PowerShell not found')
        script=work/'capture.ps1'
        script.write_text('''param([string]$Port,[int]$Seconds,[string]$OutputFile)
$ErrorActionPreference='Stop'
$uart=[System.IO.Ports.SerialPort]::new($Port,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$uart.ReadTimeout=200
$uart.DtrEnable=$false
$uart.RtsEnable=$false
$stream=[System.IO.File]::Open($OutputFile,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)
try {
    $uart.Open()
    $timer=[System.Diagnostics.Stopwatch]::StartNew()
    $buffer=[byte[]]::new(4096)
    while($timer.Elapsed.TotalSeconds -lt $Seconds) {
        try { $count=$uart.Read($buffer,0,$buffer.Length); $stream.Write($buffer,0,$count) }
        catch [System.TimeoutException] { }
    }
} finally { $uart.Close(); $uart.Dispose(); $stream.Dispose() }
''',encoding='ascii')
        raw=work/'uart.bin'
        quote=lambda value:"'"+str(value).replace("'","''")+"'"
        command='& {\n'+script.read_text(encoding='ascii')+'\n} -Port '+quote(args.port)+\
            ' -Seconds '+str(args.seconds)+' -OutputFile '+quote(raw)
        with (work/'capture.log').open('w',encoding='utf-8') as log:
            process=subprocess.run([shell,'-NoProfile','-NonInteractive','-Command',command],
                stdout=log,stderr=subprocess.STDOUT,timeout=args.seconds+15)
        if process.returncode:raise RuntimeError('Serial capture failed; inspect capture.log')
        records=decode_packets(raw.read_bytes())
        if not records:raise RuntimeError('No valid TRV1 board packets received')
        result.update(status='pass',records=records,raw_sha256=sha256(raw))
        latest=records[-1]
        expected={'h_active':800,'v_active':600,'h_total':1056,'v_total':628,
                  'h_sync':128,'v_sync':4,'h_front':40,'h_back':88,'v_front':1,'v_back':23}
        rx_records=[r for r in records if r['type']==1]
        result['physical_rx_mode_verified']=len(rx_records)>=3 and all(
            all(row[k]==v for k,v in expected.items()) and 39_800_000<=row['pixel_hz']<=40_200_000
            and all(row[k] for k in ('mode_good','frequency_good','snapshot_fresh','rx_boot_done','rx_configured','tx_done'))
            and not(row['tx_error'] or row['rx_error']) for row in rx_records[-3:])
        result['physical_ddr_bist_verified']=qualify_ddr(records)
        result['physical_axi_dma_verified']=qualify_axi_dma(records)
        result['physical_hdmi_raw_capture_verified']=qualify_hdmi_capture(records)
        result['physical_preview_capture_verified']=qualify_preview_capture(records)
        result['physical_preview_display_verified']=qualify_preview_display(records)
        print(json.dumps(latest,ensure_ascii=True))
    except (OSError,RuntimeError,subprocess.TimeoutExpired) as error:
        result.update(status='fail',reason=str(error));print(str(error),file=sys.stderr)
    write_json(work/'result.json',result)
    write_json(BUILD/'latest_board_serial.json',result)
    print('VIDEO_BOARD_SERIAL:',result['status'],work)
    return 0 if result['status']=='pass' else 1


if __name__=='__main__':raise SystemExit(main())
