"""Package a successful board bitstream and evidence for reproducible bring-up."""
import argparse
import json
from pathlib import Path
import shutil
import sys

from common import BUILD, ROOT, sha256, write_json


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target',choices=('video_board_smoke','video_rx_board','video_ddr_bist','video_axi_capture','video_hdmi_capture','video_preview_board'),default='video_board_smoke')
    args=parser.parse_args([] if argv is None else argv)
    for path in (BUILD/'latest_package.json', BUILD/f'latest_package_{args.target}.json'):
        write_json(path,{"status":"running","target":args.target,"physical_board":False})
    try:
        return package_current(args.target)
    except (OSError,ValueError,KeyError) as error:
        for path in (BUILD/'latest_package.json', BUILD/f'latest_package_{args.target}.json'):
            write_json(path,{"status":"fail","target":args.target,"error":str(error),"physical_board":False})
        print("VIDEO_PACKAGE_FAIL:",error,file=sys.stderr)
        return 1


def package_current(target='video_board_smoke'):
    build_result=BUILD/f"latest_pds_{target}.json"
    if not build_result.exists(): build_result=BUILD/"latest_pds.json"
    result=json.loads(build_result.read_text(encoding="utf-8"))
    if not (result["status"]=="pass" and result["target"]==target
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
    package=BUILD/"releases"/(target+"_"+digest[:12])
    package.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(bitstream,package/bitstream.name)
    shutil.copyfile(verify_mask,package/verify_mask.name)
    shutil.copyfile(ROOT/result["timing_report"],package/"timing.rtr")
    shutil.copyfile(ROOT/result["directory"] / "message_review.json",package/"message_review.json")
    write_json(package/"manifest.json",result)
    (package/"README.txt").write_text(
        f"PG2L100H-6IFBG676 / MES2L676-100HP {target}\n"
        f"Scope: {result.get('scope','See manifest')}\n"
        "Internal routed timing passed. External board AC timing is not signed off.\n"
        "Device/board operation requires separate hardware evidence.\n"+
        ("Shared preview: LED0 heartbeat; LED1 calibrated; LED2 CRC/display PASS; LED3 error. UART type6/7 C24 at115200.\n" if target=='video_preview_board' else
         "HDMI raw capture/CRC: LED0 heartbeat; LED1 calibrated; LED2 PASS; LED3 error. UART type5 C24 at115200.\n" if target=='video_hdmi_capture' else
         "AXI/DMA destructive selftest: LED0 heartbeat; LED1 calibrated; LED2 PASS; LED3 error. UART C24 at115200.\n" if target=='video_axi_capture' else
         "DDR standalone destructive BIST: LED0 heartbeat; LED1 calibrated; LED2 PASS; LED3 error. UART C24 at115200.\n" if target=='video_ddr_bist' else
         "LED0 heartbeat; LED1 PLL lock; LED2 input mode good; LED3 init error. UART C24 at115200.\n" if target=='video_rx_board'
         else "LED0 A20 heartbeat; LED1 C18 PLL lock; LED2 C19 error; LED3 E18 init done.\n")+
        "KEY0 C22 active-low reset.\n"+
        ("One captured HDMI frame appears in two shared-preview windows after both CRCs pass.\n" if target=='video_preview_board' else
         "Local HDMI color bars remain active during single-frame input capture.\n" if target=='video_hdmi_capture'
         else "Standalone DDR targets interrupt HDMI output.\n")+
        "Power board and connect PDS JTAG; scan target before programming.\n"
        "PDS Configuration: Scan Device, assign this .sbit to PG2L100H, Program, Verify.\n"
        "Keep the matching .smsk beside the .sbit; PDS Verify requires both files.\n"
        "Use volatile JTAG configuration; this package contains no Flash image.\n"
        f"Bitstream SHA256 {digest}\nVerification mask SHA256 {mask_digest}\n",encoding="utf-8")
    result={"status":"pass","target":target,"directory":str(package.relative_to(ROOT)),
                                         "bitstream_sha256":digest,"verify_mask_sha256":mask_digest,
                                         "physical_board":False}
    write_json(BUILD/"latest_package.json",result)
    write_json(BUILD/f"latest_package_{target}.json",result)
    print("VIDEO_PACKAGE_PASS:",package)
    return 0


if __name__=="__main__":
    raise SystemExit(main(sys.argv[1:]))
