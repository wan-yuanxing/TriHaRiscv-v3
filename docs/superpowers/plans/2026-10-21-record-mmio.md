# Record MMIO and Pipeline Implementation Plan

> Execute inline with superpowers:executing-plans; use superpowers:requesting-code-review for independent read-only review. Preserve the existing checkout and all other routes.

**Goal:** Publish real RAW/BOX/AVATAR through the frozen display MMIO and connect it to the captured three-branch shared-DDR pipeline.

**Architecture:** The existing MMIO owns the sole display_slot_owner; new compositions reuse the exact scanner, record link and material renderer. Optional external health is disabled by default for legacy instances. Actual C drivers use live RTL bus replies; no injected lifecycle proof.

**Tech Stack:** Native Windows Python/Icarus/PDS/GCC; explicit manifests and held-bundle FDC; unchanged ABI/C drivers.

- [x] Snapshot HEAD, editable/protected paths and unrelated work under build/video/record_mmio_baseline.
- [x] Write tb_video_display_health.sv and tb_video_display_record.sv first; preserve missing-health-extension/missing-module compile RED. Add explicit live C/RTL test_video_record_pipeline.c, tb_video_record_pipeline.sv and video_record_pipeline_memory.sv with independent pixel/byte oracle.
- [x] Extend video_display_mmio with opt-in EXTERNAL_HEALTH and scoped fault reporting, minimally adapt its old wildcard TB. Add video_display_record.sv and video_record_pipeline.sv with all named connections and one owner/one DDR endpoint.
- [x] Register video_display_record/video_record_pipeline manifests/FDC and new run.py/build_pds.py hooks. Run record_mmio component tests and record_pipeline native C/RTL bad_eof/corrupt/full cases; preserve exact numerical counts and source/tool/artifact hashes.
- [x] Run targeted fault/mode/retirement/guard mutations, affected legacy display_mmio/display_scanout/video_pipeline and Python/config checks. Synthesize both new targets and inspect actual constraints/resources/setup/hold.
- [x] Obtain independent review, resolve findings, update spec/interfaces/README/STATUS/verification and machine evidence. Verify byte preservation outside hooks, exact owned staging and all external deltas; commit locally only.
