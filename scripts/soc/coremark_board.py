"""Build and verify CoreMark board firmware without replacing upstream algorithms."""
import argparse
from decimal import Decimal
from pathlib import Path
import re

from run import elf_sram, hex_image


def compiler_description(flags):
    # ee_printf's upstream buffer is 256 bytes. Full commands, defines and warning
    # options remain in result.json; UART reports the actual code-generation flags.
    report = ' '.join(flag for flag in flags if not flag.startswith(('-D', '-W')))
    report += ' -nostdlib -Wl,--gc-sections'
    if len('Compiler flags   : ' + report + '\n') + 1 >= 256:
        raise ValueError('compiler description exceeds upstream formatter buffer')
    return report


def review_output(text, allow_short=False, expected_luts=None):
    def match(pattern):
        rows = re.findall(pattern, text)
        if len(rows) != 1:
            raise ValueError('missing or duplicate CoreMark UART field: ' + pattern)
        return rows[0]

    if re.search(r'CPU_TRAP|CPU_COREMARK_BOARD_FAIL', text):
        raise ValueError('board reported a failure or trap')
    crcs = [match(p).lower().zfill(4) for p in (
        r'seedcrc\s*:\s*0x([0-9a-fA-F]+)', r'\[0\]crclist\s*:\s*0x([0-9a-fA-F]+)',
        r'\[0\]crcmatrix\s*:\s*0x([0-9a-fA-F]+)', r'\[0\]crcstate\s*:\s*0x([0-9a-fA-F]+)')]
    if crcs != ['e9f5', 'e714', '1fd7', '8e3a']:
        raise ValueError('CoreMark CRC mismatch')
    errors, short = map(int, match(r'CPU_COREMARK_STATUS errors=(\d+) short=(\d+)'))
    iterations, hz = map(int, match(r'CPU_COREMARK_START iterations=(\d+) clock_hz=(\d+)'))
    seconds, high, low, clock = match(r'CPU_COREMARK_TIME seconds=([0-9]+\.[0-9]{6}) cycles_hi=(\d+) cycles_lo=(\d+) clock_hz=(\d+)')
    if errors or short not in (0, 1) or hz != 100000000 or int(clock) != hz or not 0 < iterations <= 100000:
        raise ValueError('invalid status, iterations or clock')
    if not 0 <= int(low) < 2**32 or not 0 <= int(high) < 2**32:
        raise ValueError('invalid counter halves')
    ticks = (int(high) << 32) | int(low)
    if ticks <= 0:
        raise ValueError('zero elapsed ticks')
    seconds_exact = Decimal(ticks) / hz
    score = Decimal(iterations) * hz / ticks
    per_mhz = Decimal(iterations) * 1000000 / ticks
    for reported, exact in ((Decimal(seconds), seconds_exact),
                            (Decimal(match(r'CoreMark       : ([0-9]+\.[0-9]{6})')), score),
                            (Decimal(match(r'CoreMark/MHz   : ([0-9]+\.[0-9]{6})')), per_mhz)):
        if not Decimal(0) <= exact - reported < Decimal('0.000001'):
            raise ValueError('precise score/time disagrees with measured cycles')
    duration_valid = ticks >= 10 * hz and short == 0
    if not duration_valid and not allow_short:
        raise ValueError('run is shorter than ten seconds')
    marker = 'BOARD' if duration_valid else 'PREFLIGHT'
    if int(match(r'CPU_COREMARK_' + marker + r'_PASS iterations=(\d+)')) != iterations:
        raise ValueError('result iterations differ')
    if duration_valid and 'Correct operation validated.' not in text:
        raise ValueError('missing upstream correctness validation')
    result = dict(iterations=iterations, cycles=ticks, clock_hz=hz, seconds=float(seconds_exact),
                coremark=float(score), coremark_per_mhz=float(per_mhz), crc=crcs,
                duration_valid=duration_valid, official_submission=False)
    if 'CPU core LUTs' in text or 'CoreMark/LUTs' in text or expected_luts is not None:
        count = int(match(r'CPU core LUTs  : (\d+)'))
        if count <= 0 or expected_luts is not None and count != expected_luts:
            raise ValueError('invalid or mismatched CPU-only LUT denominator')
        value = Decimal(match(r'CoreMark/LUTs  : ([0-9]+\.[0-9]{6})'))
        exact = score / count
        if not Decimal(0) <= exact - value < Decimal('0.000001'):
            raise ValueError('CoreMark/LUTs disagrees with measured score and CPU LUTs')
        result.update(cpu_core_luts=count, coremark_per_lut=float(exact))
    return result


