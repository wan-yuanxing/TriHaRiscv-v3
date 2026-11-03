"""Qualify a frozen BOX route and optionally generate its volatile JTAG image.

Keep unsuccessful builds intact. This creates a separate acceptance record
linking source synthesis, placement, route, full STA, Gray-clock audit and real
CPU/NPU simulations. A bitstream is generated only after every internal check.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
from common import ROOT, BUILD, sha256, write_json
from build_pds import verify_build_inputs, review_messages, verify_mode_key_reference
from face_timing import parse_tables, require_routed_report, audit_paths, gray_bounds
from face_route_evidence import route_record, placement_record
from face_gray_netlist import load_evidence


def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))


def hashes(items, relative=ROOT):
    for name,expected in items.items():
        if sha256(relative/Path(name))!=expected: raise ValueError('Changed evidence: '+name)


def check_simulation(directory, base, br, expected_faces):
    r=read(directory/'result.json')
    if r.get('clock_contract')!={'compute_hz':50_000_000,'video_hz':125_000_000,'pixel_hz':40_000_000}:
        raise ValueError('Simulation did not run the physical 50/125/40 MHz clock profile')
    if r['status']!='PASS' or r['expected_faces']!=expected_faces or r['avatar_boot'] or r['model_preloaded']:
        raise ValueError('Not a passing true BOX model-load simulation')
    for key in ('real_cpu','actual_capture','actual_npu','actual_display','model_loader_verified','board_profile','inputs_unchanged'):
        if r[key] is not True: raise ValueError('Incomplete functional evidence: '+key)
    for key in ('source_sha256','external_sha256','tracked_sha256'): hashes(r[key])
    hashes(r['output_sha256'],directory)
    shared=set(r['source_sha256']) & set(br['snapshot_inputs'])
    if len(shared)<130 or any(r['source_sha256'][n]!=br['snapshot_inputs'][n] for n in shared):
        raise ValueError('Simulated and synthesized source differ')
    for name in ('rom.hex','sram.hex'):
        words=lambda p:[int(x,16) for x in p.read_text(encoding='utf-8').split()]
        if words(directory/name)!=words(base/name): raise ValueError('Simulated firmware image differs')
    if expected_faces and sha256(directory/'firmware.elf')!=br['firmware']['sha256']:
        raise ValueError('Positive-scene ELF differs from built firmware')
    return dict(directory=str(directory),result_sha256=sha256(directory/'result.json'),shared_sources=len(shared),expected_faces=expected_faces)


def check_sites(source, actual):
    def ports(text):
        return {name:dict(item.split('=',1) for item in values.split() if '=' in item)
                for name,values in re.findall(r'^def_port \{([^}]+)\} ([^\n]+)',text,re.M)}
    requested,observed=ports(source),ports(actual)
    if set(requested)-set(observed)!={'mode_button_n'} or set(observed)-set(requested):
        raise ValueError('Unexpected physical port removal/addition')
    for name,attrs in observed.items():
        for key,value in requested[name].items():
            if attrs.get(key)!=value: raise ValueError('Physical pin/electrical mismatch: '+name+' '+key)
    gates={}
    for bit,site in [(0,'CLMA_357_354'),(1,'CLMA_357_660')]:
        cell='g_full.impl/I_ips_ddr_top/u_ddrphy_top/ddrphy_reset_ctrl/ddrphy_ioclk_gate['+str(bit)+']/opit_0_inv'
        matches=re.findall(r'^def_inst_site \{'+re.escape(cell)+r'\} (\S+) (\S+)(?: -no_check)?\s*$',actual,re.M)
        if matches!=[(site,'FF3')]: raise ValueError('DDR gate site changed: '+cell)
        gates[cell]=site+' FF3'
    return dict(physical_ports=len(observed),disabled_box_key='mode_button_n',ddr_gate_sites=gates)


def qualify(args):
    base=args.base.resolve();route=args.route.resolve();review=args.review.resolve();clocks=args.clock_review.resolve()
    br=read(base/'result.json');rr=route_record(route);tr=read(review/'result.json');cr=read(clocks/'result.json')
    placement=args.placement.resolve();pr=placement_record(placement)
    if br['face_profile']!='box' or br['top_parameters']!={'ENABLE_AVATAR':0,'ENABLE_MINIMAL_BOX':1,'DEMO_BOX_ONLY':0}:
        raise ValueError('Not the real detection BOX profile')
    if rr['status']!='ROUTE_REVIEW_READY' or tr['status']!='REPORTS_READY' or not tr['timing']['all_tables_met']:
        raise ValueError('Completed route has not passed full internal timing')
    if cr['status']!='PASS' or cr['analysis']['status']!='PASS_CONSERVATIVE_CLOCK_AND_DATA_BOUND':
        raise ValueError('Gray clock/data audit has not passed')
    if cr['analysis']['bits']!=116 or cr['analysis']['clock_observations']!=928 or len(cr['analysis']['groups'])!=23:
        raise ValueError('Gray audit coverage is incomplete')
    verify_build_inputs(base,br)
    for r in (pr,rr,tr,cr): hashes(r['inputs'])
    placed=placement/'place_route/triha_face_board_top_plc.adf'
    mapped=base/'device_map/triha_face_board_top_map.adf'
    if (rr['inputs'].get(str(placed))!=sha256(placed) or rr['inputs'].get(str(mapped))!=sha256(mapped)
            or pr['inputs'].get(str(mapped))!=sha256(mapped)):
        raise ValueError('Placement and route do not share the frozen mapped design')
    db=Path(rr['routed_db'])
    if sha256(db)!=rr['routed_db_sha256'] or tr['inputs'].get(str(db))!=rr['routed_db_sha256'] or cr['inputs'].get(str(db))!=rr['routed_db_sha256']:
        raise ValueError('Route/STA/clock audits refer to different databases')
    route_log=Path(rr['log_path']).read_text(encoding='utf-8',errors='replace')
    remaining=re.findall(r'Unrouted nets (\d+) at the end of iteration (\d+)\.',route_log)
    if not remaining or remaining[-1][0]!='0' or not re.search(
            r"Design 'triha_face_board_top' has been (?:placed and )?routed successfully\.",route_log):
        raise ValueError('Missing successful zero-unrouted route evidence')
    timing=Path(tr['report']['path']);sites=Path(tr['sites']['path']);clock_report=Path(cr['report']['path'])
    for p,record in [(timing,tr['report']),(sites,tr['sites']),(clock_report,cr['report'])]:
        if sha256(p)!=record['sha256']: raise ValueError('Review output changed: '+str(p))
    text=timing.read_text(encoding='utf-8');require_routed_report(text,db.as_posix())
    tables=parse_tables(text)
    if not tables['all_tables_met']: raise ValueError('Timing tables contain a violation')
    paths=audit_paths(text,tables)
    netlist=load_evidence(tr['gray_netlist'],rr['routed_db_sha256']) if 'gray_netlist' in tr else None
    cdc=gray_bounds(text,(base/'src/fpga/pg2l100h/constraints/triha_face_cdc.fdc').read_text(encoding='utf-8'),sites.read_text(encoding='utf-8'),netlist)
    if cdc!=tr['gray']: raise ValueError('Gray audit cannot be reproduced')
    physical=check_sites((base/'physical.pcf').read_text(encoding='utf-8'),sites.read_text(encoding='utf-8'))
    functional=[check_simulation(args.positive.resolve(),base,br,1),check_simulation(args.negative.resolve(),base,br,0)]
    reference=ROOT/'build/video/vendor/hdmi/HDMI_IN_DDR3_HDMI_OUT_top.fdc'
    manifest=read(base/'src/fpga/pg2l100h/ip/video_reference_manifest.json')
    expected={x['path']:x['sha256'] for x in manifest['references']['hdmi']['files']}
    if sha256(reference)!=expected[reference.name]: raise ValueError('Reference HDMI pin table changed')
    board_fdc=(base/'src/fpga/pg2l100h/constraints/triha_face_board.fdc').read_text(encoding='utf-8')
    key=read(base/'src/fpga/pg2l100h/ip/video_mode_key_manifest.json')
    for field in ('manual','vendor_example_fdc'):
        if sha256(ROOT/key[field]['path'])!=key[field]['sha256']: raise ValueError('Official KEY1 evidence changed')
    reference_fdc=reference.read_text(encoding='utf-8')+'\n'+board_fdc+'\n'+verify_mode_key_reference(key,board_fdc)
    log_paths=[base/'synth.log',Path(pr['log_path']),Path(rr['log_path']),
               review/'timing/console.log',review/'sites/console.log']
    log_paths=list(dict.fromkeys(log_paths))
    if (clocks/'console.log').exists():log_paths.append(clocks/'console.log')
    if 'gray_netlist' in tr:log_paths.append(review/'netlist/console.log')
    messages={'reviewed_reference_pin_notices':[],'reviewed_disabled_box_key':[],'rejected':[]}
    for p in log_paths:
        accepted,rejected=review_messages(p.read_text(encoding='utf-8',errors='replace'),reference_fdc)
        messages['reviewed_reference_pin_notices']+=accepted
        for line in rejected:
            if re.fullmatch(r"C: ConstraintEditor-2001: \[.*physical\.pcf\(line number: \d+\)\] Object 'mode_button_n' is dangling, which has no connection\. it will be ignored\.",line):
                messages['reviewed_disabled_box_key'].append(line)
            else:messages['rejected'].append(line)
    if messages['rejected']: raise ValueError('Unreviewed PDS error/critical warning: '+messages['rejected'][0])
    synthesis=base/'synthesize/triha_face_board_top.snr'
    resources={}
    for key,label in [('lut','Total LUTs'),('registers','Total Registers'),('drm','Total DRM'),('apm','Total APMs')]:
        values=re.findall(re.escape(label)+r'\s*[=:]\s*([\d.]+)',synthesis.read_text(encoding='utf-8'))
        if len(values)!=1: raise ValueError('Missing/duplicate synthesis resource: '+key)
        resources[key]=float(values[0])
    provenance=[base/'result.json',Path(pr['record_path']),Path(rr['record_path']),review/'result.json',clocks/'result.json',synthesis,timing,sites,clock_report,db]+log_paths
    if 'gray_netlist' in tr:
        provenance += [Path(tr['gray_netlist'][key]['path']) for key in ('netlist','model')]
    inputs={str(p):sha256(p) for p in provenance}
    return br,db,dict(timing=tables,paths=paths,physical=physical,functional=functional,resources=resources,
                     gray_clock_data=cr['analysis'],message_review=messages,evidence_inputs=inputs,
                     route_iterations=int(remaining[-1][1]))


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('base','placement','route','review','clock-review','positive','negative','output'):
        p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--generate',action='store_true')
    p.add_argument('--pds',type=Path,default=Path('D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe'))
    args=p.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    result={'status':'running','target':'triha_face_board','stage':'review','physical_board':False,
            'timing_closed':False,'internal_timing_met':False,'external_io_timing_verified':False,'started':time.time()}
    if args.generate:
        for name in ('latest_pds.json','latest_pds_triha_face_board.json'):write_json(BUILD/name,result)
    try:
        br,db,evidence=qualify(args)
        result.update(evidence)
        result.update(internal_timing_met=True,routed_internal_timing_closed=True,cdc_timing_met=True,status='review_pass',
            source_build_directory=str(args.base.resolve()),source_build_status=br['status'],
            source_snapshot_directory=str(args.base.resolve()/'src'),directory=str(out.relative_to(ROOT)),
            scope=br['scope'],face_profile='box',top_parameters=br['top_parameters'],firmware=br['firmware'],
            timing_report=str(Path(read(args.review/'result.json')['report']['path']).relative_to(ROOT)),
            inputs=dict(br['inputs']))
        for path in [Path(__file__),Path(__file__).with_name('face_timing.py'),Path(__file__).with_name('check_face_gray_clocks.py'),Path(__file__).with_name('face_route_evidence.py'),Path(__file__).with_name('face_gray_netlist.py')]:
            result['inputs'][path.relative_to(ROOT).as_posix()]=sha256(path)
        write_json(out/'message_review.json',evidence['message_review'])
        write_json(out/'result.json',result)
        if args.generate:
            for name in ('rom.hex','sram.hex','firmware.elf'):shutil.copyfile(args.base/name,out/name)
            script=out/'bitstream.tcl'
            script.write_text('set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676\n'
                +'gen_bit_stream -force_to_run -input_db_file {'+db.as_posix()+'} -scbv {High Voltage} -create_mask_file TRUE\n',encoding='utf-8')
            with (out/'bitstream.log').open('wb') as log:
                proc=subprocess.Popen([str(args.pds),'-file',str(script),'-work_dir',str(out),'-project_name','triha_face_box'],cwd=out,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
                try: code=proc.wait(timeout=600)
                except subprocess.TimeoutExpired:
                    subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True,timeout=30);proc.wait(timeout=30);raise
            _,rejected=review_messages((out/'bitstream.log').read_text(encoding='utf-8',errors='replace'))
            if code or rejected: raise ValueError('Bitstream generation failed or has an unreviewed message')
            bit=out/'generate_bitstream/triha_face_board_top.sbit';mask=bit.with_suffix('.smsk')
            if bit.stat().st_size<1024 or mask.stat().st_size<1024: raise ValueError('Incomplete bitstream/mask')
            hashes(result['inputs']);hashes(result['evidence_inputs']);verify_build_inputs(args.base.resolve(),br)
            result.update(status='pass',stage='bitstream',artifact=str(bit.relative_to(ROOT)),artifact_sha256=sha256(bit),
                verify_mask=str(mask.relative_to(ROOT)),verify_mask_sha256=sha256(mask),input_snapshot_verified_before_and_after_build=True)
            result['bitstream_generation_inputs']={str(x.resolve()):sha256(x) for x in [script,args.pds]}
    except Exception as error:result.update(status='fail',error=str(error))
    finally:result['elapsed']=time.time()-result['started'];write_json(out/'result.json',result)
    if args.generate:
        for name in ('latest_pds.json','latest_pds_triha_face_board.json'):write_json(BUILD/name,result)
    print('FACE_QUALIFY_'+result['status'].upper(),result.get('error',''),out,flush=True)
    return 0 if result['status'] in ('pass','review_pass') else 1


if __name__=='__main__':raise SystemExit(main())
