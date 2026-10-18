# YuNet 320 BGR NCHW DMA implementation

> Execute in the existing `video/windows-bringup` checkout. Follow the accepted
> `2026-10-18-video-yunet320-design.md`; user authorized continuation. Use TDD.

## Scope and contract

Implement `rtl/video/detect_nchw_dma.sv`, a core-clock component accepting active
RGB888 rows and producing three UINT8 B/G/R planes through `video_write_dma`.
Defaults: WIDTH=320, ACTIVE_HEIGHT=240, PAD_TOP=40, PAD_BOTTOM=40,
ROW_STRIDE=320, PLANE_STRIDE=102400. Parameters permit 1..2048 axes, aligned
strides and non-overlapping planes for directed tail/guard tests. A synchronous
unreset WIDTH×24 row RAM is overwritten before use. Each row is collected once,
then B, G and R row descriptors are processed in sequence; padding sends zero
bytes without reading RAM. No whole-frame buffer or new AXI implementation.

External request: base/tag ready/valid. Input: RGB/row_last ready/valid. Result:
valid/ready, success/code/tag/written_bytes. Errors stop input; abort drains any
published AW/W/B via the existing DMA. First failure code is retained. Failed
requests require coordinated reset before reuse. Successful result can be
consumed and a new request accepted after the caller flushes the source. No
`clear` that could withdraw exposed AXI. Result remains stable under backpressure.
Accepted unknown RGB/row_last or wrong row_last fails; blocked payload is ignored.
Preflight rejects unaligned/unknown/out-of-DDR descriptors before any write.
Local success waits for all 3×storage-height row results and all B responses;
it is not HDMI good EOF, shared-fabric visibility or formal INPUT_READY.

Migrate `config/video_cfg.json` and its generator to the accepted 320 profile:
UINT8/NCHW/BGR, raw scale1/zero0, pads40+40, tensor307200B, plane102400B,
slot327680B, bases0x82800000/0x82850000/0x828A0000. Generate matching RTL/C
constants; these define the common allocation but do not implement CPU decode.
Keep fixed HDMI/preview settings and historical standalone 160/C8 tests.

## Tasks

1. Create `tb/video/tb_detect_nchw_dma.sv` and update `tb/video/test_config.py`.
   Test byte-addressed AXI memory, untouched guards/stride gaps, little-endian
   lane mapping, B/G/R order, top and bottom padding, partial beats, 4KiB splits,
   source/AW/W/B/result stalls. Test final B held (no early success), malformed
   source, abort during collect/AW/W/B, online loss, bus error and wrong BID.
   Save missing-module RED and old-config assertion RED under `build/video/`.
2. Implement the row engine above, then update the generator/config and run
   `python scripts/video/gen_config.py` and `--check`. Run directed simulation
   for W=1,3,16,17,320 with zero/asymmetric/default padding and stride gaps.
3. Connect the real `detect_bilinear` in the TB for 800×600 source tests.
   Dump actual AXI memory after each of the six frozen source frames. Add
   `tb/video/check_nchw_dump.py` to compare the 307200 hardware-written bytes
   with the frozen OpenCV SHA256 identities, without software rearrangement.
4. Add `nchw_dma` to `scripts/video/run.py`, explicit sources/hash inputs and
   synth-only `video_nchw_dma` manifest/FDC/build target (8ns core clock).
   Run directed suite and PDS synthesis. Inspect RAM inference and timing
   estimates. Route/bitstream must still reject component targets.
5. Run `python scripts/video/run.py --suite all`. Request independent review
   using `superpowers:requesting-code-review`; fix findings with failing tests.
   Verify current hashes and publish `docs/verification/video/nchw_dma.md`
   plus JSON evidence; update interfaces/README/STATUS. Explicitly distinguish
   component simulation/synthesis from routing/board/SoC acceptance.
6. Stage only this batch's Video files and generated Video C header. Commit,
   then verify committed hashes, empty index and clean owned scope. Preserve
   AGENTS, CPU and technical-report work. No push/merge/Flash/JTAG/UART.

## Verification commands

```powershell
python tb/video/test_config.py
python scripts/video/gen_config.py --check
python scripts/video/run.py --suite nchw_dma
python scripts/video/build_pds.py --target video_nchw_dma --stage synth
python scripts/video/run.py --suite all
git diff --check
```

Numerical acceptance uses independent coordinate formulas and frozen hashes;
control acceptance checks exposed VALID stability, delayed B retirement,
no writes to guards, and rejection of injected failures. Throughput and physical
HDMI/FIFO sizing remain integration work; the row engine intentionally applies
backpressure and cannot be connected directly to physical RX pins.
