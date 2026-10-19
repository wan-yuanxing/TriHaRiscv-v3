# CPU Video control implementation plan

> Execute with superpowers:subagent-driven-development. Use fresh implementers
> for isolated bridge and firmware-fixture tasks, then independent spec and
> quality review. Continue in the current Video checkout; do not modify CPU
> worktree or other-route files. User has authorized this continuation.

**Goal:** A tested native-tag CPU to Video AXI-Lite control path, including real
frozen CPU firmware execution, without importing an unfinished SoC fabric.

**Architecture:** single outstanding registered native adapter -> unchanged
Video MMIO -> unchanged real capture core. Separate explicit pinned-CPU fixture.

**Tech stack:** Verilog/SystemVerilog, Windows Python, Icarus, ModelSim, GCC, PDS.

Contract: `../specs/2026-10-19-cpu-video-control-design.md`.

## Task 1 — adapter (isolated implementer)

Files: create `rtl/soc/cpu_native_axil.v`, `tb/soc/tb_cpu_native_axil.sv`.

- [ ] Write self-checking TB first with the exact contract ports. Example oracle:
  `if (cpu_ack && (cpu_resp_tag !== expected_tag || cpu_error !== expected_error))
  $fatal(1,"native completion mismatch");` Count every AW/W/AR and ACK handshake
  independently, proving one transaction per accepted native request.
- [ ] Compile without RTL; retain missing-module RED under build/video/cpu_video_red.
- [ ] Implement the contract; run Icarus and require `CPU_NATIVE_AXIL_PASS`.
- [ ] Cover all tags/strobes, independent stalls, native immutability, error/X,
  reset and response gating. Compile and reject meaningful transport mutants.
- [ ] Freeze adapter sources and provide input/artifact hashes; parent commits.

## Task 2 — real CPU fixture (fresh implementer after Task 1 ports frozen)

Files: create `config/cpu_video_fixture.json`,
`scripts/soc/run_cpu_video.py`, `tb/soc/tb_cpu_video_firmware.sv`,
`sw/tests/video_control/start.S`, `sw/tests/video_control/link.ld`,
`sw/tests/video_control/main.c` and narrow runner tests if necessary.

- [ ] Pin full CPU `8a2a07c` revision and explicit production source/header/license
  blobs. Never use its dirty working files. Test missing object, unsafe path,
  corrupted exported blob and stale generated Video headers before implementation.
- [ ] Implement `python scripts/soc/run_cpu_video.py --suite bridge|firmware|all`;
  reuse installed-tool discovery, isolated dirs, UTF8 and nonzero failure rules.
  Bind original inputs, Git blob IDs, copied hashes, model/tool hashes and logs.
- [ ] Write firmware/TB first; actual CPU must fail without adapter/control path.
  Use fixture ROM at0, SRAM0x10000/32KiB, ordinary SRAM signature, no exit MMIO.
- [ ] Implement startup/trap handling and C polling/IRQ/error tests against
  generated `video_regs.h`; use real MMIO+capture+DMA+byte memory, small geometry.
  Trap oracle must check actual load/store access faults, not a synthetic IRQ.
- [ ] Run single/dual CPU with deterministic bus backpressure. Require firmware
  signature, real capture bytes, complete retirement conditions and trap evidence;
  reject a real response/data corruption mutant. Keep failed logs.
- [ ] Report exact scope and stable input/output maps; no CPU/board timing claim.

## Task 3 — parent integration and review

Files: create `fpga/pg2l100h/project/cpu_native_axil.json` and
`fpga/pg2l100h/constraints/cpu_native_axil.fdc`; modify `scripts/video/run.py`,
`scripts/video/build_pds.py`, `docs/interfaces/video.md`, `docs/video/README.md`,
`docs/video/STATUS.md`; create `docs/verification/video/cpu_video_control.md` and
`docs/verification/video/evidence/cpu_video_control.json`.

- [ ] Add synth-only explicit adapter target with8ns `clk_i`; maintain before/after
  source and snapshot verification. Run `--stage route/bitstream` rejection.
- [ ] Add portable `--suite cpu_axil` and all selector to Video runner, hashing
  explicit adapter/TB/manifest. Do not make portable all depend on CPU Git object.
- [ ] Independently review spec compliance, then quality; resolve material
  findings with retained RED/GREEN and bind current hashes.
- [ ] Freeze sources. Run `python scripts/video/run.py --suite all`,
  `python scripts/video/build_pds.py --target cpu_native_axil --stage synth`,
  and `python scripts/soc/run_cpu_video.py --suite all` on the frozen version.
- [ ] Update docs with actual totals, pinned CPU, fixture scope and remaining
  fabric/ownership/board work. Verify prior board sources and unrelated changes.
- [ ] Stage only this batch's exact file list; diff-check, local commit and audit
  HEAD/filter identity, input/artifact hashes and preservation. No push/merge.
