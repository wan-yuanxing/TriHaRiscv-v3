"""Capture UART before authorized volatile Program/Verify and validate the score.

No Flash or UART writes. Preserve raw bytes, incomplete programming epochs and
the independently checked final result; no simulation score is admitted here.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys
import time

from run_cache import ROOT, sha, save


def last_epoch(data):
    text = data.decode('ascii', errors='strict')
    if re.search(r'CPU_TRAP|CPU_DDR_COREMARK_FAIL|CPU_COREMARK_BOARD_FAIL|CPU_COREMARK_STATUS errors=[1-9]', text):
        raise ValueError('physical UART reported failure or trap')
    parts = text.split('CPU_DDR_COREMARK_BOOT\n')
    if len(parts) < 2:
        raise ValueError('no complete private-DDR loader banner')
    return 'CPU_DDR_COREMARK_BOOT\n' + parts[-1], len(parts) - 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('--seconds', type=int, default=600)
    parser.add_argument('--existing-program-record', type=Path,
        help='Read-only KEY0 recovery capture; do not program or verify again')
    args = parser.parse_args()
    if not 30 <= args.seconds <= 1800:
        parser.error('capture deadline must be 30..1800 seconds')
    sys.path.insert(0, str(ROOT / 'scripts/soc'))
    from program_board import validate_package
    from coremark_board import review_output
    package = args.package.resolve()
    manifest = validate_package(package)
    if manifest.get('firmware_profile') != 'ddr-coremark' or manifest['iterations'] != 5000:
        raise ValueError('need a complete timing-admitted DDR CoreMark package')
    work = ROOT / 'build/soc' / ('ddr-coremark-physical-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    row = dict(status='RUNNING', operation='physical_ddr_coremark', port='COM12', directory=str(work),
        package=str(package), package_manifest_sha256=sha(package / 'manifest.json'),
        bitstream_sha256=manifest['bitstream_sha256'], payload_sha256=manifest['payload_sha256'],
        cache_enable=manifest['cache_enable'], programmed=False, verified=False,
        placement_base=manifest.get('placement_base', 0x80000000),
        flash_written=False, board_coremark_validated=False, reader_sha256=sha(__file__),
        physical_ipc=None, ipc_scope='No instruction-retirement CSR; no physical IPC claim',
        programmed_in_this_capture=args.existing_program_record is None,
        manual_recovery_capture=args.existing_program_record is not None,
        started_utc=datetime.now(timezone.utc).isoformat())
    save(work / 'result.json', row)
    (work / 'reader-source.py').write_bytes(Path(__file__).read_bytes())
    (work / 'program-source.py').write_bytes((ROOT / 'scripts/soc/program_board.py').read_bytes())
    print('CPU_DDR_COREMARK_PHYSICAL_RUN', work, flush=True)
    script = work / 'capture.ps1'
    script.write_text(r'''param([string]$Directory,[int]$Seconds)
$ErrorActionPreference='Stop'
$serial=[IO.Ports.SerialPort]::new('COM12',115200,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One)
$serial.Handshake=[IO.Ports.Handshake]::None
$serial.DtrEnable=$false
$serial.RtsEnable=$false
$serial.ReadTimeout=100
$stream=$null
try {
 $serial.Open()
 $stream=[IO.FileStream]::new((Join-Path $Directory 'uart.bin'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 [IO.File]::WriteAllText((Join-Path $Directory 'capture.ready'),'COM12 read-only')
 $timer=[Diagnostics.Stopwatch]::StartNew()
 $buffer=[byte[]]::new(4096)
 while($timer.Elapsed.TotalSeconds -lt $Seconds -and !(Test-Path -LiteralPath (Join-Path $Directory 'capture.stop'))){
  try {$count=$serial.Read($buffer,0,$buffer.Length)} catch [TimeoutException] {continue}
  if($count -gt 0){$stream.Write($buffer,0,$count);$stream.Flush()}
 }
} finally {
 $serial.Close();$serial.Dispose()
 if($null -ne $stream){$stream.Dispose()}
}
''', encoding='utf-8', newline='\n')
    capture = None
    started = time.monotonic()
    try:
        with (work / 'capture.stdout.log').open('wb') as output, (work / 'capture.stderr.log').open('wb') as error:
            capture = subprocess.Popen(['pwsh', '-NoProfile', '-File', str(script), '-Directory', str(work),
                '-Seconds', str(args.seconds)], stdout=output, stderr=error, creationflags=subprocess.CREATE_NO_WINDOW)
            row['capture_pid'] = capture.pid
            for attempt in range(50):
                if (work / 'capture.ready').exists():
                    break
                if capture.poll() is not None:
                    raise RuntimeError('COM12 unavailable; inspect capture.stderr.log')
                time.sleep(.1)
            if not (work / 'capture.ready').exists():
                raise RuntimeError('UART capture not ready')
            if args.existing_program_record:
                program_path = args.existing_program_record.resolve()
                row['program_runner_return_code'] = None
                print('CPU_DDR_COREMARK_KEY0_CAPTURE_READY', work, flush=True)
            else:
                with (work / 'program.log').open('wb') as log:
                    command = [sys.executable, str(ROOT / 'scripts/soc/program_board.py'), str(package)]
                    programmed = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                        timeout=120, creationflags=subprocess.CREATE_NO_WINDOW)
                row['program_runner_return_code'] = programmed.returncode
                program_log = (work / 'program.log').read_text(encoding='utf-8')
                locations = re.findall(r'CPU_PROGRAM PASS (.+result\.json)', program_log)
                if programmed.returncode != 0 or len(locations) != 1:
                    raise RuntimeError('volatile Program/Verify failed; see program.log')
                program_path = Path(locations[0].strip())
            program = json.loads(program_path.read_text(encoding='utf-8'))
            if (program['manifest_sha256'] != row['package_manifest_sha256'] or program['native_return_code'] != 0 or
                    not program['programmed'] or not program['verified'] or program['flash_written']):
                raise ValueError('program record does not bind the admitted image')
            row.update(programmed=True, verified=True, program_record=str(program_path),
                program_record_sha256=sha(program_path), program_finished_utc=program['finished_utc'])
            save(work / 'result.json', row)
            print('CPU_DDR_COREMARK_PHYSICAL_PROGRAMMED', row['cache_enable'], flush=True)
            while capture.poll() is None and time.monotonic() - started < args.seconds:
                data = (work / 'uart.bin').read_bytes()
                if b'CPU_DDR_COREMARK_BOOT\n' in data:
                    text, epochs = last_epoch(data)
                    if 'CPU_COREMARK_BOARD_PASS iterations=5000\n' in text:
                        expected_memory = 'shared DDR stack (uncached)' if row['placement_base'] == 0x82000000 else 'private DDR stack'
                        if 'CPU_DDR_COREMARK_PAYLOAD_PASS\n' not in text or expected_memory not in text:
                            raise ValueError('missing selected DDR copy/execution evidence')
                        measurement = review_output(text, expected_luts=manifest['cpu_only_resources']['lut'])
                        (work / 'measurement-uart.txt').write_text(text, encoding='utf-8', newline='\n')
                        total_luts = manifest['cpu_only_resources']['lut'] + manifest['cache_resources']['lut']
                        row.update(status='PASS', board_coremark_validated=True, measurement=measurement,
                            observed_loader_epochs=epochs, cpu_plus_cache_luts=total_luts,
                            coremark_per_cpu_plus_cache_lut=measurement['coremark'] / total_luts)
                        break
                time.sleep(.25)
            else:
                raise RuntimeError('no complete 5000-iteration physical score before UART deadline')
    except Exception as error:
        row.update(status='FAIL', error=str(error))
    finally:
        if capture is not None and capture.poll() is None:
            (work / 'capture.stop').write_text('stop read-only capture', encoding='utf-8')
            try:
                capture.wait(timeout=5)
            except subprocess.TimeoutExpired:
                capture.terminate()
                capture.wait(timeout=5)
        row['capture_return_code'] = capture.returncode if capture is not None else None
        if row['status'] == 'PASS' and row['capture_return_code'] != 0:
            row.update(status='FAIL', board_coremark_validated=False, error='UART reader did not exit cleanly')
        if (work / 'uart.bin').exists():
            (work / 'uart.txt').write_text((work / 'uart.bin').read_bytes().decode('ascii', errors='replace'), encoding='utf-8')
        if sha(__file__) != row['reader_sha256'] or sha(package / 'manifest.json') != row['package_manifest_sha256']:
            row.update(status='FAIL', board_coremark_validated=False, error='measurement inputs changed')
        row['elapsed_seconds'] = round(time.monotonic() - started, 3)
        row['finished_utc'] = datetime.now(timezone.utc).isoformat()
        row['output_hashes'] = {p.name: sha(p) for p in work.iterdir() if p.is_file() and p.name != 'result.json'}
        save(work / 'result.json', row)
    print('CPU_DDR_COREMARK_PHYSICAL', row['status'], row.get('measurement', row.get('error')), flush=True)
    return 0 if row['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
