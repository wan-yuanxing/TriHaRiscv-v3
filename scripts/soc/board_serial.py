"""Read CPU self-test UART with Windows SerialPort; sends no bytes or board controls."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import re
import subprocess

from gen_board import ROOT
from run import sha, save


def review_uart(data, expect_reboot=False):
    text = data.decode("ascii", errors="replace")
    if "CPU_BOARD_FAIL" in text or "CPU_TRAP" in text:
        raise ValueError("CPU_BOARD_FAIL or CPU_TRAP observed in physical UART")
    epochs = []
    for line in text.splitlines():
        if line == "CPU_BOARD_PASS checked_bytes=8192":
            epochs.append([])
        match = re.fullmatch(r"CPU_ALIVE seq=([0-9a-f]{8}) cycle=([0-9a-f]{8})", line)
        if match and epochs:
            epochs[-1].append((int(match[1], 16), int(match[2], 16)))
    if not epochs:
        raise ValueError("no complete CPU board self-test banner captured")
    if len(epochs) > 1 and not expect_reboot:
        raise ValueError("unexpected restart in stable-run capture")
    if expect_reboot and len(epochs) < 2:
        raise ValueError("reboot banner not captured")
    for records in epochs:
        if len(records) < 2:
            raise ValueError("insufficient CPU cycle progress records")
        if records[0][0] != 0:
            raise ValueError("first sequence after banner must be zero")
        for (prev_seq, prev_cycle), (seq, cycle) in zip(records, records[1:]):
            if (seq - prev_seq) & 0xffffffff != 1:
                raise ValueError("UART sequence discontinuity")
            if not 100_000_000 <= (cycle - prev_cycle) & 0xffffffff <= 200_000_000:
                raise ValueError("CPU cycle counter stalled or unexpected interval")
    return dict(boots=len(epochs), alive_records=sum(map(len, epochs)), checked_bytes_per_boot=8192,
                epochs=[dict(alive_records=len(e), first_cycle=e[0][1], last_cycle=e[-1][1]) for e in epochs])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="COM12")
    parser.add_argument("--seconds", type=int, default=12)
    parser.add_argument("--expect-reboot", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"COM[1-9][0-9]*", args.port) or not 3 <= args.seconds <= 120:
        parser.error("use a Windows COM port and a 3..120-second capture")
    work = ROOT / "build/soc" / ("board-serial-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
    work.mkdir(parents=True)
    result = dict(status="RUNNING", port=args.port, seconds=args.seconds, directory=str(work),
                  operation="read_only_uart", programmed=False, flash_written=False,
                  scope="Physical UART evidence only; combine with matching Program/Verify record for board acceptance",
                  reader_sha256=sha(Path(__file__)), physical_key0_confirmed=False)
    save(work / "result.json", result)
    print("CPU_BOARD_SERIAL_RUN", work, flush=True)
    script = work / "capture.ps1"
    script.write_text(r'''param([string]$Port,[int]$Seconds,[string]$Output)
$ErrorActionPreference='Stop'
$serial=[IO.Ports.SerialPort]::new($Port,115200,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One)
$serial.Handshake=[IO.Ports.Handshake]::None
$serial.DtrEnable=$false
$serial.RtsEnable=$false
$serial.ReadTimeout=100
$stream=[IO.MemoryStream]::new()
try {
    $serial.Open()
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $buffer=[byte[]]::new(4096)
    while($timer.Elapsed.TotalSeconds -lt $Seconds){
        try {$count=$serial.Read($buffer,0,$buffer.Length)}
        catch [TimeoutException] {continue}
        if($count -gt 0){$stream.Write($buffer,0,$count)}
    }
} finally {
    $serial.Close()
    $serial.Dispose()
    [IO.File]::WriteAllBytes($Output,$stream.ToArray())
    $stream.Dispose()
}
''', encoding="utf-8", newline="\n")
    try:
        process = subprocess.run(["pwsh", "-NoProfile", "-File", str(script), "-Port", args.port,
                                  "-Seconds", str(args.seconds), "-Output", str(work / "uart.bin")],
                                 capture_output=True, timeout=args.seconds + 15, creationflags=subprocess.CREATE_NO_WINDOW)
        (work / "capture.stdout.log").write_bytes(process.stdout)
        (work / "capture.stderr.log").write_bytes(process.stderr)
        result["native_return_code"] = process.returncode
        if process.returncode:
            raise RuntimeError("SerialPort capture failed; inspect capture.stderr.log")
        data = (work / "uart.bin").read_bytes()
        (work / "uart.txt").write_text(data.decode("ascii", errors="replace"), encoding="utf-8")
        result["observation"] = review_uart(data, args.expect_reboot)
        result["status"] = "PASS"
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        result.update(status="UNVERIFIED", error=str(error))
    finally:
        if sha(Path(__file__)) != result["reader_sha256"]:
            result.update(status="UNVERIFIED", error="Reader changed during capture")
        result["output_hashes"] = {p.name: sha(p) for p in work.iterdir() if p.is_file() and p.name != "result.json"}
        save(work / "result.json", result)
    print("CPU_BOARD_SERIAL", result["status"], work / "result.json")
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
