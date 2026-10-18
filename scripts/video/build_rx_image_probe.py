"""Build only the independent RX image probe, preserving preview build pointers."""
import argparse
import json
from pathlib import Path
import shutil
import sys

from common import ROOT,BUILD,fresh_run,input_hashes,run_logged,sha256,tool,write_json
from build_pds import tcl_path,review_messages
from gen_pll import generate as generate_pll
from run import simulate


def tests(work,manifest):
    frozen=[ROOT/p for p in manifest['sources']+manifest['tests']+[
        'fpga/pg2l100h/project/video_rx_image_probe.json','rtl/video/include/video_cfg.vh','rtl/video/include/video_edid.vh',
        'scripts/video/rx_image_probe.py','scripts/video/build_rx_image_probe.py','scripts/video/common.py','scripts/video/run.py',
        'tb/video/models/video_pll_model.sv','tb/video/models/ms7210_i2c_model.sv','tb/video/models/ms7200_i2c_model.sv']]
    hashes=input_hashes(frozen)
    paths=[ROOT/p for p in ('rtl/video/video_rx_image_probe.sv','tb/video/tb_video_rx_image_probe.sv')]
    output=simulate(work,'component','tb_video_rx_image_probe',paths)
    assert 'VIDEO_RX_IMAGE_PROBE_PASS' in output
    reference=json.loads((ROOT/'fpga/pg2l100h/ip/video_reference_manifest.json').read_text(encoding='utf-8'))
    expected={f['path']:f['sha256'] for f in reference['references']['hdmi']['files']}
    vendor=[ROOT/'build/video/vendor/hdmi'/p for p in manifest['vendor_sources']]
    assert all(sha256(p)==expected[p.relative_to(ROOT/'build/video/vendor/hdmi').as_posix()] for p in vendor)
    source=[ROOT/p for p in manifest['sources']]
    models=[ROOT/p for p in ('tb/video/models/video_pll_model.sv','tb/video/models/ms7210_i2c_model.sv','tb/video/models/ms7200_i2c_model.sv')]
    board_tb=ROOT/'tb/video/tb_video_rx_image_probe_board.sv'
    output=simulate(work,'board','tb_video_rx_image_probe_board',source+vendor+models+[board_tb],
        includes=[ROOT/'rtl/video/include'],timeout=600)
    assert 'VIDEO_RX_IMAGE_PROBE_BOARD_PASS' in output
    run_logged([sys.executable,'-m','unittest','discover','-s','tb/video','-p','test_rx_image_probe.py'],work/'decoder_tests.log')
    assert all(sha256(ROOT/p)==h for p,h in hashes.items()),'Test inputs changed while running'
    return {'status':'pass','inputs':hashes,
            'vendor_inputs':{str(p.relative_to(ROOT)):sha256(p) for p in vendor}}


