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
    parser.add_argument("--suite", choices=("config", "timing", "clocks", "tx_init", "tx_init_full", "board", "rx", "rx_init", "rx_measure", "rx_board", "ddr_bist", "ddr_board", "axi_bridge", "write_dma", "axi_capture", "axi_capture_board", "capture_ingress", "capture_startup", "capture_pipe", "capture_engine", "hdmi_capture_board", "preview_scale", "preview_capture", "preview_display", "preview_crc", "preview_clocks", "preview_board", "detect_scale", "input_format", "detect_bilinear", "nchw_dma", "three_capture", "three_board", "capture_mmio", "cpu_axil", "all"), default="all")
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
        if args.suite in ('config','capture_mmio','all'):
            run_logged([sys.executable, ROOT/'scripts/video/gen_regs.py','--check'],work/'regs_check.log')
        if args.suite not in ("timing", "detect_scale", "input_format", "detect_bilinear", "nchw_dma", "three_capture", "capture_mmio", "cpu_axil"):
            run_logged([sys.executable, ROOT / "scripts/video/prepare_reference.py", "--reference", "hdmi"],
                       work / "reference_check.log")
        manifest_path = ROOT / "fpga/pg2l100h/project/video_timing.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        paths = [ROOT / relative for relative in manifest["sources"] + manifest["tests"]]
        paths += [manifest_path, ROOT / "config/video_cfg.json",
                  ROOT / "rtl/video/include/video_cfg.vh", ROOT / "sw/include/video_cfg.h"]
        paths += list((ROOT / "scripts/video").glob("*.py"))
        paths += list((ROOT / "tb/video").glob("test_*.py"))
        if args.suite in ('config','capture_mmio','all'):
            paths += [ROOT/'config/video_regs.json',ROOT/'rtl/video/include/video_regs.vh',
                      ROOT/'sw/include/video_regs.h']
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
        if args.suite in ('cpu_axil', 'all'):
            from common import sha256
            result['cpu_axil_tools'] = {}
            for name in ('iverilog', 'vvp'):
                executable = tool(name)
                version_log = work/(name+'_version.log')
                result['cpu_axil_tools'][name] = {
                    'path': str(executable), 'sha256': sha256(executable),
                    'version_log': version_log.relative_to(ROOT).as_posix()}
                run_logged([executable, '-V'], version_log)
            adapter_path = ROOT/'fpga/pg2l100h/project/cpu_native_axil.json'
            adapter = json.loads(adapter_path.read_text(encoding='utf-8'))
            paths = [ROOT/p for p in adapter['sources']+adapter['tests']]
            add_inputs(result, [adapter_path, *paths,
                               *[ROOT/p for p in adapter['constraints']]])
            log = simulate(work, 'cpu_native_axil', adapter['test_top'], paths, timeout=600)
            if 'CPU_NATIVE_AXIL_PASS' not in log:
                raise RuntimeError('Missing CPU_NATIVE_AXIL_PASS')
            artifacts = [work/('cpu_native_axil'+suffix) for suffix in
                         ('.vvp', '_compile.log', '_simulation.log')]
            artifacts += [work/(name+'_version.log') for name in ('iverilog', 'vvp')]
            result['cpu_axil_artifacts'] = input_hashes(artifacts)
            result['passed'].append('cpu_axil')
        if args.suite in ('capture_mmio','all'):
            mmio_path=ROOT/'fpga/pg2l100h/project/video_capture_mmio.json'
            mmio=json.loads(mmio_path.read_text(encoding='utf-8'))
            paths=[ROOT/p for p in mmio['sources']+mmio['tests']]
            add_inputs(result,[mmio_path,*paths,ROOT/'config/video_regs.json',
                              ROOT/'rtl/video/include/video_regs.vh',ROOT/'sw/include/video_regs.h'])
            for name,top,marker in [('capture_mmio',mmio['test_top'],'VIDEO_CAPTURE_MMIO_PASS'),
                                    ('capture_mmio_core',mmio['integration_test_top'],'VIDEO_CAPTURE_MMIO_CORE_PASS')]:
                log=simulate(work,name,top,paths,[ROOT/'rtl/video/include'],timeout=600)
                if marker not in log:raise RuntimeError('Missing '+marker)
            run_logged([sys.executable,'-m','unittest','discover','-s',ROOT/'tb/video',
                        '-p','test_video_regs.py','-v'],work/'regs_python.log')
            result['passed'].append('capture_mmio')
        if args.suite in ('three_capture','all'):
            manifest_path=ROOT/'fpga/pg2l100h/project/video_three_capture.json'
            three=json.loads(manifest_path.read_text(encoding='utf-8'))
            paths=[ROOT/p for p in three['sources']]
            tests=[ROOT/p for p in three['tests']]
            includes=[ROOT/'rtl/video/include']
            add_inputs(result,[manifest_path,*paths,*tests,ROOT/'tb/video/check_three_capture_dump.py',
                ROOT/'tb/video/check_bilinear_dump.py',ROOT/'fpga/pg2l100h/constraints/video_three_capture.fdc'])
            log=simulate(work,'three_arbiter','tb_axi_write_arbiter3',
                [ROOT/'rtl/video/axi_write_arbiter3.sv',ROOT/'tb/video/tb_axi_write_arbiter3.sv'])
            if 'PASS tb_axi_write_arbiter3' not in log:raise RuntimeError('Missing three-master arbiter pass')
            for width,height,top,bottom in ((10,10,0,0),(30,20,2,1),(40,30,4,5)):
                log=simulate(work,f'three_{width}_{height}','tb_video_three_branch_capture',paths+[tests[0]],includes,
                    parameters=(('W',width),('H',height),('PT',top),('PB',bottom)),timeout=600)
                if 'VIDEO_THREE_CAPTURE_PASS' not in log:raise RuntimeError('Missing same-frame three-branch pass')
            for case in range(1,30):
                log=simulate(work,f'three_case_{case}','tb_video_three_branch_capture',paths+[tests[0]],includes,
                    run_args=(f'+CASE={case}',),timeout=120)
                if 'VIDEO_THREE_CAPTURE_PASS' not in log:raise RuntimeError('Missing three-branch control pass')
            invalid=({'W':0},{'W':5},{'W':810},{'W':2147483647},{'H':0},{'H':15},{'H':610},
                {'PT':-1},{'PB':-1},{'PT':2147483647},{'PT':2147483647,'PB':2147483647},
                {'W':800,'H':600,'PT':2048},{'TC':0},{'TC':-1})
            for index,parameters in enumerate(invalid):
                log=simulate(work,f'three_invalid_{index}','tb_three_capture_parameters',paths+[tests[2]],includes,
                    parameters=tuple(parameters.items()))
                if 'THREE_CAPTURE_PARAMETERS_PASS' not in log:raise RuntimeError('Missing safe parameter rejection')
            log=simulate(work,'three_full','tb_video_three_branch_capture',paths+[tests[0]],includes,
                parameters=(('W',800),('H',600),('PT',40),('PB',40)),
                run_args=('+normal_only',f'+DUMP={(work/"three_input.hex").as_posix()}'),timeout=600)
            if 'VIDEO_THREE_CAPTURE_PASS' not in log:raise RuntimeError('Missing full same-frame capture pass')
            log=run_logged([sys.executable,ROOT/'tb/video/check_three_capture_dump.py','--path',work/'three_input.hex'],work/'three_golden.log')
            if 'THREE_CAPTURE_DUMP_PASS' not in log:raise RuntimeError('Missing three-branch hardware golden pass')
            result['passed'].append('three_capture')
        if args.suite in ('nchw_dma','all'):
            paths=[ROOT/p for p in ('rtl/video/detect_bilinear.sv','rtl/video/detect_nchw_dma.sv',
                'rtl/video/video_write_dma.sv','tb/video/tb_detect_nchw_dma.sv')]
            add_inputs(result,[*paths,ROOT/'tb/video/check_nchw_dump.py',ROOT/'tb/video/check_bilinear_dump.py',
                ROOT/'tb/video/tb_nchw_parameters.sv',
                ROOT/'fpga/pg2l100h/project/video_nchw_dma.json',
                ROOT/'fpga/pg2l100h/constraints/video_nchw_dma.fdc'])
            for width,active,top,bottom,gap in ((1,1,0,0,0),(3,2,1,3,16),(16,3,0,0,0),
                                               (17,3,2,1,16),(320,240,40,40,0)):
                log=simulate(work,f'nchw_{width}','tb_detect_nchw_dma',paths,
                    parameters=(('W',width),('AH',active),('PT',top),('PB',bottom),('GAP',gap)),timeout=600)
                if 'DETECT_NCHW_DMA_PASS' not in log:raise RuntimeError('Missing NCHW DMA pass marker')
            for case in range(1,34):
                log=simulate(work,f'nchw_case_{case}','tb_detect_nchw_dma',paths,
                    run_args=(f'+CASE={case}',),timeout=600)
                if 'DETECT_NCHW_DMA_PASS' not in log:raise RuntimeError('Missing NCHW failure/reuse pass marker')
            invalid_parameters=({'W':0},{'W':2049},{'AH':0},{'PT':-1},{'PB':-1},
                {'PT':2048},{'RS':1},{'RS':17},{'RS':65552},{'PS':0},{'PS':17},
                {'PT':2147483647,'PS':0},{'PT':2147483647,'PB':2147483647,'AH':2,'PS':0})
            for index,parameters in enumerate(invalid_parameters):
                name=f'nchw_invalid_{index}'
                binary=work/(name+'.vvp')
                run_logged([tool('iverilog'),'-g2012','-Wall','-s','tb_nchw_parameters',
                    *[f'-Ptb_nchw_parameters.{key}={value}' for key,value in parameters.items()],
                    '-o',binary,ROOT/'rtl/video/detect_nchw_dma.sv',ROOT/'rtl/video/video_write_dma.sv',
                    ROOT/'tb/video/tb_nchw_parameters.sv'],work/(name+'_compile.log'))
                try:
                    run_logged([tool('vvp'),binary],work/(name+'_rejection.log'))
                except RuntimeError:
                    if 'invalid NCHW geometry/stride' not in (work/(name+'_rejection.log')).read_text(encoding='utf-8'):
                        raise
                else:raise RuntimeError('Invalid NCHW parameters accepted')
            log=simulate(work,'nchw_bilinear','tb_detect_nchw_dma',paths,
                parameters=(('W',320),('AH',240),('PT',40),('PB',40),('GAP',0),('BILINEAR',1)),
                run_args=(f'+DUMP={(work/"nchw").as_posix()}',),timeout=600)
            if 'DETECT_NCHW_DMA_PASS' not in log:raise RuntimeError('Missing bilinear NCHW chain pass marker')
            log=run_logged([sys.executable,ROOT/'tb/video/check_nchw_dump.py','--prefix',work/'nchw'],work/'nchw_goldens.log')
            if 'DETECT_NCHW_DUMP_PASS' not in log:raise RuntimeError('Missing hardware NCHW golden pass marker')
            result['passed'].append('nchw_dma')
        if args.suite in ('detect_bilinear','all'):
            paths=[ROOT/'rtl/video/detect_bilinear.sv',ROOT/'tb/video/tb_detect_bilinear.sv']
            add_inputs(result,[*paths,ROOT/'tb/video/check_bilinear_dump.py',
                ROOT/'scripts/video/yunet_input_reference.py',ROOT/'tb/video/test_yunet_input_reference.py',
                ROOT/'fpga/pg2l100h/project/video_detect_bilinear.json',
                ROOT/'fpga/pg2l100h/constraints/video_detect_bilinear.fdc'])
            for width,height,case in ((5,5,0),(15,10,0),(25,15,0),(800,600,0),(2045,5,0),(5,2045,0),
                                       (5,5,1),(15,10,1),(5,5,2),(15,10,2)):
                dump=(f'+DUMP={(work/"bilinear").as_posix()}',) if (width,height,case)==(800,600,0) else ()
                log=simulate(work,f'bilinear_{width}_{height}_{case}','tb_detect_bilinear',paths,
                    parameters=(('W',width),('H',height),('CASE',case)),run_args=dump,timeout=600)
                if 'DETECT_BILINEAR_PASS' not in log:raise RuntimeError('Missing bilinear component pass marker')
            log=run_logged([sys.executable,ROOT/'tb/video/check_bilinear_dump.py','--prefix',work/'bilinear'],work/'bilinear_goldens.log')
            if 'DETECT_BILINEAR_DUMP_PASS' not in log:raise RuntimeError('Missing bilinear OpenCV golden pass marker')
            result['passed'].append('detect_bilinear')
        if args.suite in ('input_format','all'):
            units=('detect_input_pad','detect_c8_pack')
            paths=[ROOT/('rtl/video/'+n+'.sv') for n in units]
            tests=[ROOT/('tb/video/tb_'+n+'.sv') for n in units]
            dma=[ROOT/'rtl/video/detect_downscale.sv',*paths,ROOT/'rtl/video/video_write_dma.sv',
                 ROOT/'tb/video/tb_detect_input_dma.sv']
            add_inputs(result,[*paths,*tests,*dma,ROOT/'scripts/video/input_format_reference.py',
                ROOT/'tb/video/test_input_format_reference.py',ROOT/'fpga/pg2l100h/project/video_input_pad.json',
                ROOT/'fpga/pg2l100h/project/video_c8_pack.json',ROOT/'fpga/pg2l100h/constraints/video_input_format.fdc'])
            for unit,source,test in zip(units,paths,tests):
                for width,active,height,case in ((1,1,1,0),(3,2,4,0),(4,3,5,0),(257,1,2,0),
                                                 (160,120,128,0),(3,2,4,1),(3,2,4,2)):
                    top='tb_'+unit
                    log=simulate(work,f'{unit}_{width}_{active}_{height}_{case}',top,[source,test],
                        parameters=(('W',width),('AH',active),('H',height),('CASE',case)),timeout=600)
                    if unit.upper()+'_PASS' not in log:raise RuntimeError('Missing input format pass marker')
            for width,height,padded in ((5,5,1),(15,10,4),(20,15,5),(800,600,128)):
                log=simulate(work,f'input_dma_{width}_{height}_{padded}','tb_detect_input_dma',dma,
                    parameters=(('FW',width),('FH',height),('PH',padded)),timeout=600)
                if 'DETECT_INPUT_DMA_PASS' not in log:raise RuntimeError('Missing input tensor DMA pass marker')
            log=run_logged([sys.executable,ROOT/'tb/video/test_input_format_reference.py'],work/'input_format_reference.log')
            if 'OK' not in log:raise RuntimeError('Missing format reference pass marker')
            result['passed'].append('input_format')
        if args.suite in ('detect_scale','all'):
            paths=[ROOT/p for p in ('rtl/video/detect_downscale.sv','tb/video/tb_detect_downscale.sv')]
            add_inputs(result,[*paths,ROOT/'fpga/pg2l100h/project/video_detect_scale.json',
                ROOT/'fpga/pg2l100h/constraints/video_detect_scale.fdc',
                ROOT/'scripts/video/detect_reference.py',ROOT/'tb/video/test_detect_reference.py'])
            for width,height,case in ((5,5,0),(15,10,0),(25,15,0),(800,600,0),
                                      (5,5,1),(15,10,2),(15,10,3)):
                log=simulate(work,f'detect_scale_{width}_{height}_{case}','tb_detect_downscale',paths,
                    parameters=(('W',width),('H',height),('CASE',case)),timeout=600)
                if 'DETECT_DOWNSCALE_PASS' not in log:raise RuntimeError('Missing detector scaler pass marker')
            log=run_logged([sys.executable,ROOT/'tb/video/test_detect_reference.py'],work/'detect_reference.log')
            if 'OK' not in log:raise RuntimeError('Missing detector reference pass marker')
            result['passed'].append('detect_scale')
        if args.suite in ('preview_clocks','all'):
            paths=[ROOT/p for p in ('fpga/pg2l100h/rtl/video_preview_clock_reset.sv',
                'tb/video/models/video_pll_model.sv','tb/video/tb_video_preview_clock_reset.sv')]
            add_inputs(result,paths)
            for held in (0,1):
                log=simulate(work,f'preview_clocks_{held}','tb_video_preview_clock_reset',paths,
                    parameters=(('HOLD_KEY0_AT_BOOT',held),))
                if 'VIDEO_PREVIEW_CLOCK_RESET_PASS' not in log:raise RuntimeError('Missing preview clock/reset pass marker')
            result['passed'].append('preview_clocks')
        if args.suite in ('capture_pipe','all'):
            paths=[ROOT/p for p in ('rtl/video/video_stream_register.sv','tb/video/tb_video_stream_register.sv')]
            add_inputs(result,paths)
            for width in (1,48):
                log=simulate(work,f'capture_pipe_{width}','tb_video_stream_register',paths,
                             parameters=(('TEST_WIDTH',width),))
                if 'VIDEO_STREAM_REGISTER_PASS' not in log:raise RuntimeError('Missing stream register pass marker')
            result['passed'].append('capture_pipe')
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
        if args.suite in ('three_board','all'):
            target=ROOT/'fpga/pg2l100h/project/video_three_board.json'
            board=json.loads(target.read_text(encoding='utf-8'))
            paths=[ROOT/p for p in board['sources']+board['tests']]
            vendor=[ROOT/'build/video/vendor/hdmi'/p for p in board['vendor_sources']]
            extra=[ROOT/'tb/video/tb_video_frame_crc_checksum.sv',ROOT/'tb/video/tb_video_three_engine.sv',
                   ROOT/'tb/video/models/axi_bridge_native_model.sv',ROOT/'tb/video/tb_video_three_throughput.sv']
            add_inputs(result,[target,*paths,*vendor,*extra,ROOT/'config/video_edid.hex',ROOT/'rtl/video/include/video_edid.vh',
                ROOT/'tb/video/check_three_capture_dump.py',ROOT/'tb/video/check_bilinear_dump.py'])
            log=simulate(work,'three_checksum','tb_video_frame_crc_checksum',
                [ROOT/'rtl/video/video_frame_crc_reader.sv',extra[0]],timeout=120)
            if 'VIDEO_FRAME_CRC_CHECKSUM_PASS' not in log:raise RuntimeError('Missing input checksum pass marker')
            engine_sources=[p for p in paths if p.suffix=='.sv' and not p.name.startswith('tb_')
                            and p.name not in ('video_three_board_top.sv','ddr_board_ip_model.sv','video_pll_model.sv')]
            for case in range(22):
                log=simulate(work,f'three_engine_{case}','tb_video_three_engine',engine_sources+extra[1:3],
                    [ROOT/'rtl/video/include'],timeout=600,run_args=(f'+CASE={case}',))
                if 'VIDEO_THREE_ENGINE_PASS' not in log:raise RuntimeError('Missing three-branch engine pass marker')
            log=simulate(work,'three_board',board['test_top'],paths+vendor,[ROOT/'rtl/video/include'],timeout=600)
            if 'VIDEO_THREE_BOARD_PASS' not in log:raise RuntimeError('Missing three-branch board pass marker')
            throughput_sources=[ROOT/p for p in board['sources'] if p.startswith('rtl/video/') and
                Path(p).name not in ('video_timing.sv','video_rx.sv','video_rx_measure.sv','video_capture_startup_guard.sv',
                                     'video_frame_crc_reader.sv','preview_display.sv','video_three_engine.sv')]
            log=simulate(work,'three_throughput','tb_video_three_throughput',throughput_sources+[extra[3]],
                [ROOT/'rtl/video/include'],timeout=600,run_args=(f'+DUMP={(work/"three_rate_input.hex").as_posix()}',))
            if 'VIDEO_THREE_THROUGHPUT_PASS' not in log:raise RuntimeError('Missing physical-rate candidate throughput pass')
            run_logged([sys.executable,ROOT/'tb/video/check_three_capture_dump.py','--path',work/'three_rate_input.hex'],
                work/'three_rate_golden.log')
            result['passed'].append('three_board')
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
        for name, record in result.get('cpu_axil_tools', {}).items():
            if sha256(record['path']) != record['sha256']:
                raise RuntimeError('CPU AXI-Lite simulation tool changed during regression: '+name)
        for name, expected in result.get('cpu_axil_artifacts', {}).items():
            if sha256(ROOT/name) != expected:
                raise RuntimeError('CPU AXI-Lite artifact changed during regression: '+name)
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
