# Dual-issue performance target and comparison boundary

The user requires Cache-off/on scores for dual issue and selected on-chip
SRAM/TCM as the primary boundary for the maximum target above 4 CoreMark/MHz.
Keep GCC15.2 -O2, no LTO, RV32IM/CSR, six main stages and existing predictor
configuration. Report DDR bypass, DDR cached and TCM separately. No latency or
algorithm substitution is a CPU speedup. Five-iteration simulation is a short
estimate; deployment still requires actual 100MHz and valid board duration.

## Measurement first

Reuse the accepted cached single/dual runs and complete both actual DDR
bypass runs with the same loaded program, memory model and full WB/store
comparison. Retain the existing CRC and corruption checks. The no-Cache DDR
result must not be represented by the independent TCM result.

For five iterations, >4/MHz requires <1,250,000 cycles. The current TCM dual
baseline is 1,411,226 cycles, so at least 161,227 cycles must be removed.
Add a passive testbench observer to classify the exact TCM rdcycle window:
issued/paired cycles, frontend starvation, LSU/pipeline/divide/CSR waits,
real versus unused-field dependencies, structural pair rejection and
eligible narrow-MUL dependencies. Save both full timed WB/store streams.
The observer must reproduce 1,411,226 cycles and 1,448,448 WB observations
before its counters are used. It adds no production hardware.

## Candidate decision

Measure the opportunities before modifying RTL. Prioritize existing legal
dependency/forwarding paths: ISA field-use qualification can remove false
second-slot dependencies; the accepted narrow-product E1 bypass can be
adapted to the lane owning the shared multiplier. Both require real RAW/WAW,
same-address write priority, wide/high multiply, exception/flush/interrupt,
hold and ordered-stream tests. Reuse the existing mature structures and
tests. The prior single-issue false-dependency experiment saved only35
cycles and was rejected; do not assume its result predicts dual pairing.

Changing the instruction queue or predictor is a larger alternative. Only
consider it if measured packet/branch losses justify the change. CPU-only
resource and actual timing checks follow functional/performance screening,
scheduled outside the ongoing SoC PDS work. Do not program the shared board.
