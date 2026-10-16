"""Stage only hash-verified selected vendor files; originals remain unchanged."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys

from common import BUILD, ROOT, sha256, tool, write_json


def relative_path(text):
    path = PurePosixPath(text)
    if (not text or path.is_absolute() or ".." in path.parts or ":" in text
            or "\\" in text or text.startswith("-") or "\x00" in text
            or any(part.endswith((".", " ")) for part in path.parts)):
        raise ValueError("unsafe relative path: " + repr(text))
    return path


def prepare(manifest, name, board_root, output):
    entry = manifest["references"][name]
    archive = board_root / relative_path(entry["archive"])
    if sha256(archive) != entry["sha256"]:
        raise ValueError("archive hash mismatch: " + entry["archive"])
    destination_root = (output / relative_path(name)).resolve()
    if not destination_root.is_relative_to(output.resolve()):
        raise ValueError("unsafe relative path: reference output")
    metadata = destination_root / "provenance.json"
    if (metadata.is_symlink() or not metadata.resolve().is_relative_to(destination_root)
            or (metadata.exists() and
                (not metadata.is_file() or metadata.stat().st_nlink > 1))):
        raise ValueError("unsafe metadata destination")
    verified = {}
    for file in entry["files"]:
        member = str(relative_path(file["member"]))
        relative = relative_path(file["path"])
        if relative.parts and relative.parts[0].casefold() == "provenance.json":
            raise ValueError("reserved metadata path: " + str(relative))
        destination = (destination_root / relative).resolve()
        if not destination.is_relative_to(destination_root):
            raise ValueError("unsafe relative path: destination escapes output")
        if destination in verified:
            raise ValueError("duplicate output: " + str(relative))
        result = subprocess.run([str(tool("tar")), "-xOf", str(archive), member],
                                capture_output=True, timeout=60)
        if result.returncode:
            raise RuntimeError("archive member unavailable: " + member)
        if hashlib.sha256(result.stdout).hexdigest() != file["sha256"]:
            raise ValueError("file hash mismatch: " + member)
        if destination.exists() and destination.read_bytes() != result.stdout:
            raise ValueError("staged file differs; use a fresh --output: " + str(relative))
        verified[destination] = result.stdout
    # Validate every payload before publishing any file.
    for destination, data in verified.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    write_json(metadata, {
        "archive": str(archive), "archive_sha256": entry["sha256"],
        "manifest_sha256": hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest(),
        "files": entry["files"], "scope": "selected source staging, not board validation"})
    return destination_root, len(verified)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path,
                        default=ROOT / "fpga/pg2l100h/ip/video_reference_manifest.json")
    parser.add_argument("--reference", default="hdmi")
    parser.add_argument("--board-root", type=Path,
                        default=Path(os.environ.get("TRIHA_BOARD_ROOT",
                                     "D:/FPGA/盘古100Pro+开发板（MES2L676-100HP）配套资料")))
    parser.add_argument("--output", type=Path, default=BUILD / "vendor")
    args = parser.parse_args()
    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        if manifest["schema_version"] != 1:
            raise ValueError("Unsupported reference manifest version")
        path, count = prepare(manifest, args.reference, args.board_root, args.output)
        print(f"VIDEO_REFERENCE_PASS files={count}: {path}")
        return 0
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"VIDEO_REFERENCE_FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
