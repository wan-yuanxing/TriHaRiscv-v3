"""Exercise stale upstream/owned packets at the real application capture boundary."""
import json,re
from common import ROOT,fresh_run,input_hashes,run_logged,tool,sha256,write_json

def main():
    work=fresh_run('capture_stream_admission')
    result=dict(status='running',scope='Production application capture admission with controlled MMIO request outputs; no physical timing proof.')
    try:
        manifest=ROOT/'fpga/pg2l100h/project/video_record_pipeline.json'
        sources=json.loads(manifest.read_text(encoding='utf-8'))['sources']+[
            'rtl/video/video_application_engine.sv','rtl/video/video_display_mmio_compact.sv',
            'rtl/video/video_display_record_compact.sv','rtl/video/video_record_renderer_compact.sv',
            'rtl/video/display_record_pixels_compact.sv','rtl/video/display_mode_cdc_held.sv','rtl/video/avatar_row_cache.sv']
        names=sources+['scripts/video/test_capture_stream_admission.py','scripts/video/common.py',
            'fpga/pg2l100h/project/video_record_pipeline.json']
        names+=['rtl/video/include/'+n for n in ['video_cfg.vh','video_capture_v2.vh','video_display.vh','avatar_span_table.vh','avatar_span_identity.vh']]
        result['inputs']=input_hashes(ROOT/n for n in names)
        iv,vvp=tool('iverilog'),tool('vvp');result['tools']={str(p):sha256(p) for p in [iv,vvp]}
        source=(ROOT/'rtl/video/video_application_engine.sv').read_text(encoding='utf-8')
        header=source[source.index('module video_application_engine #'):].split(');',1)[0]
        ports=re.findall(r'^\s*(input|output) wire\s*(?:\[(\d+):0\])?\s*(\w+)\s*[,\n]',header,re.M)
        assert len(ports)>100
        connections=[]
        named=dict(clk_i='clk',pixel_clk='clk',rst_ni='rst',pixel_reset_n='rst',online="1'b1",
                   src_valid='src_valid',src_data='src_data',src_ready='src_ready',arm_toggle='arm',
                   c_awready="1'b1",c_wready="1'b1")
        for direction,high,name in ports:
            value=named.get(name,('' if direction=='output' else str(int(high)+1 if high else 1)+"'d0"))
            connections.append('.'+name+'('+value+')')
        tb=work/'tb.sv'
        body='''
`timescale 1ns/1ps
`include "video_cfg.vh"
module tb_capture_stream_admission;
reg clk=0,rst=0,src_valid=0;reg [47:0] src_data=48'h0000aabbccdd;
wire src_ready,arm;always #4 clk=~clk;
video_application_engine #(.FRAME_HEIGHT(10),.ENABLE_COMPACT(1),.ENABLE_CAPTURE_PREVIEW(0)) dut(CONNECTIONS);
initial begin
  repeat(4)@(negedge clk);rst=1;repeat(6)@(negedge clk);
  force dut.capture_req_slot_o=2'd0;
  force dut.capture_req_frame_id_o=32'd1;
  force dut.capture_req_version_o=`VIDEO_INPUT_PREPROCESS_VERSION;
  force dut.capture_req_valid_o=1'b1;
  src_valid=1;#1;
  if(dut.capture_req_ready_i!==0)$fatal(1,"STALE_UPSTREAM_ADMITTED");
  repeat(3)@(negedge clk);
  if(arm!==0||dut.capture_req_ready_i!==0)$fatal(1,"STALE_PACKET_STARTED_CAPTURE");
  src_valid=0;repeat(3)@(negedge clk);
  if(dut.capture_req_ready_i!==0||dut.u_capture.m_valid!==1||dut.u_capture.m_data!==src_data)
    $fatal(1,"OWNED_STALE_PACKET_NOT_RETAINED");
  rst=0;repeat(3)@(negedge clk);rst=1;repeat(12)@(negedge clk);
  // No DDR B responder is attached: admission must occur, while top padding
  // correctly prevents arming the camera until those writes have retired.
  if(dut.u_capture.frame_id!==32'd1||dut.u_capture.m_valid!==0)
    $fatal(1,"CLEAN_RESET_DID_NOT_RESTORE_ADMISSION");
  $display("CAPTURE_STREAM_ADMISSION_PASS scenarios=3");$finish;
end
initial begin #100000;$fatal(1,"ADMISSION_WATCHDOG");end
endmodule
'''.replace('CONNECTIONS',','.join(connections))
        tb.write_text(body,encoding='utf-8');binary=work/'simulation.vvp'
        run_logged([iv,'-g2012','-s','tb_capture_stream_admission','-I',ROOT/'rtl/video/include',
                    '-o',binary,*[ROOT/n for n in sources],tb],work/'compile.log')
        output=run_logged([vvp,binary],work/'simulation.log',timeout=30)
        if output.count('CAPTURE_STREAM_ADMISSION_PASS scenarios=3')!=1:raise ValueError('Missing admission pass')
        if result['inputs']!=input_hashes(ROOT/n for n in names):raise ValueError('Inputs changed')
        result.update(status='pass',scenarios=3,artifacts=input_hashes(p for p in work.iterdir() if p.is_file()))
    except Exception as e:result.update(status='fail',error=str(e))
    write_json(work/'result.json',result)
    print(result['status'],result.get('error',''),work,flush=True)
    return 0 if result['status']=='pass' else 1

if __name__=='__main__':raise SystemExit(main())
