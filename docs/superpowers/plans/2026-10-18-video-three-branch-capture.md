# Same-frame raw / preview / YuNet input capture

Accepted design: `../specs/2026-10-18-video-yunet320-design.md`. Baseline
`29655b2`; user authorized continuation. Execute in `video/windows-bringup`.
Use writing-plans, TDD, independent code review and verification before commit.

## Scope and interfaces

Create a new `video_three_branch_capture` core; preserve the accepted two-branch
board target. One request per coordinated reset, with `req_valid/ready`,
`req_slot[1:0]`, `req_frame_id[31:0]`, `req_preprocess_version[31:0]`. Derive all
three bases from common generated configuration. Unknown fields, slot3 or a
version mismatch fail before arming/AXI. Request payload is immutable afterwards.
Add frame slot bases82000000/82200000/82400000, allocation200000 and preview
offset160000 to the JSON and generated RTL/C. Input slots keep the accepted320
allocation. CPU decoder, ownership allocator, fences/MMIO and board entry remain
separate integration work.

Use existing48bit PIX/EOF ingress stream. Arm only after all three descriptors
are accepted. A PIX is accepted atomically by raw packer, preview_downscale and
detect_bilinear; input scaler feeds detect_nchw_dma. No direct physical RX.
Default800x600→400x300 RGB and320x240+40+40 BGR NCHW. Verification geometries are
10..800 by10..600, each axis a multiple10; runtime profile remains the default.
Require all allocations, aligned row strides and final bus beats to fit slots.

`accepted_valid/ready` refers to the first consumed PIX of the armed frame;
hold its slot/frame_id/version until consumed. This corresponds to the selected
frame start after ingress latency, not a new physical SOF timestamp. Success
completion waits for accepted-event consumption, exact input/output geometry,
good EOF with matching independently accumulated raw CRC, and successful
tag/byte-count results from all three writers. `completion_valid/ready` holds
success/code and metadata; failure completion waits for all requested writers
and exposed AXI to drain. Published events cannot be withdrawn by later abort
or online loss. Live sticky error may still inhibit future operation. Source,
FIFO, scales, packers and AXI port require coordinated reset after this shot.

Error code priority:01 offline,09 AXI port,06 writer,0c abort,02 overflow,
03 source,04 PIX,05 EOF,0a scaler/count,07 timeout;08 invalid request. Latch the
first error. Timeout defaults to625000000 cycles (5s at125MHz); an exposed bus
transaction can keep drain pending beyond timeout. `port_drained` is explicit;
error/busy alone must not imply that the bus can be reset or reused.

`axi_write_arbiter3` round-robins three write masters. Select/register an owner
before exposing AW, hold from AW through B and advance pointer only on B
retirement. Route B only to its owner; drain stray unowned B and flag it. Abort
does not gate owner selection, published VALID or data: every already exposed
master AW must eventually receive arbitration and drain. No read/CPU fabric.

## Tasks and verification

1. Add failing config tests for frame-slot constants; run RED, then migrate
   config/generator and generate/check headers. Delegate arbiter+its independent
   TB as a bounded subtask; require missing-module RED then implementation.
2. Add `tb_video_three_branch_capture.sv` with actual byte-addressed three-region
   AXI memory, duplicate/guard/stride checks, independent raw/2x2/bilinear/BGR
   oracle and CRC. Missing core must fail compilation before writing RTL.
3. Implement capture core and wire existing unchanged scalers/writers through
   the arbiter. Cover slotsA/B/C; accepted/completion backpressure; missing/bad
   EOF/CRC; last B stalled independently for every branch; source/overflow,
   abort/offline/timeout during AW/W/B; malformed/unknown PIX; invalid metadata;
   wrong BID/BRESP/stray B; fail drain, first-error retention and reset recovery.
4. Add `three_capture` suite and synth-only `video_three_capture` manifest/FDC,
   preserving8ns clock, existing125MHz/6ns bundle and5s policies. Run one complete
   800x600 source and compare actual input-memory hash to frozen OpenCV identity.
   Run component synthesis, inspect RAM/resource/timing and reject route/bitstream.
5. Request independent spec/code review; fix every material issue test-first.
   Freeze source, then run `python scripts/video/run.py --suite all` once; keep
   per-run hashes and expected-rejection logs separate from positive PASS logs.
6. Publish verification Markdown/JSON, update interface/README/STATUS, stage only
   this batch's Video files and generated Video C header, commit and verify HEAD
   hashes/index/owned scope. No push/merge/Flash/JTAG/UART this component batch.

Commands: `python tb/video/test_config.py`; `python scripts/video/gen_config.py
--check`; `python scripts/video/run.py --suite three_capture`; `python
scripts/video/build_pds.py --target video_three_capture --stage synth`; `python
scripts/video/run.py --suite all`; `git diff --check`.

Local completion proves same-frame geometry and all AXI B retirements under this
component contract. It does not prove CPU cache policy, cross-master visibility,
three-slot scheduling, physical HDMI/FIFO throughput, routed timing or board
acceptance. Do not relabel it as a full SoC INPUT_READY/MMIO implementation.
