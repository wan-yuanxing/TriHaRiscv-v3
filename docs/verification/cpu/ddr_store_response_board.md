# DDR store response: physical CoreMark acceptance

2026-10-22. The user explicitly requested testing the admitted candidate on the
board. PG2L100H / device ID 00602899 was identified, then release
`cpu_ddr_coremark_on_32019ccd2f69` was loaded into volatile configuration and
readback-verified. Native Program and Verify both returned success; no Flash
write was performed. This release is now retained on the board.

The UART reader opened COM12 before programming, captured raw bytes, and closed
cleanly after one complete result. No physical KEY0 action was needed. Two
loader banners are present: the initial incomplete programming epoch is retained
in the raw log, while exactly one final epoch reaches BOARD_PASS. This is one
measured run, not two successful boots or a repeated-training stability test.

| Physical measurement | Previous accepted image | Store-only candidate |
|---|---:|---:|
| Iterations | 5,000 | 5,000 |
| Timed cycles | 5,925,962,666 | 5,779,800,133 |
| Seconds at nominal 100 MHz | 59.25962666 | 57.79800133 |
| CoreMark, calculated from cycles | 84.374476888 | 86.508181684 |
| CoreMark/MHz | 0.843744769 | 0.865081817 |
| CPU-only LUTs | 6,558 | 6,477 |
| CoreMark/CPU LUT | 0.012865885 | 0.013356211 |

Throughput improves **2.528851%**, using 146,162,533 fewer cycles; efficiency
per CPU LUT improves **3.811055%**. The baseline is the user's saved serial
assistant text, validated again against its recorded hash; the new result is an
independent raw UART capture. This is not a fresh alternating two-image trial.

Both images load byte-identical DDR payloads (SHA256
`04c2ae6b5d6efdb45a7432244d4f68c28441dbbf02937c9ed6f105ed14257216`).
Compiler/version/flags and private DDR stack location match, including GCC15.2,
`-O2`, no LTO, and 5,000 iterations. The new UART LUT denominator is independently
matched to the actual native synthesis hierarchy, 6,477. The separate Cache and
transport hierarchy remains 492 LUT / 763 FF / 11 DRM; it is excluded from the
CPU-only denominator.

All standard CRCs (`e9f5/e714/1fd7/8e3a`, final `bd59`) pass. UART reports
`errors=0 short=0` and `CPU_COREMARK_BOARD_PASS iterations=5000`. Its precise
score, time and CoreMark/LUTs agree with the full 64-bit cycle count, including
`cycles_hi=1 cycles_lo=1484832837`.

The actual post-route 100MHz admission and all frozen sources/tools/outputs
were rechecked against the package before programming and during the independent
board evidence review. CPU Slow/Fast setup is +0.314/+3.623ns; hold
+0.147/+0.100ns; minimum pulse width +3.655/+4.202ns. All clocks and Gray delay/
skew checks pass. Nominal clock frequency is used for scores; this run does not
add independent instrument frequency calibration, physical retirement IPC,
official CoreMark submission, shared-SoC fabric or full-ISA acceptance.

The observed physical gain is smaller than the +4.578979% five-iteration digital
model gain. The model's DDR waiting and clock phases are not board latency
measurements; this physical result takes precedence. No physical stall profile
was collected, so the difference is not attributed to a measured stall category.

Evidence, all bound in `ddr_store_response_board.json`:

- Capture: `build/soc/ddr-coremark-physical-20261022T115703162826Z/result.json`.
- Raw bytes: the same directory's `uart.bin`; complete measured epoch:
  `measurement-uart.txt`. The initial incomplete epoch remains in `uart.bin`.
- Actual download/readback:
  `build/soc/board-ddr-program-20261022T115707081040Z/result.json` and
  `program_verify.log`.
- Package: `build/soc/releases/cpu_ddr_coremark_on_32019ccd2f69`.
- Independent reviewer: `build/cpu/review-ddr-store-board-20261022.py`.

COM12 is released for the user's serial assistant (115200 / 8N1 / no flow
control). Brief KEY0 reset reruns this image; no long button hold or further
download was used in this acceptance. The known earlier DDR startup failures
remain recorded; one successful new automatic start does not resolve their cause.
