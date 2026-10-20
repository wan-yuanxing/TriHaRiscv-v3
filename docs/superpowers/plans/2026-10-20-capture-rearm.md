# Capture Rearm Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans in this checkout; independent review uses superpowers:requesting-code-review. User has authorized implementation and local exact commits.

**Goal:** Enable opt-in sequential good-frame capture without resetting FIFO, DDR or display.

**Architecture:** Default-off parameters preserve single-shot consumers. A consumed successful completion reopens the capture kernel; the next request clears only idle preprocessing and per-job state. The pixel ingress consumes the next arm in its stopped state with persistent FIFO pointers. Faults remain terminal.

**Tech Stack:** Native Windows Python, Icarus/SystemVerilog, PDS; explicit JSON filelists.

## Tasks

- [x] Read capture ingress, FIFO, three-branch kernel, preprocessing and DMA; snapshot protected and unrelated files in `build/video/capture_rearm_baseline`.
- [x] Add `tb/video/tb_video_capture_rearm.sv` and explicit `fpga/pg2l100h/project/video_capture_rearm.json`; capture a RED where the second request times out with unchanged production RTL. Use a test parameter to enable the new parameters only after they exist, so RED compiles and exercises the missing behavior.

```systemverilog
// The first job must succeed before testing rearm.
completion_ready=1;
repeat(16) @(negedge clk);
if(!req_ready) $fatal(1,"REARM_SECOND_REQUEST_BLOCKED");
```

- [x] Add `ENABLE_REARM=0` to `rtl/video/video_capture_ingress.sv` and `rtl/video/video_three_branch_capture.sv`. Gate STOPPED-arm reuse on source health; clear per-frame source state and wait for the next start. Gate DONE-to-IDLE on consumed success, accepted consumption, drained port and fresh health. Clear preprocessing and job statistics at the next valid request.

```systemverilog
wire job_clear=ENABLE_REARM && req_valid && req_ready;
// Clear synchronous preprocessing only while no descriptor or old stream is live.
// FIFO pointers and DMA reset signals retain their existing coordinated reset.
```

- [x] Run `python scripts/video/run.py --suite capture_rearm`, covering repeat frames, slot reuse, held records/final B, asynchronous clocks, source clock pause and terminal error draining. Add meaningful mutants under ignored `build/video` to prove missing clear, early rearm and failure reuse are detected.
- [x] Add a synthesis-only enabled-kernel wrapper `rtl/video/video_capture_rearm_core.sv`, 8ns FDC and `scripts/video/build_pds.py` target. Run `python scripts/video/build_pds.py --target video_capture_rearm --stage synth`; inspect timing/warnings and distinguish synthesis estimates from routing.
- [x] Run old `three_capture`, `capture_ingress`, `capture_mmio`, `frame_pool` suites plus Python checks and generated-header checks. Request an independent reviewer to inspect the final worktree against HEAD 013632f, with own logs under ignored build/video and no board operations.
- [x] Close review findings with RED/GREEN when needed. Update `docs/video/STATUS.md`, README, interface/main-spec implementation boundaries and verification/evidence files; hash-bind current sources and artifacts. Verify protected/unrelated bytes and line endings; commit only the enumerated batch files.

Expected completion marker is `VIDEO_CAPTURE_REARM_PASS`; all failure scenarios must remain unable to advertise another request. No board acceptance is part of this plan.
