# Three-slot face detection and photo overlay

The serialized polling step uses the production capture, frame NPU, display and
frame-pool drivers. Capture completion must match the allocation and prove drain;
NPU completion must be published and pass identity/header/full-record CRC checks;
ACK must return hardware to idle before the graph releases its workspace. Each
slot holds its own 640-byte display record. Pixel commit retires the old slot;
only the matching release event and successful ACK make it allocatable again.

The detection-only release selects BOX at startup. The photo board profile
starts in RAW; each KEY1 press cycles RAW → BOX → AVATAR → RAW. The display
records use up to 16 sorted rectangles in source coordinates. AVATAR anchors
the supplied transparent [photo](../../../assets/avatars/triha/source.png)
on the centre of the primary face. Its square covers 1.5 times the longer
box edge; the anchor (128,160) in the 256×256 image leaves room for the hair.
A result with no faces leaves the camera pixels unchanged. Five landmarks and
pose rotation are not required. The renderer uses the frame and generation of
the result so an older result cannot decorate a newer picture.

The photo profile expects a seven-segment boot upload: six model segments and
the RGBA image. With the matching photo bitstream already programmed, run
`python scripts/soc/upload_face_model.py --port COM12` (substitute the board's
port). Without `--port`, the same command audits the assets offline.
The legacy six-segment BOX bitstream instead requires `--model-only`. See
[video status](../../../docs/video/STATUS.md) for the current physical build
and board verification status.

Startup is SRAM at `0x10000`; boot ROM must jump there. `main.c` binds MMIO at
`0x20000000`, `0x20011000`, `0x20012000` and volatile reads in shared uncached DDR.
The supervisor must seal/load the model, establish fabric readiness and reset all
owners into a common epoch. NPU hardware exposes IDLE only when healthy, sealed
and unowned. Startup reads IDLE and a nonzero/non-FFFFFFFF session epoch, then
repeats both reads and requires a stable snapshot. `face_avatar_system_epoch` is
telemetry of that read, never a software-written readiness prerequisite.
I/O faults retain ownership and stop work; recovery requires the supervisor's
real coordinated quiescence, not reinitialization over live references. CPU bus
exceptions record mcause/mepc/mtval and park with the frame pool intact.

Run `python scripts/soc/run_face_avatar.py`. The runner freezes all inputs and
records hashes and compiler outputs under `build/soc/face_avatar/`. Host injected
events are not proof of physical capture, NPU inference, DDR visibility or pixels.
