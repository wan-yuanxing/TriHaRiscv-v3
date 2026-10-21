# Video Pipeline Implementation Plan

> **For agentic workers:** Execute inline with superpowers:executing-plans in the authorized checkout; independent review uses superpowers:requesting-code-review only.

**Goal:** Join actual ABI2 capture, shared native memory and display MMIO scanout under the unchanged native C frame owner.

**Architecture:** A wrapper keeps two explicit AXI-Lite ports and a single native DDR owner. A live C/RTL bridge issues real R/W/F, waits for actual events and preserves software ACK boundaries. The test owns an independent native memory oracle and complete output raster checks.

**Tech Stack:** Windows Python/C99/Icarus/PDS, explicit sources,8ns core/25ns pixel.

- [x] Snapshot869a028,451 protected files and31 unrelated paths before new files.
- [x] Write `tb/video/tb_video_pipeline.sv`, `models/video_pipeline_memory.sv` and native C test/runner first; record integration absence RED before the new production wrapper.

```systemverilog
if(capture_awvalid&&capture_awready&&display_lease[capture_slot])
    $fatal(1,"PIPELINE_CAPTURE_OVERWROTE_DISPLAY");
```

- [x] Add `rtl/video/video_pipeline.sv`, explicit JSON/FDC and hooks. Wire existing ABI2/core/display/shared bridge with named ports; keep old production bytes.
- [x] Run full800×600 live C four-frame rotation, third-slot capture while old release awaits ACK, sameRAW mode, all three write oracles and complete raster/lease checks. Run short-height badEOF/native-corruption failure probes; assert conservative C error handling.
- [x] Run targeted ownership/ordering mutations, old capture_v2/display_scanout/shared_video/frame_pool and Python checks. Synthesize combined component and inspect matched scalar/bundle constraints and warnings.
- [x] Independently review live RPC integrity, source/memory/pixel oracle, true completion and software lifetime; close findings with preserved RED/GREEN. Update docs/evidence, verify all hashes/protected/unrelated bytes and exact new hooks, commit the explicit file list locally.
