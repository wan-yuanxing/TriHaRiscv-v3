"""Check installed native Windows tools; version checks do not prove licenses."""
import platform
import subprocess
import sys

from common import BUILD, tool, write_json


def main():
    report = {"platform": platform.platform(), "python": sys.version.split()[0],
              "python_executable": sys.executable,
              "python_supported": sys.version_info >= (3, 11),
              "tools": {}, "physical_board": False,
              "scope": "executable/version discovery; no license or board signoff"}
    required_ok = report["python_supported"]
    for name, arguments in {"iverilog": ["-V"], "vvp": ["-V"],
                            "pds_shell": ["-version"], "vsim": ["-version"],
                            "tar": ["--version"]}.items():
        try:
            executable = tool(name)
            result = subprocess.run([str(executable), *arguments],
                                    capture_output=True, text=True, errors="replace",
                                    timeout=30)
            lines = (result.stdout + result.stderr).splitlines()
            report["tools"][name] = {"path": str(executable),
                                     "exit_code": result.returncode,
                                     "version": lines[0] if lines else "no version output"}
            if name in ("iverilog", "vvp", "pds_shell", "tar"):
                required_ok &= result.returncode == 0
        except (OSError, subprocess.TimeoutExpired) as error:
            report["tools"][name] = {"error": str(error)}
            if name != "vsim":
                required_ok = False
    report["required_tools_ready"] = bool(required_ok)
    path = BUILD / "doctor.json"
    write_json(path, report)
    for name, item in report["tools"].items():
        print(name + ": " + item.get("version", item.get("error", "unknown")))
    print("Report:", path)
    return 0 if required_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
