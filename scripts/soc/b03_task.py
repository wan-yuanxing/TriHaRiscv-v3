"""Bind an immutable NPM3 program to the main SoC's Video frame slots."""
import struct
import zlib
from gen_config import need, uint, validate_memory


def build_task(memory, program, *, slot, cmd_id, frame_id, epoch, addr_version):
    validate_memory(memory)
    need(type(slot) is int and 0<=slot<3,'invalid frame slot')
    for name,v in [('cmd_id',cmd_id),('frame_id',frame_id),('epoch',epoch),('addr_version',addr_version)]:
        need(uint(v) and 0<v<0xffffffff,'invalid/exhausted '+name)
    need(len(program)>=128 and len(program)%128==0,'program alignment')
    h=struct.unpack('<32I',program[:128]); b=memory['b03']
    need(h[:6]==(0x334d504e,1,128,128,79,len(program)),'unsupported NPM3 header')
    need(zlib.crc32(program[:124])==h[31] and zlib.crc32(program[128:])==h[26],'program CRC')
    need(h[6:9]==(b['workspace_bytes'],b['parameter_origin'],b['parameter_bytes']), 'workspace package mismatch')
    need(h[9:13]==(3,320,320,b['input_bytes']) and h[22]==b['heads_bytes'] and h[23]==b['post_table_bytes'], 'model dimensions')
    need(len(program)==b['program_bytes'],'program size')
    shared_base=memory['ddr_base']+memory['window_base']
    def offset(addr):
        need(shared_base<=addr<shared_base+memory['window_bytes'],'task address outside shared window')
        return addr-shared_base
    out=b['output_bases'][slot]
    words=[0x33444d42,1,128,1,offset(b['program_base']),len(program),offset(b['workspace_base']),h[6],
           offset(b['input_bases'][slot]),b['input_bytes'],offset(out+b['result_offset']),b['result_bytes'],
           offset(b['post_table_base']),b['post_table_bytes'],cmd_id,frame_id,0,epoch,addr_version,
           b['source_width'],b['source_height'],b['resized_width'],b['resized_height'],b['pad_left'],b['pad_top'],
           b['capacity'],zlib.crc32(program),h[25],offset(out+b['heads_offset']),1,b['watchdog_cycles'],0]
    return struct.pack('<32I',*words)
