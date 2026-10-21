"""Prepare the existing CoreMark port for modeled-DDR CPU Cache comparisons."""
from pathlib import Path
import re


def prepare(work, iterations, fault):
    work = Path(work)
    src = work/'src'
    bench = src/'sw/benchmarks/coremark/src'
    port = src/'sw/benchmarks/coremark/port'
    generated = work/'generated-port'
    generated.mkdir()
    base = ['-march=rv32im_zicsr','-mabi=ilp32','-std=gnu99','-O2','-mcmodel=medany',
            '-mno-relax','-msmall-data-limit=0','-ffreestanding','-fno-builtin',
            '-ffunction-sections','-fdata-sections','-Wall','-Wextra','-Werror=implicit-function-declaration']
    report = ' '.join(f for f in base if not f.startswith('-W')) + ' -nostdlib -Wl,--gc-sections'
    if len('Compiler flags   : '+report+'\n') + 1 >= 256:
        raise ValueError('CoreMark compiler description exceeds fixed formatter buffer')
    (work/'core_build_config.h').write_text('#define TRIHA_COMPILER_FLAGS "'+report+'"\n',encoding='utf-8',newline='\n')
    header = (port/'core_portme.h').read_text(encoding='utf-8')
    assert header.count('#define MEM_LOCATION "TCM stack"') == 1
    header = header.replace('#define MEM_LOCATION "TCM stack"', '#define MEM_LOCATION "modeled DDR stack"')
    (generated/'core_portme.h').write_text(header,encoding='utf-8',newline='\n')
    (generated/'core_portme.c').write_bytes((port/'core_portme.c').read_bytes())
    formatter = (bench/'barebones/ee_printf.c').read_text(encoding='utf-8')
    pattern = r'(?s)void uart_send_char\(char c\) \{.*?\n\}\s*(?=int ee_printf)'
    if len(re.findall(pattern,formatter)) != 1 or formatter.count('#ifdef HAS_FLOAT') != 2 or formatter.count('va_start(args, fmt);') != 1:
        raise ValueError('Fixed CoreMark formatter adapter anchors changed')
    formatter = re.sub(pattern,'void uart_send_char(char c);\n\n',formatter)
    formatter = formatter.replace('#ifdef HAS_FLOAT','#if HAS_FLOAT')
    formatter = formatter.replace('va_start(args, fmt);','triha_coremark_note(fmt);\n  va_start(args, fmt);')
    (generated/'ee_printf.c').write_text(formatter,encoding='utf-8',newline='\n')
    main = (bench/'core_main.c').read_text(encoding='utf-8')
    if fault == 'crc':
        if main.count('(ee_u16)0xe714') != 1:
            raise ValueError('Fixed CoreMark CRC negative anchor changed')
        main = main.replace('(ee_u16)0xe714','(ee_u16)0xe715')
    (generated/'core_main.c').write_text(main,encoding='utf-8',newline='\n')
    flags = base + [f'-DITERATIONS={iterations}','-DTOTAL_DATA_SIZE=2000','-DCORE_DEBUG=0',
                    '-DPERFORMANCE_RUN=1','-DVALIDATION_RUN=0',
                    '-I',generated,'-I',bench,'-I',work,'-I',src/'sw/runtime']
    sources = [src/'sw/runtime/crt0.S',src/'sw/runtime/triha_runtime.c',generated/'core_main.c',
               generated/'ee_printf.c',generated/'core_portme.c']
    sources += [bench/n for n in ['core_list_join.c','core_matrix.c','core_state.c','core_util.c']]
    return flags, sources
