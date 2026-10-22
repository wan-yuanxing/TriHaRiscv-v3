# DDR CoreMark performance diagnosis

Physical follow-up, authorized after this implementation checkpoint: release
32019ccd2f69 is now programmed/readback-verified and has one complete real
5000-iteration run:86.508181684CoreMark,0.865081817/MHz,0.013356211/CPU LUT6477.
Throughput+2.528851% versus the previous user-provided board run; CPU-LUT
efficiency+3.811055%. COM12 released, no Flash. See ddr_store_response_board.md
and its independently bound JSON. The remainder records the earlier digital/
physical-gate checkpoint; its packaging-stage unprogrammed status is historical.

2026-10-22. Worktree cpu/windows-baseline; backup cpu-before-ddr-profile-20261022
at977e151. Native Windows ModelSim/PDS/GCC15.2, -O2/noLTO;100MHz unchanged.
No JTAG/UART access or replacement of the user's current volatile image.

The user supplied a complete serial-assistant run after a brief KEY0 reset:
5925962666cycles,59.25962666seconds,84.374476888CoreMark,
0.843744769CoreMark/MHz,0.012865885CoreMark/CPU LUT6558. The parser accepts all
standard CRCs and the5000-iteration duration. It is user-provided text, not an
independently captured UART byte stream. It demonstrates a successful boot,
not unconditional DDR startup stability. Earlier init failures remain retained.

## Exact-window digital profile

The opt-in testbench observer decodes the actual rdcycle instructions issued
from the DDR payload. Loader reads, copying, initialization and score printing
are outside the window. Observed cycles must match the software CSR delta;
issue buckets, D-cache states and sampled bridge states each sum to that window.
All observers are outside synthesized RTL. Profiling enabled/disabled produced
identical one-iteration820472cycles and identical loadable bytes.

Five-iteration baseline uses the actual CPU/Cache/CDC/frozen native bridge with
digital DDR/PLL substitutes. It is not a board latency profile:

- 4077640 timed cycles,1448453 timed WB observations,70840 accepted stores.
- 273477 data reads:273429 hits,48 misses,99.982448% read hit rate.
- LSU issue-blocking category2354152cycles,57.7332% of the window.
- D-cache write-wait occupancy1782894cycles,43.7237% of the window.
- 70840 native writes; native reads include70840 verification reads as well as
  cache refills. The existing bridge acknowledges only after masked readback.

The LSU bucket and cache/bridge occupancy overlap; do not add their percentages.
High hit rate rules out insufficient capacity as the main explanation in this
model. Real DDR waiting may differ; no measured board stall percentages exist.

## Bounded response candidate

Retain blocking write-through/no-write-allocate, true lower acknowledgements,
error invalidation, private/shared attributes, maintenance and coordinated reset.
The fixed controller already demonstrates synchronous-lookup hit responses.
The candidate returns resident reads in that lookup cycle, dispatches stores
without an unused pre-write lookup cycle, and responds in the cache-update
cycle after the actual lower response. Native bridge/CDC/CPU RTL are unchanged.
There is no posted-store acknowledgement, dirty line or writeback policy change.

A dedicated latency check fails on the original resident-read response at
cycle399, then passes on the candidate. The component run also checks delayed
stores do not complete before the lower response and covers masks, failures,
refill errors, invalidation, maintenance, shared bypass and reset.

| Same-payload five-iteration digital run | Baseline | Candidate |
|---|---:|---:|
| Timed cycles |4077640|3665984|
| Short RTL CoreMark/MHz estimate |1.226199468|1.363890295|
| Timed WB observations |1448453|1448453|
| Accepted stores |70840|70840|
| Read hits / misses |273429 /48|273429 /48|

411656 fewer cycles, throughput+11.229072%. All CRCs pass. Complete timed WB
and store observations match line-for-line except the first absolute rdcycle
value and its corresponding timestamp store. That is a bounded observation
comparison, not a complete ISA proof. No new physical score or physical IPC.

