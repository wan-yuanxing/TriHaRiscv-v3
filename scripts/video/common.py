"""Small native-process helpers shared by Video entry points (no shell/WSL)."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build/video"
FALLBACKS = {
    "iverilog": Path("D:/iverilog/bin/iverilog.exe"),
    "vvp": Path("D:/iverilog/bin/vvp.exe"),
    "pds_shell": Path("D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe"),
    "vsim": Path("D:/modeltech64_2020.4/win64/vsim.exe"),
}


def tool(name):
    override = os.environ.get("TRIHA_" + name.upper())
    if override:
        candidate = Path(override)
        if not candidate.is_file():
            raise FileNotFoundError(f"TRIHA_{name.upper()} does not name a file")
        return candidate.resolve()
    found = shutil.which(name)
    if found:
        return Path(found)
    if name in FALLBACKS and FALLBACKS[name].is_file():
        return FALLBACKS[name]
    raise FileNotFoundError(f"Missing {name}; set TRIHA_{name.upper()} to its executable")


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8", newline="\n")


def fresh_run(label):
    name = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    path = BUILD / label / name
    path.mkdir(parents=True, exist_ok=False)
    return path


def run_logged(command, log, *, cwd=ROOT, timeout=120):
    command = [str(arg) for arg in command]
    print("RUN", Path(command[0]).name, flush=True)
    with log.open("w", encoding="utf-8") as stream:
        result = subprocess.run(command, cwd=cwd, stdout=stream,
                                stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        tail = log.read_text(encoding="utf-8", errors="replace")[-3000:]
        raise RuntimeError(f"{Path(command[0]).name} exit {result.returncode}\n{tail}")
    return log.read_text(encoding="utf-8", errors="replace")


def input_hashes(paths):
    return {str(Path(path).relative_to(ROOT)).replace("\\", "/"): sha256(path)
            for path in sorted(map(Path, paths))}
