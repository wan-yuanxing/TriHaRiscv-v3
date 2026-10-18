"""Decode/record the independent RX image observer without changing preview tools."""
import argparse
import base64
from functools import reduce
import json
import struct
import subprocess
from pathlib import Path

from common import ROOT, fresh_run, sha256, write_json
from read_board import decode_packets


def decode_probe_packets(data):
    rows=[];offset=0
    while True:
        start=data.find(b'TRV1',offset)
        if start<0 or start+37>len(data):break
        packet=data[start:start+37];offset=start+1
        if reduce(int.__xor__,packet,0):continue
        kind=packet[4]
        if kind not in (8,9,10):
            decoded=decode_packets(packet)
            if decoded:rows.extend(decoded);offset=start+37
            continue
        fields=struct.unpack('<4B7I',packet[4:36])
        _,flags,version,reserved,*v=fields
        if version!=1 or reserved:continue
        if kind==8:
            if v[5]>0xffffff or v[6]>0xffffff:continue
            row=dict(type=kind,flags=flags,version=version,frame_sequence=v[0],
                     pixels=v[1],nonzero=v[2],x_bounds=[v[3]&65535,v[3]>>16],
                     y_bounds=[v[4]&65535,v[4]>>16],q0=v[5],q1=v[6])
        elif kind==9:
            if v[1]>0xffffff or v[2]>0xffffff or any(v[4:]):continue
            row=dict(type=kind,flags=flags,version=version,frame_sequence=v[0],
                     q2=v[1],q3=v[2],crc32=f'{v[3]:08x}')
        else:
            if v[6]!=0:continue
            row=dict(type=kind,flags=flags,version=version,frame_sequence=v[0],
                     crc_frame128=f'{v[1]:08x}',crc_frame129=f'{v[2]:08x}',
                     last_change_frame=v[3],crc_before_change=f'{v[4]:08x}',crc32=f'{v[5]:08x}')
        row['mode_good']=bool(flags&128)
        rows.append(row);offset=start+37
    return rows


def pair_samples(records):
    result=[];pending=None
    for row in records:
        if row['type']==8:pending=row
        elif row['type']==9:
            if pending and row['frame_sequence']==pending['frame_sequence']:
                result.append({**{k:v for k,v in pending.items() if k not in ('type','q0','q1')},
                               'quadrants':[pending['q0'],pending['q1'],row['q2'],row['q3']],
                               'crc32':row['crc32'],'second_flags':row['flags']})
            pending=None
        else:pending=None
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds',type=int,default=300)
    args=parser.parse_args()
    if not 1<=args.seconds<=1800:parser.error('seconds must be 1..1800')
    work=fresh_run('rx_image_probe_serial');stop=work/'stop'
    script=work/'capture.ps1'
    script.write_text('''param([int]$Seconds,[string]$StopFile)
$ErrorActionPreference='Stop'
$uart=[System.IO.Ports.SerialPort]::new('COM12',115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$uart.ReadTimeout=200;$uart.DtrEnable=$false;$uart.RtsEnable=$false
try {
 $uart.Open();$timer=[System.Diagnostics.Stopwatch]::StartNew();$buffer=[byte[]]::new(4096)
 Write-Output 'READY'
 while($timer.Elapsed.TotalSeconds -lt $Seconds -and -not [System.IO.File]::Exists($StopFile)) {
  try {$count=$uart.Read($buffer,0,$buffer.Length)
   Write-Output ($timer.Elapsed.TotalMilliseconds.ToString('F3',[System.Globalization.CultureInfo]::InvariantCulture)+' '+[Convert]::ToBase64String($buffer,0,$count))
  } catch [System.TimeoutException] { }
 }
} finally {$uart.Close();$uart.Dispose()}
''',encoding='ascii')
    result={'status':'running','directory':str(work.relative_to(ROOT)),'port':'COM12','records':[],
            'operation':'receive_only_rx_image_probe','scope':'Host receive timestamps; diagnostic image observations only.'}
    write_json(work/'result.json',result)
    print('TRACE_DIRECTORY',work,flush=True)
    command='& {\n'+script.read_text(encoding='ascii')+'\n} -Seconds '+str(args.seconds)+" -StopFile '"+str(stop).replace("'","''")+"'"
    process=subprocess.Popen(['powershell.exe','-NoProfile','-NonInteractive','-Command',command],
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
    pending=b'';offset=0
    with (work/'uart.bin').open('wb') as raw,(work/'chunks.ndjson').open('w',encoding='utf-8') as chunks,(work/'records.ndjson').open('w',encoding='utf-8') as records:
        for line in process.stdout:
            if line.strip()=='READY':print('UART_READY',flush=True);continue
            elapsed,encoded=line.strip().split(' ',1);data=base64.b64decode(encoded)
            chunks.write(json.dumps({'elapsed_ms':float(elapsed),'offset':offset,'bytes':len(data)})+'\n');chunks.flush()
            raw.write(data);raw.flush();offset+=len(data);pending+=data
            while True:
                start=pending.find(b'TRV1')
                if start<0:pending=pending[-3:];break
                if len(pending)<start+37:pending=pending[start:];break
                decoded=decode_probe_packets(pending[start:start+37]);pending=pending[start+(37 if decoded else 1):]
                for row in decoded:
                    row={'elapsed_ms':float(elapsed),**row};result['records'].append(row)
                    records.write(json.dumps(row)+'\n');records.flush()
                    if row['type']==10:print(json.dumps(row),flush=True)
                    if row['type']==9:
                        sample=pair_samples(result['records'][-2:])
                        if sample:print(json.dumps(sample[-1]),flush=True)
        process.wait();error=process.stderr.read()
    result.update(status='pass' if process.returncode==0 and result['records'] else 'fail',
                  error=error,raw_sha256=sha256(work/'uart.bin'),stopped_by_file=stop.exists(),
                  samples=pair_samples(result['records']))
    write_json(work/'result.json',result)
    print('TRACE_COMPLETE',result['status'],len(result['samples']),flush=True)
    return 0 if result['status']=='pass' else 1


if __name__=='__main__':raise SystemExit(main())
