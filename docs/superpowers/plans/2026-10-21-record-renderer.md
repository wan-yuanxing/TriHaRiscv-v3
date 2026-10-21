# Record Renderer Implementation Plan

> Execute inline with superpowers:executing-plans; use superpowers:requesting-code-review for independent read-only review.

**Goal:** Share one AXI128 read path between RAW and material loading and render validated full records with the actual immutable material provider.

**Architecture:** New one-outstanding owner arbiter precedes the unchanged shared DDR endpoint. A new composition joins the frozen record/pixel and DDR material components; RAW stream identity remains an explicit caller contract.

**Tech Stack:** Windows Python/Icarus/PDS, explicit JSON/FDC, core8ns/pixel25ns, independent integer oracle.

- [x] Snapshot HEAD, protected sources and unrelated work; preserve existing STATUS append.
- [x] Write tb/video/tb_video_read_arbiter.sv, tb/video/tb_video_record_renderer.sv, tb/video/models/video_renderer_memory.sv and scripts/video/test_record_renderer.py first. Record expected missing-module compile RED under build/video/renderer_red.
- [x] Implement rtl/video/video_read_arbiter.sv and rtl/video/video_record_renderer.sv with explicit fpga/pg2l100h/project/video_record_renderer.json and constraints/video_record_renderer.fdc; preserve existing modules. Add only new run.py/build_pds.py hooks.
- [x] Run python scripts/video/run.py --suite record_renderer: owner routing with equal/different IDs, urgent quota/round robin, AR/R stalls, online/memory fault, premature/unknown/wrong responses and sticky undrained; actual shared DDR material/provider plus full800×600 and small RAW/BOX/AVATAR oracle, identity/commit/retire and reset.
- [x] Detect targeted routing/fairness/posted-AR/provider/CDC/commit mutations; run affected avatar_ddr/shared_video and Python/config regressions. Synthesize python scripts/video/build_pds.py --target video_record_renderer --stage synth and inspect applicable constraints/resources/actual timing.
- [x] Independently review and close findings; update STATUS/README/interfaces/spec and docs/verification/video/record_renderer.md/evidence/record_renderer.json. Audit byte preservation outside hooks and exact owned staging, retain other-route changes, commit locally only.
