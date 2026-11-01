# Three-slot face BOX application

The serialized polling step uses the production capture, frame NPU, display and
frame-pool drivers. Capture completion must match the allocation and prove drain;
NPU completion must be published and pass identity/header/full-record CRC checks;
ACK must return hardware to idle before the graph releases its workspace. Each
slot holds its own 640-byte display record. Pixel commit retires the old slot;
only the matching release event and successful ACK make it allocatable again.

Default display mode is BOX. The first 16 already sorted, source-space NPU boxes
are copied directly. The first is primary; point masks and all landmark words
stay zero. No CPU NMS, scaling or avatar availability is implied. AVATAR is not
exposed until a supported real asset path is integrated.

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

Implementation/verification sequence:
1. Add failing host tests using register/DDR callbacks with explicit injected events.
2. Add the whole-frame completion API and the polling state loop.
3. Verify long compute, capture busy, stale identity, full CRC including face 17,
   delayed display release, three-slot exhaustion and I/O failures.
4. Compile/link freestanding RV32IM_Zicsr firmware and require no undefined symbols.

Run `python scripts/soc/run_face_avatar.py`. The runner freezes all inputs and
records hashes and compiler outputs under `build/soc/face_avatar/`. Host injected
events are not proof of physical capture, NPU inference, DDR visibility or pixels.
