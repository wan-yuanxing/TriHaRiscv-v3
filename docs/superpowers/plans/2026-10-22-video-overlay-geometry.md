# Video Overlay Geometry Implementation Plan

> **For agentic workers:** Execute inline with superpowers:executing-plans. Existing user authorization covers this resource optimization; keep the current Video branch and preserve concurrent CPU/NPU files.

**Goal:** Reduce repeated overlay arithmetic without changing any pixel behavior or interface.

**Architecture:** Compute signed pixel-side bounds once, compare all signed16 record coordinates against them, and retain the existing clipping, priority and 13-stage pipeline.

**Tech Stack:** Windows native Python, Icarus, Pango PDS, SystemVerilog.

### Task 1: Establish reference and tests

- [x] Record hashes of unrelated dirty/untracked files under ignored build output.
- [x] Run `python scripts/video/build_pds.py --target video_overlay --stage synth` before RTL edits.
- [x] Add `scripts/video/test_overlay_geometry.py`: freeze overlay from commit 2463d01adbcb468d4953a4d98628a8d4235035f4; compare every output each cycle at posedge+1ns; reuse the independent oracle and file driver.
- [x] Generate deterministic boundary vectors: all 80 point lanes, all 16 boxes, signed16 extremes, exact inclusive point/exclusive box limits, invalid and clipped boxes, input blanking and mode changes, midstream reset.
- [x] Include parameter pairs (2,2), (1,0), (800,31), (3,31), (799,1). Compile deliberate point-edge, box-edge and priority faults and require runtime rejection.
- [x] Run the miter against unchanged RTL to establish a passing functional baseline. The pre-edit measured resource count is the performance failure, not a functional defect.

### Task 2: Share bounds

- [x] Modify only the geometry block of `rtl/video/display_overlay.sv`.
- [x] Add signed13 shared thresholds using explicit signed13 parameters: `px-W`, `px+W`, `py-W`, `py+W`, and analogous R bounds.
- [x] Keep clipped box and point coordinates signed16. Use `left > px-W || right <= px+W` only inside the unchanged rectangle containment condition; compare point centers against inclusive shared R bounds.
- [x] Run `python scripts/video/test_overlay_geometry.py`, ordinary and `python -O`.

### Task 3: Regress and measure

- [x] Run `python scripts/video/run.py --suite overlay`, `record_pixels`, `record_renderer`, `record_scanout`, and `record_pipeline`.
- [x] Retain the first full pixel simulation's measured 900-second timeout. Increase only the full-frame budget to the renderer's 1800 seconds and rerun; no change to simulation time, clocks, checks or small-case budgets.
- [x] Run native PDS overlay and full `video_record_probe` synthesis in unique directories. Compare matching target totals and hierarchy, not unrelated builds.
- [x] Inspect seed11 route result/log separately; keep timing_closed=false without complete final STA.
- [x] Update `docs/verification/video/overlay_geometry.md`, its small evidence JSON and Video STATUS. Remove only the duplicate own F4c5d section in HEAD projection; preserve concurrent NPU edits.
- [x] Review the scoped diff and verify protected files remain unchanged. Commit only this batch's paths, using an index projection for shared STATUS.
