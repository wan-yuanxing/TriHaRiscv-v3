# DDR CoreMark physical checkpoint

2026-10-22, parent baa980f, cpu/windows-baseline. Native Windows tools only.
Raw bindings: id_cache_board_coremark_checkpoint.json.

The standalone DDR diagnostic was programmed and verified, then observed three
complete private/shared8192-byte/FENCE.I boots, including the user's KEY0 reset.
The cached CoreMark image subsequently passed actual100MHz post-route timing
and two5000-iteration physical runs. GCC15.2-O2/noLTO, RV32IM/CSR, single issue,
BTB512/BHT512/RAS4, GShare off; I/D16KiB/two ways/32B, D write-through.

| Physical private-DDR cached run | First | Repeat |
|---|---:|---:|
| Cycles, full64-bit | 5925962390 | 5925962602 |
| Seconds at nominal100MHz | 59.25962390 | 59.25962602 |
| CoreMark | 84.374480817 | 84.374477799 |
| CoreMark/MHz | 0.843744808 | 0.843744778 |
| CPU-only LUTs | 6558 | 6558 |
| CoreMark/CPU LUT | 0.012865886 | 0.012865886 |

Both runs passed standard seed/list/matrix/state CRCs e9f5/e714/1fd7/8e3a and
the upstream correctness/duration checks. They are actual board results, not
RTL estimates or an official submission. No instret CSR exists; board IPC is
unknown. The original upstream Total ticks field prints only the low32bits;
CPU_COREMARK_TIME high/low plus the precise score fields are the authoritative
64-bit report. The two runs differ by212cycles, about0.00000358%.

CPU-only6558LUT/3562FF/688RAM-LUT(included)/0DRM/4APM. Cache/transport is
519LUT/763FF/11DRM36K-equivalent; CDC/DDR/board are separate. CPU setup Slow/Fast
+0.213/+3.617ns, hold+0.136/+0.082ns, MPW+3.655/+4.202ns; all-clock recovery,
removal and Gray checks also passed. The loaded DDR program starts0x80000000;
code, work data and16KiB stack are in private DDR. SRAM startup copies/verifies
the payload before timing; SRAM0x16ff0 supplies area metadata after timing.

Compile-time Cache-off also passed actual100MHz setup+0.066ns worst, with
CPU6466LUT, but **failed physical DDR initialization before payload copy**.
Program/Verify passed; UART reported CPU_DDR_COREMARK_FAIL init twice. User
KEY0 observation: LED0 blinking, LED1 off, LED3 on. The manual-retry UART was
not captured because its initial180-second window expired; do not claim a
second raw-UART failure. Detailed PLL/training cause remains UNKNOWN. This
image supplies no valid performance score, and no Cache speedup is claimed.

Both versions used identical DDR IP source hashes, FDC and loaded benchmark
bytes. Their hardware/netlists/layouts differ, so this is not evidence that
the Cache itself causes or fixes training. Writes currently complete through
the native bridge's actual write/readback verification; this adds DDR latency.
SRAM performance is a different boundary and cannot isolate Cache benefit.

User selected a follow-up using the successful Cache-enabled hardware with
the shared-DDR region's uncached attributes. It will be labeled a private-
cached/shared-uncached comparison, not same-address compile-time Cache off/on.
The current volatile image is cpu_ddr_coremark_on_e5503c690208. No Flash,
main-worktree edits, merge or push. The old SRAM release files remain intact.
