# DDR CoreMark performance implementation plan

2026-10-22. User approved continuing the performance diagnosis and optimization.
Use the existing isolated cpu/windows-baseline worktree and native Windows tools.
Execute inline with review checkpoints; no agents, UART, JTAG or Flash.

Goal: attribute the measured0.843744769CoreMark/MHz and implement a measured,
contract-preserving improvement where the evidence supports it.

Architecture: add an opt-in simulation observer outside synthesized RTL. Decode
the actual rdcycle instructions issued from the DDR payload, excluding loader
reads. Count the exact timed window and mutually exclusive issue categories;
also count D-cache state occupancy/hits, lower transactions and bridge phases.
Native DDR remains a digital substitute: these counters explain that model,
not measured board stall percentages. Keep100MHz/GCC15.2-O2/noLTO and six-stage
single-issue/predictor/cache geometry. Normal runs and payload bytes stay intact.

The existing DDR contract requires readback before B OKAY. Retain it. Early
write completion/writeback cache would require a separate ordering/error design;
do not silently introduce either as a local performance patch.

- [x] Back up977e151 with cpu-before-ddr-profile-20261022 and preserve the user's
  successful serial-assistant output as user-provided evidence, not raw capture.
- [x] Add scripts/cpu/test_ddr_profile.py before implementation. Synthetic
  profile records must reject mismatched rdcycle windows, missing/duplicate
  fields, mismatched cycle/category/state totals, and inconsistent request counts.
  Run `python -m unittest discover -s scripts/cpu -p test_ddr_profile.py` RED.
- [x] Implement scripts/cpu/ddr_profile.py and the testbench-only observer
  tb/soc/cpu_ddr_coremark_profile.vh. Extend run_ddr_coremark.py with --profile,
  snapshot/validate the observer and parser, and save structured profile data.
  The observer must assert two payload rdcycle reads and no dual completion or
  timed architectural exception. Run parser tests GREEN and actual ModelSim.
- [x] Profile cached and shared-uncached one-iteration payloads using the actual
  CPU/Cache/CDC/frozen bridge with the same digital DDR model. Compare the
  profiling-disabled cached cycles/loadable image against profiling-enabled
  to ensure the observer has no effect. Require standard CRCs and exact CSR
  cycle equality. Inspect measured waiting, not inferred SRAM/DDR ratios.
- [x] Choose one bounded optimization from the observed dominant local cost.
  First add a self-check that fails for its latency/throughput requirement;
  preserve address attributes, write acknowledgement, errors, fences and reset.
  Reference fixed upstream cache/transport behavior when applicable. Retest
  real CoreMark and component/integration positives and fault negatives.
- [x] Only if functional performance and CPU-only area justify it, run actual
  original100MHz multi-corner post-route admission. Otherwise retain the original
  hardware and document why the candidate stopped. No new board score claim.
- [x] Save docs/verification/cpu/ddr_performance.md/.json, update STATUS, run CPU
  and SoC Python/config checks plus relevant ModelSim and PDS parser checks,
  and commit explicit files only. Keep user COM12 ownership and current image.

First bounded candidate after attribution: retain blocking write-through and
verified lower responses. Follow the fixed cache controller's existing lookup
response organization for resident loads instead of an extra response register
cycle; stores bypass an unused pre-write lookup state and acknowledge in the
cache-update cycle only after the actual lower response. No posted stores,
dirty state, eviction, address-policy or native bridge changes. Directed checks
require synchronous-lookup hit latency, immediate dispatch and post-lower-ack
response, while existing delayed/error stores must still be rejected correctly.
The direct RAM-return path must pass actual100MHz STA before selection.

Physical checkpoint: seed1 completed but CPU setup is-0.544ns with93 failing
endpoints; worst path is the existing frontend FIFO to issue PC registers.
Run one explicit seed2 comparison with unchanged RTL/FDC and the corrected6627
CPU-LUT metadata outside timing. A new native preflight verifies that metadata
change leaves the loaded DDR payload unchanged. Limit this batch to seeds1/2;
Do not publish a failing candidate.

Seed2 terminal: only one setup endpoint fails,-0.036ns. Actual path is D-cache
RAM to LSU/branch/PC; the first data net alone takes1.640ns and total route is
6.255ns versus logic3.143ns. The previously unconstrained D-cache RAM is far
from the CPU's fixed region. Keep seed2 and unchanged RTL/timing constraints;
run one path-guided placement change assigning u_dcache to the existing CPU
region(0,64,150,199). This is a physical region change, not another seed search.
If it fails, retain the full diagnostic and restore baseline RTL/region rather
than releasing a timing failure. All intermediate terminal evidence remains.

Region terminal: Slow/Fast CPU setup -0.420/+3.500ns, with77 Slow setup
endpoints failing and TNS-11.532ns. CPU hold+0.158/+0.101ns and MPW
+3.655/+4.202ns pass. The worst frontend FIFO-to-issue-PC path has7.805ns
routing and2.056ns logic. Independent frozen review passes, timing does not.
The whole-D-cache region constraint has been restored to the original FDC.

Within the already authorized response optimization, roll back the direct
load shortcut while retaining only the store-dispatch/completion improvement.
This keeps the original response_data_q boundary on every load; no extra CPU
stage or new cache policy is introduced. Preserve the rejected combined
candidate in docs/verification/cpu/ddr_fast_response_diagnostic.patch and its
three frozen route directories. A new --store-response-check must first reject
the original store bubbles, then accept the store-only candidate while checking
that resident loads retain the register boundary. Compare the full five-iteration
DDR profile/WB/store traces with the same baseline payload, rerun relevant
positive/negative cache and DDR tests, then attempt one native100MHz flow with
the original region FDC and seed2. No additional seed sweep. On timing failure,
archive this candidate and restore the accepted D-cache/manifest; on timing
success, package for later board measurement without UART/JTAG/Flash access.

Store-only digital checkpoint:3899101cycles versus4077640, +4.578979%
throughput;1448453 WB observations/70840 stores, identical payload and traces
apart from initial absolute timing values. Native read/write event counts match.
CPU-only native map6477LUT/3562FF/688RAM-LUT included/0DRM/4APM;
Cache/transport492LUT/763FF/11DRM. Full/preflight firmware now prints6477;
one-iteration preflight784812cycles and standard CRCs pass. Final bounded route:
build/cpu/ddr-board-route-20261022T114044179848Z, original region FDC, seed2.

Terminal: independent final physical review passes100MHz. CPU Slow/Fast
setup+0.314/+3.623ns, hold+0.147/+0.100ns, MPW+3.655/+4.202ns;
all clocks/corners including recovery/removal and Gray delay/skew pass.
CPU/Cache resources match the native map. Package
build/soc/releases/cpu_ddr_coremark_on_32019ccd2f69 is generated and all16
manifest-listed file hashes verified.66CPU/45SoC Python checks and original
configuration/PDS/route parser checks pass. Store-only selected; fast-load and
D-cache-region experiments excluded. Next is separately authorized physical
measurement with the user's serial assistant; no new board-score claim yet.
