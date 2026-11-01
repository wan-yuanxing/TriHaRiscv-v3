# TriHa face application

The production application entry is `triha_face_board_top`. The default board
configuration is the CPU+B03 application with the timing-bounded CPU control
profile (`DEMO_BOX_ONLY=0`, `MINIMAL_CONTROL_CPU=1`): it connects
the existing HDMI input/output pins and DDR3 IP to `triha_face_system`:

```text
HDMI RX -> capture/preprocess -> three-slot frame pool -> CPU frame ABI
        -> B03 graph/heads -> CPU decode + NMS -> CPU BOX record -> HDMI scanout
```

The full path keeps CPU frame allocation, completion publication, display
record submission and slot retirement. The FPGA runs the graph and writes the
real cls/obj/bbox heads. The CPU reads those heads, applies the 0.6 score
threshold, decodes the B03 lookup table, performs a small IoU-0.3 NMS, clips
the restored 800x600 boxes, and submits the existing display record. This
removes the FPGA decoder, sorter, ROI and result-record writer from the board
configuration while preserving the real inference result path.

The current B03 model is bbox-only and has no valid landmark branch, so all
point fields and the landmark-valid flag remain zero. The default full-board
configuration disables hardware post-processing with
`ENABLE_HARDWARE_POST=0`; `DEMO_BOX_ONLY=1` remains an explicit TX-only
bring-up override. Setting `MINIMAL_CONTROL_CPU=0` restores the full CPU
control profile when the board timing budget permits it. The board resource
profile compares only the CPU-selected primary box in the pixel overlay; RAW
pixels, box coordinates and NPU/CPU inference work are unchanged.

The board target uses the DDR IP generated core clock for both compute and
video domains. This is an explicit 125 MHz board contract; it is separate from
the 100 MHz CPU simulation contract and must be closed in PDS before a board
bitstream is claimed.

Use the digital final-application regression while the board target is being
closed:

```powershell
python scripts/soc/run_face_system.py --board-profile --boot-load --fixture build/npu/face_fixture_20261101
```

The regression exercises real CPU firmware, capture/preprocess, the B03 graph,
the shared DDR proxy, CPU result reads, same-frame BOX pixels, three-slot
holding, retirement and reuse. Its result is not a board or timing claim.

The fixture directory contains the independently prepared natural-face image
and reference HEAD data. The board-profile boot regression also sends all six
model segments through the actual loader before admitting the CPU. Without
these options, the runner's preloaded/default configuration is a separate test.

The current board profile keeps `MINIMAL_CONTROL_CPU=1` and `CACHE_ENABLE=0`,
retaining the existing instruction functionality. It disables the board's cache
path, branch prediction and selected bypasses; it must not be described as the
full CPU performance configuration. These are existing board defaults, not new
reductions introduced by the vector/control timing changes. NPU defaults are
`M_LANES=2`, `QUANTIZER_LANES=1` and `TRUSTED_MODEL=1`.
The timing work adds the existing extra decode pipeline stage. Its performance
evidence is the application regression, not a general CPU benchmark.

Board connection is deferred at the user's request. Before deployment, require
a source-bound build with the application ELF, completed routing, and passing
setup, hold, recovery, removal and pulse-width checks at both corners. Placement
estimates and global routing with zero remaining nets are intermediate results.
The latest evidence is in
`docs/verification/npu/2026-11-01-face-timing-progress.json`; no passing final
application bitstream is currently certified there.

For the later board session, use the matching `.sbit` and `.smsk` for volatile
JTAG Program/Verify, reset the board, wait for DDR calibration, and then upload
the model through the explicitly selected USB serial port:

```powershell
# This command audits local assets without opening a serial port.
python scripts/soc/upload_face_model.py
# Replace COMx with the connected board's actual serial port when ready.
python scripts/soc/upload_face_model.py --port COMx
```

The uploader defaults to 115200 baud and records the exact six segment hashes,
packet count and acknowledged cursor. A final loader acknowledgement permits
capture/inference/display admission; it alone does not prove face detection or
HDMI output. The current display shows the CPU-selected primary face box.
External HDMI I/O AC timing and actual DDR/HDMI operation remain board acceptance
items separate from internal STA.