Same CPU+Cache mapping fixture, with only triha_dcache.v differing among HDL/FDC
inputs:6890→6953LUT(+63,+0.914369%),4326FF/688RAM-LUT already included/11DRM/4APM
unchanged. Hierarchy attribution is6438→6484CPU LUT and452→469Cache/transport
LUT in this fixture; CPU RTL is unchanged. These are not the standalone-board
CPU-only resource counts, and are not substituted for its6558LUT denominator.
The short candidate UART still carries that old area metadata for comparison;
it is not a new admitted area/performance release.

## Validation and physical gate

Positive native runs: resident-response component check, real CPU/cache directed
test, joint I/D, local SoC runtime, Cache-bypass runtime, real CPU+CDC+native bridge
including live coordinated reset, and two-boot8KiB/FENCE.I board-wrapper digital
test. Corrupt data is rejected by both component and real-system runs; corrupt
CoreMark CRC reports errors=1 and is rejected.66CPU and45SoC Python checks,
configuration/source binding and PDS/STA parser checks pass.

The first actual new100MHz flow,
build/cpu/ddr-board-route-20261022T090507275782Z, completed but failed timing:
CPU Slow/Fast setup-0.544/+3.545ns,hold+0.156/+0.101ns,MPW+3.655/+4.202ns.
Worst setup is the original frontend decode FIFO bit22 to issue PC register
path;93CPU setup endpoints fail,TNS-24.764ns. The independent full frozen
review reports timing_closed=false; successful PDS stages do not override it.

Same RTL and byte-identical constraints, explicit placement seed2, are checked
in build/cpu/ddr-board-route-20261022T091827315671Z. It additionally corrects
the timing-external SRAM area metadata to6627. Full DDR payload bytes are
identical across that metadata change. Standalone board-context synthesis is
CPU-only6627LUT/3562FF/688RAM-LUT included/0DRM/4APM and cache/transport
506LUT/763FF/11DRM, versus baseline6558CPU LUT and519cache/transport LUT.
Do not replace these with the serial mapping fixture's hierarchy counts.
Seed2 terminal: CPU Slow/Fast setup-0.036/+3.427ns,hold+0.151/+0.100ns;
only one setup endpoint fails. Final worst path is D-cache RAM to LSU/branch/PC,
logic3.143ns and routing6.255ns; the first RAM-output net alone takes1.640ns.
It remains a timing failure, despite the small margin.

The seed comparison ends at1/2. One subsequent path-guided physical experiment
keeps seed2 and the same RTL: assign only u_dcache to the existing CPU placement
region(0,64,150,199). This changes the region FDC;100MHz/IO/hold/multicorner
timing FDC is byte-identical. It is not a third seed or a timing exception.
Run:build/cpu/ddr-board-route-20261022T093045697465Z. Independent terminal
bindings pass, but CPU Slow/Fast setup is-0.420/+3.500ns, with77 Slow setup
endpoints failing and TNS-11.532ns. CPU hold+0.158/+0.101ns, MPW
+3.655/+4.202ns, recovery/removal and Gray delay/skew pass. The worst path
returns to frontend FIFO rd_ptr_q[0] through decode/operands/branch to issue PC
CE:2.056ns logic and7.805ns route. The broad D-cache region assignment worsens
the overall result and has been removed. The combined fast-read/store candidate
is retained only in the frozen results and ddr_fast_response_diagnostic.patch.

## Store-only fallback

The fallback restores response_data_q and its RESPONSE cycle on every load.
It retains only immediate store dispatch and completion in STORE_UPDATE after
the real lower response. A store still waits for the native masked readback;
cache update/error invalidation complete at the acknowledgement edge before
another request can be accepted. CPU pipeline, bypass, predictor, Cache geometry,
DDR bridge,100MHz timing/IO/hold constraints and original region FDC are unchanged.

