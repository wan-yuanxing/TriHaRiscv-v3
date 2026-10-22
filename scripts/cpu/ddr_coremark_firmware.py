"""Build an O2 CoreMark payload and an SRAM loader for private DDR execution."""
from pathlib import Path
import json
import struct

from cache_firmware import prepare


def payload_image(data, base=0x80000000):
    if base not in (0x80000000, 0x82000000):
        raise ValueError('unsupported private/shared DDR comparison base')
    if data[:7] != b'\x7fELF\x01\x01\x01' or struct.unpack_from('<H', data, 18)[0] != 243:
        raise ValueError('need little-endian RV32 ELF')
    if struct.unpack_from('<I', data, 24)[0] != base:
        raise ValueError('payload entry must match the selected DDR base')
    offset = struct.unpack_from('<I', data, 28)[0]
    size, count = struct.unpack_from('<HH', data, 42)
    if size != 32 or count == 0 or offset + count * size > len(data):
        raise ValueError('invalid payload program headers')
    image = bytearray()
    ranges = []
    for index in range(count):
        kind, start, virtual, physical, filesz, memsz, _, _ = struct.unpack_from('<8I', data, offset + index * size)
        if kind != 1:
            continue
        relative = physical - base
        if (virtual != physical or relative < 0 or filesz > memsz or relative + memsz > 131072 or
                start + filesz > len(data)):
            raise ValueError('payload is outside the private DDR execution window')
        if filesz:
            if any(relative < end and relative + filesz > begin for begin, end in ranges):
                raise ValueError('overlapping payload segments')
            ranges.append((relative, relative + filesz))
            if len(image) < relative + filesz:
                image.extend(b'\0' * (relative + filesz - len(image)))
            image[relative:relative + filesz] = data[start:start + filesz]
    if not ranges or min(begin for begin, _ in ranges) != 0:
        raise ValueError('payload entry bytes are missing')
    image.extend(b'\0' * (-len(image) % 4))
    return bytes(image)


def build(work, native, iterations=1, preflight=True, fault='none', cpu_luts=0, base=0x80000000):
    work = Path(work)
    src = work / 'src'
    flags, sources = prepare(work, iterations, fault)
    flags += ['-DTRIHA_SOC_MMIO=1', '-DTRIHA_COREMARK_BOARD=1',
        '-DTRIHA_COREMARK_PREFLIGHT=' + str(int(preflight)), '-DTRIHA_COREMARK_DDR_BOARD=1', '-DTRIHA_CPU_CORE_LUTS=0']
    port = work / 'generated-port/core_portme.h'
    location = 'private DDR stack' if base == 0x80000000 else 'shared DDR stack (uncached)'
    text = port.read_text(encoding='utf-8').replace('SRAM stack', location).replace('modeled DDR stack', location)
    port.write_text(text, encoding='utf-8', newline='\n')
    gcc = Path(json.loads((src / 'config/cpu_toolchain.json').read_text(encoding='utf-8'))['compiler'])
    payload = work / 'payload'
    payload.mkdir()
    linker = (src / 'sw/runtime/triha_tcm.ld').read_text(encoding='utf-8')
    if linker.count('ORIGIN = 0x80000000') != 1:
        raise ValueError('DDR linker anchor changed')
    (work / 'payload.ld').write_text(linker.replace('ORIGIN = 0x80000000', f'ORIGIN = 0x{base:08x}'), encoding='utf-8', newline='\n')
    native(gcc, flags + ['-nostdlib', '-T', work / 'payload.ld',
        '-Wl,--gc-sections,--build-id=none', '-Wl,-Map=' + str(payload / 'firmware.map'),
        '-o', payload / 'firmware.elf', *sources, '-lgcc'], 'payload-build')
    image = payload_image((payload / 'firmware.elf').read_bytes(), base)
    (payload / 'firmware.bin').write_bytes(image)
    header = '#include <stdint.h>\n#define TRIHA_PAYLOAD_WORDS ' + str(len(image)//4) + 'u\n'
    header += '#define TRIHA_PAYLOAD_CPU_LUTS ' + str(cpu_luts) + 'u\n'
    header += f'#define TRIHA_PAYLOAD_ENTRY 0x{base:08x}u\n'
    header += 'static const uint32_t triha_payload[] = {\n'
    header += ''.join(f'0x{int.from_bytes(image[n:n+4], "little"):08x}u,\n' for n in range(0, len(image), 4))
    header += '};\n'
    (work / 'cpu_ddr_payload.h').write_text(header, encoding='utf-8', newline='\n')
    boot_flags = ['-march=rv32im_zicsr', '-mabi=ilp32', '-O2', '-mcmodel=medany', '-mno-relax',
        '-msmall-data-limit=0', '-ffreestanding', '-fno-builtin', '-ffunction-sections', '-fdata-sections',
        '-Wall', '-Wextra', '-DTRIHA_SOC_MMIO=1']
    native(gcc, boot_flags + ['-I', work, '-I', src / 'sw/runtime', '-nostdlib',
        '-T', src / 'sw/runtime/triha_coremark_loader.ld', '-Wl,--gc-sections,--build-id=none',
        '-Wl,-Map=' + str(work / 'firmware.map'), '-o', work / 'firmware.elf',
        src / 'sw/runtime/crt0.S', src / 'sw/runtime/triha_runtime.c',
        src / 'sw/tests/cpu_ddr_coremark_boot.c', '-lgcc'], 'loader-build')
    # Reuse the established SRAM ELF loader and 64-bit initialization format.
    import sys
    from run_cache import ROOT
    sys.path.insert(0, str(ROOT / 'scripts/soc'))
    from run import elf_sram, hex_image
    memory = json.loads((src / 'config/soc_map.json').read_text(encoding='utf-8'))
    hex_image(work / 'sram.hex', elf_sram((work / 'firmware.elf').read_bytes(), memory))
    rom = bytearray(b'\x73\x00\x10\x00' * 2048)
    rom[:8] = struct.pack('<II', 0x000102b7, 0x00028067)
    hex_image(work / 'rom.hex', rom)
    return dict(compiler_flags=[str(flag) for flag in flags], payload_bytes=len(image),
        payload_entry=base, placement_base=base, iterations=iterations, preflight=preflight,
        cpu_core_luts=cpu_luts, lto=False)