def build(work,manifest):
    manifest_path=ROOT/'fpga/pg2l100h/project/video_rx_image_probe.json'
    names=manifest['sources']+manifest['constraints']+[
        manifest_path.relative_to(ROOT).as_posix(),'rtl/video/include/video_cfg.vh','rtl/video/include/video_edid.vh',
        'config/video_cfg.json','config/video_edid.hex','fpga/pg2l100h/ip/video_pll.json',
        'fpga/pg2l100h/ip/video_reference_manifest.json','scripts/video/build_rx_image_probe.py',
        'scripts/video/build_pds.py','scripts/video/common.py','scripts/video/gen_config.py','scripts/video/gen_pll.py','scripts/video/gen_edid.py']
    inputs=input_hashes([ROOT/p for p in names])
    assert json.loads(manifest_path.read_text(encoding='utf-8'))==manifest,'Manifest changed before freeze'
    for generator in ('gen_config.py','gen_edid.py'):
        run_logged([sys.executable,ROOT/'scripts/video'/generator,'--check'],work/(generator+'.log'))
    for name in names:
        destination=work/'src'/name;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/name,destination)
        assert sha256(destination)==inputs[name],'Source changed while copying: '+name
    reference=json.loads((ROOT/'fpga/pg2l100h/ip/video_reference_manifest.json').read_text(encoding='utf-8'))
    expected={f['path']:f['sha256'] for f in reference['references']['hdmi']['files']}
    _,pll=generate_pll(work/'ip/video_pll');vendor=[pll]
    for name in manifest['vendor_sources']:
        source=ROOT/'build/video/vendor/hdmi'/name
        assert sha256(source)==expected[name],name
        destination=work/'vendor'/name;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,destination);vendor.append(destination)
    top=manifest['top']
    lines=['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
    lines += ['add_design '+tcl_path(work/'src'/p) for p in manifest['sources']]
    lines += ['add_design '+tcl_path(p) for p in vendor]
    lines += ['add_constraint '+tcl_path(work/'src'/p) for p in manifest['constraints']]
    lines += [f'compile -system_verilog -top_module {top} -include_path {{'+tcl_path(work/'src/rtl/video/include')+'}',
              'synthesize -ads','dev_map','pnr -optimize_multi_corner_timing -fix_hold_violation','report_timing','gen_bit_stream -scbv {High Voltage}']
    script=work/'build.tcl';script.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    assert all(sha256(ROOT/p)==h for p,h in inputs.items()),'Inputs changed before PDS launch'
    version=run_logged([tool('pds_shell'),'-version'],work/'version.log').strip()
    log=run_logged([tool('pds_shell'),'-file',script,'-work_dir',work,'-project_name','video_rx_image_probe'],work/'build.log',cwd=work,timeout=900)
    ref_fdc=ROOT/'build/video/vendor/hdmi/HDMI_IN_DDR3_HDMI_OUT_top.fdc'
    assert sha256(ref_fdc)==expected[ref_fdc.name]
    approved,rejected=review_messages(log,ref_fdc.read_text(encoding='utf-8'))
    write_json(work/'message_review.json',{'reviewed_reference_pin_notices':approved,'rejected':rejected})
    assert not rejected,rejected
    timing=work/'report_timing'/(top+'.rtr')
    assert 'All Constraints Met' in timing.read_text(encoding='utf-8',errors='replace')
    bit=work/'generate_bitstream'/(top+'.sbit');mask=bit.with_suffix('.smsk')
    assert all(sha256(ROOT/p)==h for p,h in inputs.items())
    assert all(sha256(work/'src'/p)==h for p,h in inputs.items()),'Frozen snapshot changed during build'
    return {'status':'pass','target':'video_rx_image_probe','stage':'bitstream','directory':str(work.relative_to(ROOT)),
            'scope':manifest['scope'],'internal_timing_met':True,'physical_board':False,'external_io_timing_verified':False,
            'inputs':inputs,'vendor_inputs':{str(p.relative_to(work)):sha256(p) for p in vendor},'pds_version':version,
            'artifact':str(bit.relative_to(ROOT)),'artifact_sha256':sha256(bit),'verify_mask':str(mask.relative_to(ROOT)),
            'verify_mask_sha256':sha256(mask),'timing_report':str(timing.relative_to(ROOT))}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--test',action='store_true');args=parser.parse_args()
    work=fresh_run('rx_image_probe_test' if args.test else 'rx_image_probe_pds')
    result={'status':'running','directory':str(work.relative_to(ROOT))}
    pointer=BUILD/('latest_rx_image_probe_test.json' if args.test else 'latest_rx_image_probe_build.json')
    write_json(pointer,result)
    try:
        manifest=json.loads((ROOT/'fpga/pg2l100h/project/video_rx_image_probe.json').read_text(encoding='utf-8'))
        result=tests(work,manifest) if args.test else build(work,manifest)
    except Exception as e:result.update(status='fail',error=str(e));print(str(e),file=sys.stderr)
    result.setdefault('directory',str(work.relative_to(ROOT)))
    write_json(work/'result.json',result);write_json(pointer,result)
    print('RX_IMAGE_PROBE',result['status'],work)
    return 0 if result['status']=='pass' else 1


if __name__=='__main__':raise SystemExit(main())
