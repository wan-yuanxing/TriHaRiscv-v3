"""Compare extracted real B forwarding/E2 expressions with the frozen parent."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]
SIM=Path('D:/modeltech64_2020.4/win64')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()


def extract(cpu,prefix):
    issue=(cpu/'triha_issue.v').read_text(encoding='utf-8')
    pipe=(cpu/'triha_pipe_ctrl.v').read_text(encoding='utf-8')
    start=issue.index('always @ *',issue.index('reg [31:0] issue_b_rb_value_r;'))
    end=issue.index('assign opcode1_ra_operand_o',start)
    body=issue[start:end]
    helper=''
    if 'function [31:0] forward_b_operand;' in issue:
        a=issue.index('function [31:0] forward_b_operand;')
        helper=issue[a:issue.index('endfunction',a)+len('endfunction')]
    aliases='''wire [4:0] issue_b_ra_idx_w=index_i,issue_b_rb_idx_w=index_i;
wire [31:0] issue_b_ra_value_w=rf_i,issue_b_rb_value_w=rf_i;
wire [29:0] raw_bypass_tags_w=tags_i;
wire [191:0] raw_bypass_values_w=values_i;
wire [31:0] writeback_mem_bypass_i=memory_i;
wire pipe0_mem_bypass_e2_w=mem_select_i[0],pipe1_mem_bypass_e2_w=mem_select_i[1];
wire [31:0] pipe0_nonmem_e2_w=nonmem_i[31:0],pipe1_nonmem_e2_w=nonmem_i[63:32];
wire [4:0] pipe0_rd_bypass_wb_w=tags_i[4:0],pipe1_rd_bypass_wb_w=tags_i[9:5],
pipe0_rd_bypass_e2_w=tags_i[14:10],pipe1_rd_bypass_e2_w=tags_i[19:15],
pipe0_rd_e1_w=tags_i[24:20],pipe1_rd_e1_w=tags_i[29:25];
wire [31:0] pipe0_result_wb_w=values_i[31:0],pipe1_result_wb_w=values_i[63:32],
pipe0_result_e2_w=values_i[95:64],pipe1_result_e2_w=values_i[127:96],
pipe0_forward_e1_w=values_i[159:128],pipe1_forward_e1_w=values_i[191:160];
reg [31:0] issue_b_ra_value_r,issue_b_rb_value_r;
'''
    wrapper=f'''module {prefix}_operand(input [4:0] index_i,input [31:0] rf_i,
input [29:0] tags_i,input [191:0] values_i,input [31:0] memory_i,
input [1:0] mem_select_i,input [63:0] nonmem_i,output [31:0] value0_o,value1_o);
'''+aliases+helper+'\n'+body+'\nassign value0_o=issue_b_ra_value_r;assign value1_o=issue_b_rb_value_r;\nendmodule\n'
    marker='// Direct B forwarding sources'
    start=pipe.index(marker) if marker in pipe else pipe.index('reg [31:0] result_e2_r;')
    end=pipe.index('wire   load_store_e2_w',start)
    block=pipe[start:end]
    ports=f'''module {prefix}_e2 #(parameter SUPPORT_LOAD_BYPASS=1,SUPPORT_MUL_BYPASS=1)(
input valid_e2_q,input [9:0] ctrl_e2_q,input [31:0] result_e2_q,mem_bypass_e2_i,mul_result_e2_i,
output [31:0] value_o,result_nonmem_e2_o,output bypass_mem_e2_o);
wire issue_stall_i=1'b0;
'''
    if marker not in pipe:block+='\nassign result_nonmem_e2_o=result_e2_r;assign bypass_mem_e2_o=1\'b0;\n'
    return ('`define PCINFO_LOAD 1\n`define PCINFO_STORE 2\n`define PCINFO_MUL 5\n'+wrapper+
            ports+block+'\nassign value_o=result_e2_r;\nendmodule\n')


def main():
    p=argparse.ArgumentParser();p.add_argument('parent',type=Path);p.add_argument('candidate',type=Path);p.add_argument('output',type=Path);p.add_argument('--old',action='store_true');a=p.parse_args()
    out=a.output.resolve()
    if not out.is_relative_to(ROOT/'build/cpu'):raise ValueError('Use a fresh build/cpu directory')
    out.mkdir(parents=True,exist_ok=False)
    tb=ROOT/'tb/cpu/tb_direct_load_forward.v'
    inputs=[tb,Path(__file__).resolve()]+[d/n for d in [a.parent,a.candidate] for n in ['triha_issue.v','triha_pipe_ctrl.v']]
    row={'status':'RUNNING','input_hashes':{str(p.resolve()):sha(p) for p in inputs},'commands':[]}
    try:
        for name,d in [('parent',a.parent),('candidate',a.candidate)]:
            (out/(name+'.v')).write_text(extract(d,name),encoding='utf-8',newline='\n')
        calls=[('vlib','vlib.exe',['work'],None),('compile','vlog.exe',['parent.v','candidate.v',str(tb)],None),
               ('semantic','vsim.exe',['-c','-voptargs=+acc','tb_direct_load_forward','-do','run -all; quit -f'],'DIRECT_FORWARD_PASS'),
               ('poison','vsim.exe',['-c','-voptargs=+acc','tb_direct_load_forward','+POISON_E2','-do','run -all; quit -f'],'DIRECT_FORWARD_FAIL' if a.old else 'DIRECT_FORWARD_PASS'),
               ('negative','vsim.exe',['-c','-voptargs=+acc','tb_direct_load_forward','+FAULT_OUTPUT','-do','run -all; quit -f'],'DIRECT_FORWARD_FAIL')]
        for load,mul in [(0,0),(0,1),(1,0)]:
            calls.append((f'semantic-{load}-{mul}','vsim.exe',['-c','-voptargs=+acc',f'-gLOAD_BYPASS={load}',f'-gMUL_BYPASS={mul}','tb_direct_load_forward','-do','run -all; quit -f'],'DIRECT_FORWARD_PASS'))
        for label,tool,args,expected in calls:
            command=[str(SIM/tool)]+args;r=subprocess.run(command,cwd=out,capture_output=True,timeout=120)
            log=r.stdout+r.stderr;(out/(label+'.log')).write_bytes(log);row['commands'].append(dict(command=command,return_code=r.returncode))
            if expected and (expected.encode() not in log or (b'DIRECT_FORWARD_FAIL' in log)!=(expected=='DIRECT_FORWARD_FAIL')):raise ValueError(label+' marker mismatch')
            if r.returncode and expected!='DIRECT_FORWARD_FAIL':raise ValueError(label+' tool failed')
        assert all(sha(Path(n))==h for n,h in row['input_hashes'].items())
        row['status']='PASS'
    except Exception as e:
        row.update(status='FAIL',error=str(e));raise
    finally:
        row['output_hashes']={p.name:sha(p) for p in out.iterdir() if p.is_file()}
        (out/'result.json').write_text(json.dumps(row,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('DIRECT_FORWARD_CHECK_PASS',out)


if __name__=='__main__':main()
