"""Read-only PDS JTAG cable/device scan; never resets or programs a device."""
import argparse
import socket
import subprocess
import sys
import time

from common import BUILD, ROOT, fresh_run, tool, write_json


def listening(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.2):
            return True
    except OSError:
        return False


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start-server",action="store_true")
    parser.add_argument("--frequency", choices=("1MHz", "500KHz", "100KHz"))
    args=parser.parse_args()
    port=65420
    work=fresh_run("jtag_scan")
    result={"operation":"read_only_scan", "device_found":False,"frequency":args.frequency,
            "programmed":False,"directory":str(work.relative_to(ROOT))}
    server=None
    try:
        directory=tool("pds_shell").parent
        with (work/"server.log").open("w",encoding="utf-8") as server_log:
            if not listening(port):
                if not args.start_server:
                    raise RuntimeError("No local JTAG server; use --start-server to start one for this scan")
                server=subprocess.Popen([str(directory/"cdt_js.exe"),"-port",str(port),
                                         "-work_dir",str(work)],cwd=work,stdout=server_log,
                                        stderr=subprocess.STDOUT,
                                        creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0))
                deadline=time.monotonic()+5
                while not listening(port) and time.monotonic()<deadline:
                    time.sleep(0.1)
                if not listening(port):
                    raise RuntimeError("Local JTAG server did not start")
            script=work/"scan.tcl"
            frequency=(f"cfg_set_cable_property -index 0 -freq {{{args.frequency}}}\n" if args.frequency else "")
            script.write_text("cfg_connect -ip 127.0.0.1 -port 65420\n"+frequency+"cfg_scan_chain\n"
                              "cfg_read_device_property -mode 0\ncfg_disconnect\n",encoding="ascii")
            with (work/"scan.log").open("w",encoding="utf-8") as scan_log:
                process=subprocess.run([str(directory/"cdt_cfg_shell.exe"),"-file",str(script),
                                        "-work_dir",str(work)],cwd=work,stdout=scan_log,
                                       stderr=subprocess.STDOUT,timeout=30)
            log=(work/"scan.log").read_text(encoding="utf-8",errors="replace")
            result["exit_code"]=process.returncode
            result["device_found"]=process.returncode==0 and "PG2L100H" in log and "00602899" in log
            result["status"]="identified" if result["device_found"] else "unavailable"
            if not result["device_found"]:
                result["reason"]="Target PG2L100H was not identified; inspect scan/server logs"
            print(log[-2200:])
    except (OSError,RuntimeError,subprocess.TimeoutExpired) as error:
        result.update(status="unavailable",reason=str(error))
    finally:
        if server is not None:
            server.terminate()
            try: server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)
    write_json(work/"result.json",result)
    write_json(BUILD/"latest_jtag_scan.json",result)
    print("VIDEO_JTAG_SCAN:",result["status"],work)
    return 0 if result["device_found"] else 1


if __name__=="__main__": raise SystemExit(main())
