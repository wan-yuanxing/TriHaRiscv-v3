# Dual-issue performance target and comparison boundary

Latest user scope: on-chip SRAM/TCM is the primary boundary for >4 CoreMark/MHz;
DDR with I/D Cache enabled is the integration performance boundary. DDR Cache-off
is excluded from further optimization and acceptance; existing results are historical.
Keep GCC15.2 -O2, no LTO, RV32IM/CSR, six main stages and existing predictor
configuration. Report active DDR cached and TCM results separately. No latency or
algorithm substitution is a CPU speedup. Five-iteration simulation is a short
estimate; deployment still requires actual 100MHz and valid board duration.

## Measurement first

The completed DDR on/off matrix remains historical evidence. Do not rerun or
optimize DDR bypass for future candidates. Active TCM and cached-DDR measurements
retain fixed compiler settings, CRC checks, and full WB/store comparisons.

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

## Actual timing is mandatory

A short RTL score above 4 does not qualify the CPU. Acceptance requires the same
candidate to pass actual postroute 100MHz setup, hold and pulse-width checks in
both Slow/Fast corners, under the original clock/I/O constraints and an actual
memory/system boundary. CPU-only area is reported separately from fixture area.
The legacy run_route.ps1 is explicitly single-issue-only and is not a valid
unmodified entry for the candidate. Prepare a frozen dual-issue physical target
before launching tools; do not interfere with ongoing SoC physical work.