The new --store-response-check first rejects the original controller at cycle403
for the unused store lookup bubble, then passes the candidate while also checking
the original resident-load register boundary. Component data corruption is
rejected; real CPU/cache, joint I/D, local runtime and bypass, native-DDR system
including live coordinated reset, two complete board-wrapper boots, and real
DDR CRC corruption checks have new positive/negative logs.

Five-iteration same-payload digital comparison:

| Metric | Baseline | Store-only fallback |
|---|---:|---:|
| Timed cycles |4077640|3899101|
| Short RTL CoreMark/MHz estimate |1.226199468|1.282346879|
| Timed WB observations |1448453|1448453|
| Stores |70840|70840|
| Read hits / misses |273429 /48|273429 /48|

178539 fewer cycles; throughput+4.578979%. Both complete timed traces match
apart from the first absolute cycle read and its timestamp store. Native write,
verification-read and refill counts are unchanged. These modeled results do
not establish a board-score improvement; the first digital run's6558 area
metadata is provisional and is not a new mapped CPU denominator.

Actual standalone native mapping in
build/cpu/ddr-board-route-20261022T113604207883Z is CPU-only6477LUT/3562FF/
688RAM-LUT included/0DRM/4APM and Cache/transport492LUT/763FF/11DRM.
It is map-only and makes no frequency claim. The full5000-iteration image and
one-iteration preflight have been rebuilt with denominator6477 before the one
bounded final native route, using seed2 and the original region/timing FDC.

## Store-only physical admission and package

Final run:build/cpu/ddr-board-route-20261022T114044179848Z. All five actual
PDS stages and their native commands succeed; frozen source, tool, firmware,
hardware and output bindings pass independent review. The runner deliberately
returns REVIEW_REQUIRED until that review; its review-required code is not
the native PDS return code and is not a timing result.

| CPU clock check | Slow corner | Fast corner |
|---|---:|---:|
| Setup slack, ns |+0.314|+3.623|
| Hold slack, ns |+0.147|+0.100|
| Minimum pulse width slack, ns |+3.655|+4.202|

All clock-domain setup/hold/recovery/removal/pulse-width summary rows pass.
Performance slack+0.314ns agrees with the worst CPU setup path, frontend FIFO
ram_q[1][56] to exec result_q[31]. The report's calculated Fmax is not a higher
validated operating frequency. The original100MHz/IO/hold/multicorner and region
FDC files match the accepted parent byte-for-byte.

All60 Gray max-delay paths and20 Slow/Fast skew groups pass, with worst skew
slack+0.929ns and largest actual skew1.071ns under the original2ns requirement.
Actual final hierarchy resources match the preliminary native map: CPU-only
6477LUT/3562FF/688RAM-LUT included/0DRM/4APM; Cache/transport492LUT/763FF/11DRM.
CPU RTL is unchanged; the81-LUT difference from the6558-LUT accepted image is
measured in this board-context synthesis, not an intrinsic CPU state reduction.

The timing-admitted release is
build/soc/releases/cpu_ddr_coremark_on_32019ccd2f69, with16 manifest-bound files
and its manifest. Actual bitstream generation and every package hash pass;
the package includes the verification mask, routed database, native timing XML,
text report, exact5000-iteration firmware and DDR payload. Its SRAM-only LUT
metadata is6477; both full and short payload bytes are unchanged by correcting
that metadata. The release remains unprogrammed and has no new board score.

Final checks:66 CPU and45 SoC Python tests, Cache source/manifest check, both
config generators, PDS resource/STA parser checks and diff whitespace check pass.
The selected default RTL is the store-only candidate. The direct-read shortcut
and broad D-cache region experiment are excluded. There is no extra load stage,
posted store, altered readback policy or relaxed timing exception.

The original cached e5503c690208 image stays on the board with COM12 owned by
the user's serial assistant. No Flash, main-worktree edits, merge or push.

Digital evidence:build/cpu/ddr-performance-review-20261022/result.json.
Store-only evidence:build/cpu/ddr-store-response-review-20261022/result.json.
Final status and all bindings are recorded in ddr_performance.json.
