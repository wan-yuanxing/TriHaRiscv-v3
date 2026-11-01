"""Map an admitted RV32 ELF into the board's 8KiB ROM and 32KiB SRAM."""
import hashlib
from pathlib import Path
import struct


def memory_images(elf):
    if len(elf)<52 or elf[:7]!=b'\x7fELF\x01\x01\x01':
        raise ValueError('expected little-endian ELF32')
    if struct.unpack_from('<HHI',elf,16)!=(2,243,1) or struct.unpack_from('<I',elf,24)[0]!=0x10000:
        raise ValueError('expected executable RV32 firmware at 0x10000')
    ph=struct.unpack_from('<I',elf,28)[0]
    size,count=struct.unpack_from('<HH',elf,42)
    if size!=32 or not count or ph<52 or ph+size*count>len(elf):
        raise ValueError('invalid ELF program header table')
    sram=bytearray(32768);ranges=[];entry_loaded=False
    for i in range(count):
        kind,start,va,pa,filesz,memsz,flags,align=struct.unpack_from('<8I',elf,ph+i*size)
        if kind!=1:continue
        local=pa-0x10000
        if va!=pa or local<0 or filesz>memsz or local+memsz>len(sram) or start+filesz>len(elf):
            raise ValueError('ELF segment exceeds file or SRAM')
        if any(local<end and local+memsz>begin for begin,end in ranges):
            raise ValueError('overlapping ELF load segments')
        ranges.append((local,local+memsz));sram[local:local+filesz]=elf[start:start+filesz]
        entry_loaded|=local==0 and filesz>=4 and bool(flags&1)
    if not entry_loaded:raise ValueError('firmware entry is not executable file data')
    rom=bytearray(b'\x73\x00\x10\x00'*2048)
    rom[:8]=struct.pack('<II',0x000102b7,0x00028067)
    return {name:''.join(data[n:n+8][::-1].hex()+'\n' for n in range(0,len(data),8)).encode('ascii')
            for name,data in [('rom.hex',rom),('sram.hex',sram)]}


def install(work,source):
    source=Path(source).resolve();elf=source.read_bytes();images=memory_images(elf)
    (work/'firmware.elf').write_bytes(elf)
    for name,data in images.items():(work/name).write_bytes(data)
    return {'source':str(source),'sha256':hashlib.sha256(elf).hexdigest()}, {
        **{name:hashlib.sha256(data).hexdigest() for name,data in images.items()},'placeholder':False}
