# Shared Video Memory Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans in this authorized checkout. Independent review uses superpowers:requesting-code-review; implementation stays in the parent.

**Goal:** Let capture writes and raw scanout reads share the verified native DDR bridge with explicit service fairness and drain ownership.

**Architecture:** A single-transaction local scheduler latches one selected AXI descriptor, serializes ownership through B or advertised R count, and limits urgent read streaks. A wrapper pairs it with the unchanged AXI/native bridge. Real-core digital tests model CPU-controlled slots and use actual raw commit/release.

**Tech Stack:** Native Python/Icarus/SystemVerilog/PDS, explicit manifests, 125MHz component constraint.

- [x] Inspect bridge/scanout/capture contracts and snapshot c58186d with unrelated path preservation.
- [x] Write `tb/video/tb_video_memory_scheduler.sv`; demonstrate the old write-priority choice violates the bounded read-service assertion and save RED before production code.

```systemverilog
// Both directions remain valid. After a read waits through completed writes,
// it must gain the shared port; accepted descriptors cannot be withdrawn.
if(writes_while_read_waiting>1) $fatal(1,"SHARED_READ_STARVED");
```

- [x] Add `rtl/video/video_memory_scheduler.sv` and `video_shared_ddr.sv`; latch accepted descriptors, drain W/B/R by advertised counts, quota urgent reads, preserve late-held responses and sticky faults. Add explicit `video_shared_ddr` manifest/FDC and `shared_video` runner/build hooks.
- [x] Add `tb/video/models/video_shared_memory_model.sv` and `tb/video/tb_video_shared_memory.sv`; integrate actual ABI2 capture core, raw scanout and native bridge. Verify capture/display overlap, three-slot identity, native readback, output pixels and commit/release reuse boundaries.
- [x] Run targeted protocol/error/fairness mutations and related old ABI2/bridge/raw-display regressions plus Python checks. Synthesize wrapper with 8ns core timing and inspect errors/warnings, without claiming routing or I/O timing.
- [x] Request independent adversarial review; close findings with RED/GREEN. Update STATUS/README/interfaces/spec and verification/evidence, audit all protected/unrelated bytes and limited runner hooks, then commit the explicit batch file list locally.
