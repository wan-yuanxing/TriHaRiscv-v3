# Display Record Pixels Implementation Plan

> Execute inline with superpowers:executing-plans; independent review only uses superpowers:requesting-code-review.

**Goal:** Commit a full validated display record atomically at the matching source SOF and prove pixel/material retirement after the output pipeline.

**Architecture:** New explicit wrapper around frozen full-width mode CDC and existing overlay. Per-pixel material tags and source metadata traverse fixed pipelines. No modification to prior production modules or global ownership.

**Tech Stack:** Native Windows Python/Icarus/PDS, explicit JSON/FDC, core8ns/pixel25ns.

- [x] Snapshot tracked protections and existing unrelated files at d079e75; preserve STATUS other-route additions.
- [x] Write tb/video/tb_display_record_pixels.sv and tb/video/check_record_pixels.py first. Capture the missing-module compile RED before rtl/video/display_record_pixels.sv exists.
- [x] Add full-record CDC/decoder, fixed-latency material tags, output-aligned feedback and conservative local pixel-retirement proof. Create explicit video_record_pixels.json and FDC; add only new run.py/build_pds.py hooks.
- [x] Run normal modes/identity switches, source/mailbox poison, feedback/retirement stalls, asset wait/wrong identity, sample failure, unknown command, coordinated reset, clock ratio and full800×600 independent oracle cases. Detect targeted identity/first-pixel/retirement mutations.
- [x] Run affected overlay/mode_resources/display_scanout and Python/config checks; synthesize component and inspect applicable constraints, warnings and actual estimates.
- [x] Independently review lifecycle and source/oracle integrity; close findings. Update STATUS/README/interfaces/spec/evidence, audit protected/other bytes and exact hooks, commit only the owned payload locally.
