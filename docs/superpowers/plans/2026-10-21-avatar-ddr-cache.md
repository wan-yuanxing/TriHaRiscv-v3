# Avatar DDR Cache Implementation Plan

> Execute inline with superpowers:executing-plans; independent read-only review follows superpowers:requesting-code-review.

**Goal:** Load a checked DDR RGBA material into the immutable fixed-slot pixel cache, preserving its identity until coordinated reset.

**Architecture:** One AXI128 outstanding burst and one beat scratch register feed the frozen cache. CRC is updated per byte; the last texel is withheld until validation. No replacement allocator or extra physical DDR path.

**Tech Stack:** Windows Python/zlib, Icarus, PDS, explicit JSON/FDC, core8ns/pixel25ns.

- [x] Snapshot baseline, protected sources and unrelated work; preserve original STATUS append.
- [x] Write tb/video/tb_avatar_ddr_cache.sv and scripts/video/test_avatar_ddr.py first. Compile without the new module, preserve expected missing-module RED under build/video/avatar_ddr_red.
- [x] Implement rtl/video/avatar_ddr_cache.sv; add fpga/pg2l100h/project/video_avatar_ddr.json and constraints/video_avatar_ddr.fdc. Reuse avatar_texture_cache unchanged. Check full cache data against independent binary fixtures, not DUT CRC logic.
- [x] Run python scripts/video/run.py --suite avatar_ddr: full65536/tail68/page split/clock ratio, descriptor bounds and unknowns, CRC, RESP/RID/LAST/data faults, timeout/online loss, posted AR drain and coordinated reset/reload; poison command payload after handshake and stall result consumption.
- [x] Run targeted isolated last-CRC/byte-order/burst-boundary/response/sealed-identity mutations. Run mode_resources and Python/config regressions; synthesize python scripts/video/build_pds.py --target video_avatar_ddr --stage synth and inspect real constraints/timing/resources.
- [x] Obtain read-only independent review; close findings and reverify current hashes. Update STATUS/README/interfaces/spec and docs/verification/video/avatar_ddr.md/evidence/avatar_ddr.json. Audit old entrypoints outside hooks, exact owned index and other-route bytes; commit only this batch locally.
