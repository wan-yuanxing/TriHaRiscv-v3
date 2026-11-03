"""Frozen real debounce + mode observation MMIO, with negative controls."""
import argparse,hashlib,json,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/video'))
from common import tool

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--baseline',action='store_true');a=p.parse_args()
 out=ROOT/'build/soc'/('face_mode_key-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'));out.mkdir(parents=True)
 names=['rtl/video/video_display_mmio_compact.sv','rtl/video/display_slot_owner.sv','rtl/video/display_record_guard.sv',
        'rtl/video/include/video_display.vh','rtl/video/include/video_cfg.vh','tb/soc/tb_face_mode_key.sv','scripts/soc/run_face_mode_key.py']
 if not a.baseline:names+=['rtl/soc/triha_face_mode_key.v','rtl/video/video_button_debounce.sv']
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 inputs={n:sha(ROOT/n) for n in names};row={'status':'RUNNING','inputs':inputs,'cases':{}}
 for n in names:
  dst=out/'inputs'/n;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes((ROOT/n).read_bytes())
 try:
  cases=['baseline'] if a.baseline else ['green','no_debounce','wrong_cycle','zero_observation']
  for case in cases:
   sources=[out/'inputs'/n for n in names if n.endswith(('.v','.sv'))]
   if case not in ('green','baseline'):
    name='rtl/video/video_display_mmio_compact.sv' if case=='zero_observation' else 'rtl/soc/triha_face_mode_key.v'
    old,new={'no_debounce':('if(press_pulse)','if(!button_ni)'),
             'wrong_cycle':("mode_o==2?2'd0:mode_o+2'd1","mode_o==1?2'd0:mode_o+2'd1"),
             'zero_observation':("{30'd0,mode_request_i}","32'd0")}[case]
    src=(out/'inputs'/name).read_text(encoding='utf-8');assert src.count(old)==1
    dst=out/(case+'.sv');dst.write_text(src.replace(old,new),encoding='utf-8');sources=[dst if x==out/'inputs'/name else x for x in sources]
   binary=out/(case+'.vvp')
   cmd=[str(tool('iverilog')),'-g2012','-I',str(out/'inputs/rtl/video/include'),'-s','tb_face_mode_key','-o',str(binary)]+(['-DLEGACY'] if a.baseline else [])+list(map(str,sources))
   cp=subprocess.run(cmd,capture_output=True,text=True,timeout=60);(out/(case+'.compile.log')).write_text(cp.stdout+cp.stderr,encoding='utf-8');assert cp.returncode==0,cp.stderr
   cp=subprocess.run([str(tool('vvp')),str(binary)],capture_output=True,text=True,timeout=60);log=cp.stdout+cp.stderr;(out/(case+'.log')).write_text(log,encoding='utf-8')
   expected=case!='green';assert (cp.returncode!=0 and 'FACE_MODE_KEY_FAIL' in log) if expected else (cp.returncode==0 and 'FACE_MODE_KEY_PASS' in log),log
   row['cases'][case]={'expected_rejection':expected,'returncode':cp.returncode,'log':log.strip()}
  assert all(sha(ROOT/n)==v and sha(out/'inputs'/n)==v for n,v in inputs.items())
  row['status']='NEGATIVE_CONFIRMED' if a.baseline else 'PASS'
 except Exception as e:row.update(status='FAIL',error=str(e))
 (out/'result.json').write_text(json.dumps(row,indent=2)+'\n',encoding='utf-8');print(row['status'],out,row.get('error',''));return int(row['status']=='FAIL')
if __name__=='__main__':sys.exit(main())
