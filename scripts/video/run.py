"""Run the available Video regression suites using native Python/Icarus."""
import argparse
import json
from pathlib import Path
import sys

from common import BUILD, ROOT, fresh_run, input_hashes, run_logged, tool, write_json
from gen_pll import generate as generate_pll


def add_inputs(result,paths):
    incoming=input_hashes(paths)
    changed=[name for name,digest in incoming.items()
             if name in result['inputs'] and result['inputs'][name]!=digest]
    if changed:raise RuntimeError('Inputs changed between suites: '+', '.join(changed))
    result['inputs'].update(incoming)


def simulate(work, name, top, sources, includes=(), defines=(), timeout=120, parameters=(), run_args=()):
    binary = work / (name + ".vvp")
    command = [tool("iverilog"), "-g2012", "-Wall", "-s", top, "-o", binary]
    for directory in includes:
        command += ["-I", directory]
    command += ["-D"+define for define in defines]
    command += [f"-P{top}.{key}={value}" for key,value in parameters]
    run_logged(command + list(sources), work / (name + "_compile.log"))
    return run_logged([tool("vvp"), binary, *run_args], work / (name + "_simulation.log"), timeout=timeout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=("config", "timing", "clocks", "tx_init", "tx_init_full", "board", "rx", "rx_init", "rx_measure", "rx_board", "ddr_bist", "ddr_board", "axi_bridge", "write_dma", "axi_capture", "axi_capture_board", "capture_ingress", "capture_startup", "capture_engine", "hdmi_capture_board", "preview_scale", "preview_capture", "preview_display", "preview_crc", "preview_board", "all"), default="all")
    args = parser.parse_args()
    work = fresh_run("regression")
    latest = BUILD / f"latest_{args.suite}.json"
    result = {"status": "running", "suite": args.suite,
              "directory": str(work.relative_to(ROOT)), "passed": [],
              "physical_board": False, "vendor_ddr_training": False}
    write_json(latest, result)  # Invalidate an earlier PASS before doing any work.
    try:
        run_logged([sys.executable, ROOT / "scripts/video/gen_config.py", "--check"],
                   work / "config_check.log")
        if args.suite != "timing":
            run_logged([sys.executable, ROOT / "scripts/video/prepare_reference.py", "--reference", "hdmi"],
                       work / "reference_check.log")
        manifest_path = ROOT / "fpga/pg2l100h/project/video_timing.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        paths = [ROOT / relative for relative in manifest["sources"] + manifest["tests"]]
        paths += [manifest_path, ROOT / "config/video_cfg.json",
                  ROOT / "rtl/video/include/video_cfg.vh", ROOT / "sw/include/video_cfg.h"]
        paths += list((ROOT / "scripts/video").glob("*.py"))
        paths += list((ROOT / "tb/video").glob("test_*.py"))
        if args.suite in ("clocks", "board", "tx_init", "tx_init_full", "rx", "rx_init", "rx_measure", "rx_board", "all"):
            paths += list((ROOT / "fpga/pg2l100h/rtl").glob("*.sv"))
            paths += list((ROOT / "tb/video").glob("*.sv"))
            paths += list((ROOT / "tb/video/models").glob("*.sv"))
            paths += [ROOT / "fpga/pg2l100h/ip/video_pll.json",
                      ROOT / "fpga/pg2l100h/ip/video_reference_manifest.json"]
        result["inputs"] = input_hashes(set(paths))
        if args.suite in ("rx", "all"):
            add_inputs(result,[ROOT / "rtl/video/video_rx.sv", ROOT / "fpga/pg2l100h/project/video_rx.json"])
        result["python"] = sys.version.split()[0]
        if args.suite in ('capture_startup','all'):
            paths=[ROOT/p for p in ('rtl/video/video_capture_startup_guard.sv',
                                   'tb/video/tb_video_capture_startup_guard.sv')]
            add_inputs(result,paths)
            for frames in (1,2,128):
                log=simulate(work,f'capture_startup_{frames}','tb_video_capture_startup_guard',paths,
                             parameters=(('TEST_FRAMES',frames),))
                if 'VIDEO_CAPTURE_STARTUP_GUARD_PASS' not in log:raise RuntimeError('Missing capture startup guard pass marker')
            result['passed'].append('capture_startup')
        if args.suite in ('preview_scale','all'):
            paths=[ROOT/p for p in ('rtl/video/preview_downscale.sv','tb/video/tb_preview_downscale.sv')]
            add_inputs(result,paths)
            log=simulate(work,'preview_scale','tb_preview_downscale',paths,timeout=600)
            if 'PREVIEW_DOWNSCALE_PASS' not in log:raise RuntimeError('Missing preview scaler pass marker')
            result['passed'].append('preview_scale')
        if args.suite in ('preview_capture','all'):
            paths=[ROOT/p for p in ('rtl/video/preview_downscale.sv','rtl/video/rgb888_packer.sv',
                'rtl/video/video_write_dma.sv','rtl/video/video_preview_capture.sv','tb/video/tb_video_preview_capture.sv')]
            add_inputs(result,paths)
            for width,height in ((2,2),(26,6),(32,6),(800,600)):
                name=f'preview_capture_{width}_{height}'
                log=simulate(work,name,'tb_video_preview_capture',paths,timeout=600,
                    parameters=(('TEST_WIDTH',width),('TEST_HEIGHT',height)),
                    run_args=('+normal_only',) if width==800 else ())
                if 'VIDEO_PREVIEW_CAPTURE_PASS' not in log:raise RuntimeError('Missing dual capture pass marker')
            result['passed'].append('preview_capture')
        if args.suite in ('preview_display','all'):
            paths=[ROOT/p for p in ('rtl/video/preview_display.sv','tb/video/tb_preview_display.sv')]
            add_inputs(result,paths)
            scenarios=[(f'case_{mode}',0,(f'+CASE={mode}',)) for mode in range(27)]
            scenarios += [('ratio_fast',0,('+CORE_HALF=3','+PIXEL_HALF=10.5')),
                          ('ratio_slow',0,('+CORE_HALF=5','+PIXEL_HALF=16.5')),('invalid_window',0,()),('full',1,())]
            for name,full,options in scenarios:
                log=simulate(work,'preview_display_'+name,'tb_preview_display',paths,timeout=600,
                    parameters=(('FULL',full),('INVALID_WINDOW',int(name=='invalid_window'))),run_args=options)
                if 'PASS preview_display' not in log:raise RuntimeError('Missing shared display pass marker')
            result['passed'].append('preview_display')
        if args.suite in ('preview_crc','all'):
            paths=[ROOT/p for p in ('rtl/video/video_frame_crc_reader.sv','tb/video/tb_video_frame_crc_reader.sv')]
            add_inputs(result,paths)
            log=simulate(work,'preview_crc','tb_video_frame_crc_reader',paths,timeout=600)
            if 'VIDEO_FRAME_CRC_READER_PASS' not in log:raise RuntimeError('Missing plane CRC pass marker')
            result['passed'].append('preview_crc')
        if args.suite in ('preview_board','all'):
            target=ROOT/'fpga/pg2l100h/project/video_preview_board.json'
            preview=json.loads(target.read_text(encoding='utf-8'))
            paths=[ROOT/p for p in preview['sources']+preview['tests']]
            vendor=[ROOT/'build/video/vendor/hdmi'/p for p in preview['vendor_sources']]
            add_inputs(result,[target,*paths,*vendor,ROOT/'config/video_edid.hex',ROOT/'rtl/video/include/video_edid.vh'])
            log=simulate(work,'preview_board',preview['test_top'],paths+vendor,[ROOT/'rtl/video/include'],timeout=600)
            if 'VIDEO_PREVIEW_BOARD_PASS' not in log:raise RuntimeError('Missing preview board pass marker')
            result['passed'].append('preview_board')
        if args.suite in ('capture_ingress','all'):
            paths=[ROOT/p for p in ('rtl/video/video_async_fifo.sv','rtl/video/video_capture_ingress.sv',
                                   'tb/video/tb_video_async_fifo.sv','tb/video/tb_video_capture_ingress.sv')]
            add_inputs(result,paths)
            for address_width,write_half,read_half,phase in ((1,5,7,2),(3,3,11,1),(3,13,2,4),(4,5,5,0),(11,12,4,1)):
                name=f'capture_fifo_{address_width}_{write_half}_{read_half}'
                binary=work/(name+'.vvp')
                run_logged([tool('iverilog'),'-g2012','-Wall','-s','tb_video_async_fifo',
                    f'-Ptb_video_async_fifo.TEST_ADDR_WIDTH={address_width}',
                    f'-Ptb_video_async_fifo.WR_HALF={write_half}',f'-Ptb_video_async_fifo.RD_HALF={read_half}',
                    f'-Ptb_video_async_fifo.RD_PHASE={phase}','-o',binary,*paths],work/(name+'_compile.log'))
                log=run_logged([tool('vvp'),binary],work/(name+'_simulation.log'),timeout=600)
                if 'VIDEO_ASYNC_FIFO_PASS' not in log:raise RuntimeError('Missing async FIFO pass marker')
            for width,height,address_width in ((5,3,4),(9,1,3),(13,3,3),(13,3,6)):
                name=f'capture_ingress_{width}_{height}_{address_width}'
                binary=work/(name+'.vvp')
                run_logged([tool('iverilog'),'-g2012','-Wall','-s','tb_video_capture_ingress',
                    f'-Ptb_video_capture_ingress.TEST_WIDTH={width}',f'-Ptb_video_capture_ingress.TEST_HEIGHT={height}',
                    f'-Ptb_video_capture_ingress.TEST_FIFO_ADDR_WIDTH={address_width}',
                    '-o',binary,*paths],work/(name+'_compile.log'))
                log=run_logged([tool('vvp'),binary],work/(name+'_simulation.log'),timeout=600)
                if 'VIDEO_CAPTURE_INGRESS_PASS' not in log:raise RuntimeError('Missing capture ingress pass marker')
            result['passed'].append('capture_ingress')
        if args.suite in ('capture_engine','all'):
            paths=[ROOT/p for p in ('rtl/video/video_async_fifo.sv','rtl/video/video_capture_ingress.sv',
                'rtl/video/axi128_hmic256.sv','rtl/video/rgb888_packer.sv','rtl/video/video_write_dma.sv',
                'rtl/video/video_capture_engine.sv','tb/video/tb_video_capture_engine.sv')]
            add_inputs(result,paths)
            for width,height in ((13,3),(16,3),(1367,3),(800,600)):
                name=f'capture_engine_{width}_{height}'
                binary=work/(name+'.vvp')
                run_logged([tool('iverilog'),'-g2012','-Wall','-s','tb_video_capture_engine',
                    f'-Ptb_video_capture_engine.TEST_WIDTH={width}',f'-Ptb_video_capture_engine.TEST_HEIGHT={height}',
                    '-o',binary,*paths],work/(name+'_compile.log'))
                command=[tool('vvp'),binary]
                if width==800:command.append('+normal_only')
                log=run_logged(command,work/(name+'_simulation.log'),timeout=600)
                if 'VIDEO_CAPTURE_ENGINE_PASS' not in log:raise RuntimeError('Missing physical capture engine pass marker')
            result['passed'].append('capture_engine')
        if args.suite in ('hdmi_capture_board','all'):
            target=ROOT/'fpga/pg2l100h/project/video_hdmi_capture.json'
            capture=json.loads(target.read_text(encoding='utf-8'))
            paths=[ROOT/p for p in capture['sources']+capture['tests']]
            vendor=[ROOT/'build/video/vendor/hdmi'/p for p in capture['vendor_sources']]
            add_inputs(result,[target,*paths,*vendor,ROOT/'config/video_edid.hex',ROOT/'rtl/video/include/video_edid.vh'])
            run_logged([sys.executable,ROOT/'scripts/video/gen_edid.py','--check'],work/'capture_edid_check.log')
            log=simulate(work,'hdmi_capture_board',capture['test_top'],paths+vendor,
                         [ROOT/'rtl/video/include'],timeout=600)
            if 'VIDEO_HDMI_CAPTURE_BOARD_PASS' not in log:raise RuntimeError('Missing HDMI capture board pass marker')
            result['passed'].append('hdmi_capture_board')
        if args.suite in ('axi_bridge','all'):
            paths=[ROOT/p for p in ('rtl/video/axi128_hmic256.sv',
                'tb/video/models/axi_bridge_native_model.sv','tb/video/tb_axi128_hmic256.sv')]
            add_inputs(result,paths)
            log=simulate(work,'axi_bridge','tb_axi128_hmic256',paths,timeout=600)
            if 'AXI128_HMIC256_PASS' not in log:raise RuntimeError('Missing bridge pass marker')
            result['passed'].append('axi_bridge')
        if args.suite in ('write_dma','all'):
            for name,source,marker in (
                ('rgb888_packer','rgb888_packer','RGB888_PACKER_PASS'),
                ('write_dma','video_write_dma','VIDEO_WRITE_DMA_PASS')):
                paths=[ROOT/f'rtl/video/{source}.sv',ROOT/f'tb/video/tb_{name}.sv']
                add_inputs(result,paths)
                log=simulate(work,name,'tb_'+name,paths,timeout=600)
                if marker not in log:raise RuntimeError('Missing pass marker: '+name)
            paths=[ROOT/'rtl/video/rgb888_packer.sv',
                   ROOT/'tb/video/models/rgb888_packer_legacy_model.sv',
                   ROOT/'tb/video/tb_rgb888_packer_serial.sv']
            add_inputs(result,paths)
            log=simulate(work,'rgb888_packer_serial','tb_rgb888_packer_serial',paths,timeout=600)
            if 'RGB888_PACKER_SERIAL_PASS' not in log:raise RuntimeError('Missing serial packer pass marker')
            result['passed'].append('write_dma')
        if args.suite in ('axi_capture','axi_capture_board','all'):
            manifest_axi_path=ROOT/'fpga/pg2l100h/project/video_axi_capture.json'
            manifest_axi=json.loads(manifest_axi_path.read_text(encoding='utf-8'))
            paths=[ROOT/p for p in manifest_axi['sources']]
            add_inputs(result,[manifest_axi_path,*paths])
            if args.suite in ('axi_capture','all'):
                test_paths=[ROOT/'tb/video/tb_axi_capture_bist.sv']
                add_inputs(result,test_paths)
                for width,height in ((13,3),(16,3),(1367,3),(800,600)):
                    name=f'axi_capture_{width}_{height}'
                    binary=work/(name+'.vvp')
                    run_logged([tool('iverilog'),'-g2012','-Wall','-s','tb_axi_capture_bist',
                        f'-Ptb_axi_capture_bist.TEST_WIDTH={width}',f'-Ptb_axi_capture_bist.TEST_HEIGHT={height}',
                        '-o',binary,*paths,*test_paths],work/(name+'_compile.log'))
                    command=[tool('vvp'),binary]
                    if width==800:command.append('+normal_only')
                    log=run_logged(command,work/(name+'_simulation.log'),timeout=600)
                    if 'VIDEO_AXI_CAPTURE_BIST_PASS' not in log:raise RuntimeError('Missing capture engine pass marker')
                result['passed'].append('axi_capture')
            if args.suite in ('axi_capture_board','all'):
                test_paths=[ROOT/p for p in manifest_axi['tests']]
                add_inputs(result,test_paths)
                log=simulate(work,'axi_capture_board',manifest_axi['test_top'],paths+test_paths,timeout=600)
                if 'VIDEO_AXI_CAPTURE_BOARD_PASS' not in log:raise RuntimeError('Missing capture board pass marker')
                result['passed'].append('axi_capture_board')
        if args.suite in ('ddr_bist','ddr_board','all'):
            add_inputs(result,[
                ROOT/'rtl/video/ddr_native_bist.sv',
                ROOT/'fpga/pg2l100h/rtl/video_ddr_bist_top.sv',
                ROOT/'fpga/pg2l100h/rtl/video_diag_uart.sv',
                *list((ROOT/'tb/video').glob('*ddr*.sv')),
                *list((ROOT/'tb/video/models').glob('*ddr*.sv'))])
        if args.suite in ('ddr_bist','all'):
            for window,burst in ((1,1),(2,2),(3,3),(5,2),(17,16),(33,16),(37,15),(137,7)):
                binary=work/f'ddr_bist_{window}_{burst}.vvp'
                run_logged([tool('iverilog'),'-g2012','-Wall','-s','tb_ddr_native_bist',
                    f'-Ptb_ddr_native_bist.TEST_WINDOW_BEATS={window}',
                    f'-Ptb_ddr_native_bist.TEST_BURST_BEATS={burst}','-o',binary,
                    ROOT/'rtl/video/ddr_native_bist.sv',ROOT/'tb/video/models/ddr_native_model.sv',
                    ROOT/'tb/video/tb_ddr_native_bist.sv'],work/f'ddr_bist_{window}_{burst}_compile.log')
                log=run_logged([tool('vvp'),binary],work/f'ddr_bist_{window}_{burst}_simulation.log',timeout=600)
                if 'PASS tb_ddr_native_bist' not in log:raise RuntimeError('Missing DDR BIST pass marker')
            result['passed'].append('ddr_bist')
        if args.suite in ('ddr_board','all'):
            path=ROOT/'fpga/pg2l100h/project/video_ddr_bist.json'
            ddr=json.loads(path.read_text(encoding='utf-8'))
            paths=[ROOT/p for p in ddr['sources']+ddr['tests']]
            add_inputs(result,[path,*paths])
            log=simulate(work,'ddr_board','tb_ddr_board',paths,timeout=600)
            if 'VIDEO_DDR_BOARD_PASS' not in log:raise RuntimeError('Missing DDR board pass marker')
            result['passed'].append('ddr_board')
        if args.suite in ("config", "all"):
            run_logged([sys.executable, "-m", "unittest", "discover", "-s",
                        ROOT / "tb/video", "-p", "test_*.py", "-v"], work / "python.log")
            result["passed"].append("config")
        if args.suite in ("timing", "all"):
            iverilog, vvp = tool("iverilog"), tool("vvp")
            result["iverilog_version"] = run_logged(
                [iverilog, "-V"], work / "iverilog_version.log").splitlines()[0]
            result["vvp_version"] = run_logged(
                [vvp, "-V"], work / "vvp_version.log").splitlines()[0]
            binary = work / "timing.vvp"
            run_logged([iverilog, "-g2012", "-Wall", "-I",
                        ROOT / "rtl/video/include", "-s", manifest["test_top"],
                        "-o", binary, *[ROOT / name for name in manifest["sources"]],
                        *[ROOT / name for name in manifest["tests"]]], work / "compile.log")
            log = run_logged([vvp, binary], work / "simulation.log")
            if "VIDEO_TIMING_PASS" not in log:
                raise RuntimeError("Missing VIDEO_TIMING_PASS marker")
            result["passed"].append("timing")
        if args.suite in ("clocks", "all"):
            _, wrapper = generate_pll(work / "ip/video_pll")
            library = tool("pds_shell").parent.parent / "arch/vendor/pango/verilog/simulation"
            primitives = [library / "GTP_GPLL.v", library / "GTP_CLKBUFG.v"]
            from common import sha256
            result["pll_model_inputs"] = {str(path): sha256(path) for path in [wrapper, *primitives]}
            for name, top, extra, marker in (
                ("pll", "tb_pll", [], "VIDEO_PLL_PASS"),
                ("clock_reset", "tb_clock_reset", [ROOT / "fpga/pg2l100h/rtl/video_clock_reset.sv"],
                 "VIDEO_CLOCK_RESET_PASS")):
                log = simulate(work, name, top, [ROOT / f"tb/video/{top}.sv", wrapper,
                                                *primitives, *extra])
                if marker not in log:
                    raise RuntimeError("Missing " + marker)
            result["passed"].append("clocks")
        vendor = ROOT / "build/video/vendor/hdmi/source/hdmi"
        if args.suite in ("rx_init", "rx_board", "all"):
            run_logged([sys.executable, ROOT/"scripts/video/gen_edid.py", "--check"], work/"edid_check.log")
            add_inputs(result,[ROOT/"config/video_edid.hex",ROOT/"rtl/video/include/video_edid.vh"])
        if args.suite in ("rx_init", "all"):
            log=simulate(work,"rx_init","tb_hdmi_rx_init",[
                ROOT/"fpga/pg2l100h/rtl/hdmi_rx_init.sv",vendor/"ms7200_ctl.v",vendor/"iic_dri.v",
                ROOT/"tb/video/tb_hdmi_rx_init.sv",ROOT/"tb/video/models/ms7200_i2c_model.sv"],
                [ROOT/"rtl/video/include"],timeout=600)
            if "HDMI_RX_INIT_PASS" not in log: raise RuntimeError("Missing HDMI_RX_INIT_PASS")
            result["passed"].append("rx_init")
        if args.suite in ("rx_measure", "all"):
            for name,source in [("rx_measure","rtl/video/video_rx_measure.sv"),
                                ("rx_probe","rtl/video/video_rx_probe.sv"),
                                ("rx_telemetry","fpga/pg2l100h/rtl/video_rx_telemetry.sv"),
                                ("diag_uart","fpga/pg2l100h/rtl/video_diag_uart.sv")]:
                add_inputs(result,[ROOT/source])
                log=simulate(work,name,"tb_"+name,[ROOT/source,ROOT/f"tb/video/tb_{name}.sv"],timeout=600)
                if f"VIDEO_{name.upper()}_PASS" not in log: raise RuntimeError("Missing pass marker: "+name)
            result["passed"].append("rx_measure")
        if args.suite in ("rx_board", "all"):
            target=ROOT/"fpga/pg2l100h/project/video_rx_board.json"
            rx_board=json.loads(target.read_text(encoding="utf-8"))
            paths=[ROOT/p for p in rx_board["sources"]+rx_board["tests"]]
            add_inputs(result,[target,*paths])
            log=simulate(work,"rx_board","tb_rx_board",[*paths,*[ROOT/"build/video/vendor/hdmi"/p for p in rx_board["vendor_sources"]]],
                         [ROOT/"rtl/video/include"],timeout=600)
            if "VIDEO_RX_BOARD_PASS" not in log: raise RuntimeError("Missing VIDEO_RX_BOARD_PASS")
            result["passed"].append("rx_board")
        tx_sources = [ROOT / "fpga/pg2l100h/rtl/hdmi_tx_init.sv",
                      vendor / "ms7210_ctl.v", vendor / "iic_dri.v"]
        if args.suite in ("tx_init", "tx_init_full", "all"):
            log = simulate(work, "tx_init", "tb_hdmi_tx_init",
                           [*tx_sources, ROOT / "tb/video/tb_hdmi_tx_init.sv",
                            ROOT / "tb/video/models/ms7210_i2c_model.sv"],
                           defines=["HDMI_TX_INIT_FULL_WAIT"] if args.suite=="tx_init_full" else [])
            if "HDMI_TX_INIT_PASS" not in log:
                raise RuntimeError("Missing HDMI_TX_INIT_PASS")
            result["passed"].append("tx_init_full" if args.suite=="tx_init_full" else "tx_init")
        if args.suite in ("board", "all"):
            board_path = ROOT / "fpga/pg2l100h/project/video_board_smoke.json"
            board = json.loads(board_path.read_text(encoding="utf-8"))
            from common import sha256
            add_inputs(result,[board_path])
            result["vendor_inputs"] = {str(path.relative_to(ROOT)): sha256(path)
                                       for path in tx_sources[1:]}
            log = simulate(work, "board", board["test_top"],
                           [*[ROOT / path for path in board["sources"] + board["tests"]],
                            *tx_sources[1:]], [ROOT / "rtl/video/include"])
            if "VIDEO_BOARD_SMOKE_PASS" not in log:
                raise RuntimeError("Missing VIDEO_BOARD_SMOKE_PASS")
            result["passed"].append("board")
        if args.suite in ("rx", "all"):
            rx=json.loads((ROOT / "fpga/pg2l100h/project/video_rx.json").read_text(encoding="utf-8"))
            log=simulate(work,"rx",rx["test_top"],
                         [ROOT / path for path in rx["sources"]+rx["tests"]],
                         [ROOT / "rtl/video/include"],timeout=600)
            if "VIDEO_RX_PASS" not in log:
                raise RuntimeError("Missing VIDEO_RX_PASS")
            result["passed"].append("rx")
        from common import sha256
        changed=[name for name,digest in result['inputs'].items() if sha256(ROOT/name)!=digest]
        if changed:raise RuntimeError('Inputs changed during regression: '+', '.join(changed))
        result["status"] = "pass"
    except Exception as error:
        result["status"] = "fail"
        result["error"] = str(error)
        print(str(error), file=sys.stderr)
    write_json(work / "result.json", result)
    write_json(latest, result)
    print(f"VIDEO_REGRESSION_{result['status'].upper()}: {work}")
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