def build(work, destination, native, iterations, preflight=False, fault='none', cpu_luts=0):
    """Same frozen source and flags; only iteration count/preflight policy differ."""
    import json
    destination.mkdir(parents=True, exist_ok=True)
    src = work / 'src'
    port = src / 'sw/benchmarks/coremark/port'
    bench = src / 'sw/benchmarks/coremark/src'
    gcc = Path(json.loads((src / 'config/cpu_toolchain.json').read_text(encoding='utf-8'))['compiler'])
    flags = ['-march=rv32im_zicsr', '-mabi=ilp32', '-std=gnu99', '-O2', '-mcmodel=medany', '-mno-relax',
             '-msmall-data-limit=0', '-ffreestanding', '-fno-builtin', '-ffunction-sections', '-fdata-sections',
             '-Wall', '-Wextra', '-Werror=implicit-function-declaration', '-DTRIHA_SOC_MMIO=1',
             '-DTRIHA_COREMARK_BOARD=1', '-DTRIHA_COREMARK_PREFLIGHT=' + str(int(preflight)),
             '-DTRIHA_CPU_CORE_LUTS=' + str(cpu_luts),
             '-DITERATIONS=' + str(iterations), '-DTOTAL_DATA_SIZE=2000', '-DCORE_DEBUG=0',
             '-DPERFORMANCE_RUN=1', '-DVALIDATION_RUN=0']
    (destination / 'core_build_config.h').write_text(
        '#define TRIHA_COMPILER_FLAGS "' + compiler_description(flags) + '"\n', encoding='utf-8')
    formatter = (bench / 'barebones/ee_printf.c').read_text(encoding='utf-8')
    pattern = r'(?s)void uart_send_char\(char c\) \{.*?\n\}\s*(?=int ee_printf)'
    if len(re.findall(pattern, formatter)) != 1:
        raise ValueError('unexpected formatter source')
    formatter = re.sub(pattern, 'void uart_send_char(char c);\n\n', formatter)
    formatter = formatter.replace('#ifdef HAS_FLOAT', '#if HAS_FLOAT').replace(
        'va_start(args, fmt);', 'triha_coremark_note(fmt);\n  va_start(args, fmt);')
    (destination / 'ee_printf.c').write_text(formatter, encoding='utf-8', newline='\n')
    main = (bench / 'core_main.c').read_text(encoding='utf-8')
    # Original no-float report divides by whole seconds; label it honestly.
    main = main.replace('Iterations/Sec   : %d', 'Iterations/Sec (whole seconds): %d')
    if fault == 'crc':
        main = main.replace('(ee_u16)0xe714', '(ee_u16)0xe715')
    (destination / 'core_main.c').write_text(main, encoding='utf-8', newline='\n')
    sources = [src / 'sw/runtime/crt0.S', src / 'sw/runtime/triha_runtime.c', destination / 'core_main.c',
               destination / 'ee_printf.c', port / 'core_portme.c']
    sources += [bench / name for name in ('core_list_join.c', 'core_matrix.c', 'core_state.c', 'core_util.c')]
    native(gcc, flags + ['-I', port, '-I', bench, '-I', destination, '-I', src / 'sw/runtime',
           '-nostdlib', '-T', src / 'sw/runtime/triha_sram.ld', '-Wl,--gc-sections,--build-id=none',
           '-Wl,-Map=' + str(destination / 'firmware.map'), '-o', destination / 'firmware.elf'] + sources + ['-lgcc'],
           'coremark-build-' + str(iterations))
    memory = json.loads((src / 'config/soc_map.json').read_text(encoding='utf-8'))
    hex_image(destination / 'sram.hex', elf_sram((destination / 'firmware.elf').read_bytes(), memory))
    return gcc


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Review a saved physical CoreMark UART text file; opens no serial port.')
    parser.add_argument('log', type=Path)
    args = parser.parse_args()
    import json
    print(json.dumps(review_output(args.log.read_text(encoding='utf-8', errors='replace')), indent=2))
