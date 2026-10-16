"""Package a successful board bitstream and evidence for reproducible bring-up."""
import json
from pathlib import Path
import shutil
import sys

from common import BUILD, ROOT, sha256, write_json


def main():
    write_json(BUILD/"latest_package.json",{"status":"running","physical_board":False})
    try:
        return package_current()
    except (OSError,ValueError,KeyError) as error:
        write_json(BUILD/"latest_package.json",{"status":"fail","error":str(error),"physical_board":False})
        print("VIDEO_PACKAGE_FAIL:",error,file=sys.stderr)
        return 1


def package_current():
    build_result=BUILD/"latest_pds_video_board_smoke.json"
    if not build_result.exists(): build_result=BUILD/"latest_pds.json"
    result=json.loads(build_result.read_text(encoding="utf-8"))
    if not (result["status"]=="pass" and result["target"]=="video_board_smoke"
            and result["stage"]=="bitstream" and result["internal_timing_met"]):
        raise ValueError("Latest PDS result is not a successful board bitstream")
    bitstream=ROOT/result["artifact"]
    digest=sha256(bitstream)
    if digest!=result["artifact_sha256"]:
        raise ValueError("Bitstream hash differs from verified build")
    verify_mask=ROOT/result["verify_mask"]
    if verify_mask != bitstream.with_suffix(".smsk"):
        raise ValueError("PDS Verify mask must be the bitstream's sibling .smsk")
    mask_digest=sha256(verify_mask)
    if mask_digest!=result["verify_mask_sha256"]:
        raise ValueError("Verification mask hash differs from verified build")
    for relative,expected in result["inputs"].items():
        if sha256(ROOT/relative)!=expected:
            raise ValueError("Source changed since bitstream build: "+relative)
    package=BUILD/"releases"/("video_board_smoke_"+digest[:12])
    package.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(bitstream,package/bitstream.name)
    shutil.copyfile(verify_mask,package/verify_mask.name)
    shutil.copyfile(ROOT/result["timing_report"],package/"timing.rtr")
    shutil.copyfile(ROOT/result["directory"] / "message_review.json",package/"message_review.json")
    write_json(package/"manifest.json",result)
    (package/"README.txt").write_text(
        "PG2L100H-6IFBG676 / MES2L676-100HP TX-only color bars\n"
        "800x600 RGB888, 40 MHz, positive HS/VS, no RX or DDR dependency.\n"
        "Internal routed timing passed. MS7210 external AC timing is not signed off.\n"
        "Device/board identification and actual picture still require hardware validation.\n"
        "LED0 A20 heartbeat; LED1 C18 PLL lock; LED2 C19 error; LED3 E18 init done.\n"
        "KEY0 C22 active-low reset. HDMI OUT uses MS7210, address 0x59.\n"
        "Power board, connect PDS JTAG and HDMI OUT to monitor; scan target before programming.\n"
        "PDS Configuration: Scan Device, assign this .sbit to PG2L100H, Program, Verify.\n"
        "Keep the matching .smsk beside the .sbit; PDS Verify requires both files.\n"
        "Use volatile JTAG configuration; this package contains no Flash image.\n"
        f"Bitstream SHA256 {digest}\nVerification mask SHA256 {mask_digest}\n",encoding="utf-8")
    write_json(BUILD/"latest_package.json",{"status":"pass","directory":str(package.relative_to(ROOT)),
                                         "bitstream_sha256":digest,"verify_mask_sha256":mask_digest,
                                         "physical_board":False})
    print("VIDEO_PACKAGE_PASS:",package)
    return 0


if __name__=="__main__":
    raise SystemExit(main())
