# Display Scanout Link Implementation Plan

> **For agentic workers:** Execute inline with superpowers:executing-plans in the authorized checkout. Use superpowers:requesting-code-review for independent review only.

**Goal:** Connect real RAW commit/retirement to the frozen display MMIO owner, with identity preservation and CPU pool trace verification.

**Architecture:** A core link latches each command and per-slot generation, waits for raw commit, and then retires the previous raw reference. Same-RAW mode commands cross the existing mode CDC and wait for an aligned raster boundary. A new RAW-only wrapper exposes MMIO and scanout without changing existing modules.

**Tech Stack:** Windows Python/Icarus/C99/PDS; explicit filelists; core8ns/pixel25ns component constraints.

- [x] Snapshot bf6effc and all unrelated paths before implementation; preserve existing core/ABI/software bytes.
- [x] Write `tb/video/tb_display_scanout_link.sv` with independently controlled raw event peers. Save a behavioral RED proving command acceptance cannot stand in for raw commit.

```systemverilog
if(feedback_valid && raw_commits==0) $fatal(1,"LINK_COMMIT_PRECEDES_RAW");
```

- [x] Add `rtl/video/display_scanout_link.sv` with one latched command, per-slot identity, held feedback/retirement, same-RAW mode CDC and sticky faults. Add `video_display_scanout.sv`, explicit JSON/FDC and runner/builder hooks; expose only RAW capability.
- [x] Add `tb/video/tb_video_display_scanout.sv` for actual MMIO/owner/link/raw/CDC and byte-address BFM. Check complete rasters, true events, three-slot reuse and held software ACK; include default800×600 and alternate digital clock ratios.
- [x] Add `tb/video/test_display_scanout.c` and `scripts/video/test_display_scanout.py`; execute unchanged C pool/display driver and replay actual R/W/F with wait-only event tokens, never fabricated pixel feedback.
- [x] Run new suite, targeted policy mutations, old display_mmio/frame_pool/raw_display/mode_resources and Python checks. Synthesize wrapper with all scalar/bundle CDC constraints, inspect warnings and report component limits.
- [x] Independently review protocol/lease/identity and close findings with RED/GREEN; update STATUS/interfaces/spec/verification/evidence, audit protected bytes and only added entrypoint hooks, commit the explicit file list locally and verify delivery.
