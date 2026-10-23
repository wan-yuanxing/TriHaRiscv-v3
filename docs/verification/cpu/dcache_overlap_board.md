# Write-back / load-overlap physical CoreMark

2026-10-23. Source commit `febadb3`, release
`cpu_ddr_coremark_on_478149ee9e63`. The user approved measuring this image
before advancing to safe store overlap. Actual PG2L100H / 00602899 volatile
Program and readback Verify both succeeded. No Flash write or long KEY0 hold.

| Physical result | Prior deployed WT store-response image | WB + load-overlap image |
|---|---:|---:|
| Iterations | 5000 | 5000 |
| Cycles | 5,779,800,133 | 2,002,053,973 |
| Seconds, nominal 100MHz | 57.79800133 | 20.02053973 |
| CoreMark | 86.508181684 | 249.743516780 |
| CoreMark/MHz | 0.865081817 | 2.497435168 |
| CPU-only LUTs | 6477 | 6507 |
| CoreMark/CPU LUT | 0.013356211 | 0.038380746 |

Measured throughput +188.693522%, CPU-LUT efficiency +187.362524%. Both results
are independently captured raw UART, with byte-identical loaded DDR payload
SHA256 `04c2ae6b5d6efdb45a7432244d4f68c28441dbbf02937c9ed6f105ed14257216`.
GCC15.2 `-O2`/no-LTO, predictor, CPU clock, private DDR placement and stack
match. This comparison includes both write-back and load-response overlap;
it cannot isolate their individual physical contributions and is not a fresh
alternating-image experiment. The new store-overlap candidate is not measured
by this result.

The full 64-bit cycle count, exact formatter values, all standard CRCs including
final `bd59`, `errors=0 short=0` and BOARD_PASS were independently checked.
Only one final programming epoch completes. The raw capture also retains an
incomplete loader epoch from programming; this does not prove repeated-boot or
DDR-training stability. Nominal frequency is used, with no independent frequency
calibration, physical retirement IPC or official benchmark submission claim.

CPU-only6507LUT/3562FF/688 distributed-RAM LUT already included/0DRM/4APM.
Cache/transport668LUT/807FF/11DRM is separate. Actual unchanged-constraint
100MHz final timing remains admitted: CPU Slow/Fast setup+0.309/+3.551ns,
hold+0.151/+0.099ns, MPW+3.655/+4.202ns; every clock-domain summary and complete
Gray max-delay/skew coverage passes. All immutable release, original routed
inputs/outputs and programming tool hashes were rechecked.

Evidence in `dcache_overlap_board.json`:

- `build/soc/ddr-coremark-physical-20261023T020247339677Z/result.json`, raw
  `uart.bin` and complete `measurement-uart.txt`.
- `build/soc/board-ddr-program-20261023T020251383504Z/result.json` and actual
  `program_verify.log`.
- `build/cpu/review-dcache-overlap-board-20261023.py` independently checks UART,
  the package, actual Program/Verify and post-route timing; no new board action.

The measured image is retained on the board. COM12 is released; user serial
settings remain115200/8N1/no flow control, brief KEY0 reruns the benchmark.
New RTL experiments stay in the isolated CPU worktree and do not change the
board until their own functional, resource and physical gates pass.
