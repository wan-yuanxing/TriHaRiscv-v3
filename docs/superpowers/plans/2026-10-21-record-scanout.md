# Record Scanout Implementation Plan

> Execute inline with superpowers:executing-plans. Independent read-only review uses superpowers:requesting-code-review. Stay in the existing authorized Video checkout.

**Goal:** Drive full-record rendering from actual DDR scanout pixels and join scanner/pixel retirement before the existing Video owner releases a slot.

**Architecture:** Extend raw_display with aligned generation/identity sidebands; compose it with video_record_renderer and display_slot_owner using a new event join. Validated caller records and immutable material remain explicit contracts; formal MMIO and CPU global ownership remain unchanged.

**Tech Stack:** Native Windows Python/Icarus/PDS, explicit manifests/FDC, independent pixel oracle.

- [x] Save base HEAD and protected/editable/unrelated file hashes under build/video/scanout_record_baseline.
- [x] Add tb/video/tb_display_record_link.sv and tb/video/tb_video_record_scanout.sv, tb/video/models/video_scanout_memory.sv, scripts/video/test_record_scanout.py. Compile to preserve missing-module/sideband RED.
- [x] Extend rtl/video/raw_display.sv with record_generation, held generation events and aligned pixel identity/x/y/SOF. Add display_record_link.sv and video_record_scanout.sv with explicit ports; adapt only tb_raw_display's wildcard instance to explicitly tie/ignore the new sidebands. Freeze unrelated RTL/ABI/C files.
- [x] Register explicit project/constraints and run.py/build_pds.py hooks. Run python scripts/video/run.py --suite record_scanout for directed event joins plus small/ratio/full actual memory-to-output cases.
- [x] Verify negative identity/early retirement mutations; run affected raw_display/display_scanout/video_pipeline regression and Python checks. Synthesize video_record_scanout and inspect constraint applicability/resources/setup/hold honestly.
- [x] Independently review and resolve findings. Update STATUS/README/interfaces/spec and docs/verification/video/record_scanout.md with machine evidence. Audit exact owned staging, retain all CPU/NPU/report work and STATUS deltas; commit locally.
