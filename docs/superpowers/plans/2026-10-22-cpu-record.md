# CPU Record Integration Implementation Plan

> Execute inline using superpowers:executing-plans; use requesting-code-review for independent review. The user authorized continuation of this direction. Preserve the shared checkout and external routes.

**Goal:** Add a reusable two-target control decoder and execute captured three-mode display through the frozen RV32 CPU and existing drivers.

**Architecture:** Native CPU → unchanged cpu_native_axil → new video_axil_decode → original capture/display endpoints in video_record_pipeline. One outstanding read and one write independently; exact generated ABI windows, local DECERR for holes. CPU stays an exported diagnostic snapshot.

**Tech Stack:** Windows Python/Icarus/ModelSim/RV32 GCC/PDS, explicit manifests, unchanged ABI/drivers.

### 1. Snapshot and test first
- [x] Freeze HEAD, every protected tracked path including deleted files, other untracked paths and six editable snapshots under build/video/cpu_record_baseline.
- [x] Create tb/soc/tb_video_axil_decode.sv, compile before RTL and retain unknown-module RED. Test W-before-AW/AW-before-W, target binding, aligned window ends, legacy/hole/misaligned DECERR, read/write concurrency and delayed responses. For example `write(32'h20012000,32'h12345678,4'hf)` must hit lane0 once; `read(32'h20010000)` must return 0/DECERR with no endpoint transaction.

### 2. Production decoder
- [x] Add rtl/soc/video_axil_decode.v. In `decode`, use VCAP_MMIO_BASE/VCAP_MMIO_BYTES and VDISP_BASE/VDISP_REGION_BYTES from generated headers. Buffer AW and W independently; enter ISSUE only when both full, hold both independent downstream VALIDs until accepted, retain selected lane through B handshake. Buffer AR independently and retain selected lane through R handshake. Failed address returns local error only.
- [x] Register explicit video_axil_decode project/FDC and a portable `control_decode` suite. Run `python scripts/video/run.py --suite control_decode`; expect all behavioral assertions and held transport monitors PASS. Compile isolated routing/early-W/response-target mutations and require designated assertion failures.

### 3. Real CPU fixture
- [x] Add sw/tests/video_record/main.c, start.S, link.ld; callbacks use volatile full-address loads/stores, maintain the original driver APIs and bound CPU-cycle waits. Link unchanged drivers with RV32I_Zicsr/ILP32 and libgcc. Read an independently generated record/CRC header, never DUT state.
- [x] Add tb/soc/tb_cpu_record_firmware.sv using the existing pipeline source/memory/pixel monitors plus a local ROM/SRAM model and pinned real CPU. Completion requires SRAM signature plus actual two capture, five output seq, one joined retirement and no errors. Add a failed capture and actual negative source/control variants.
- [x] Add scripts/soc/run_cpu_record.py. Reuse frozen Git-object export/copy verification from run_cpu_video.py; snapshot explicit files and tools, recheck before/after every tool. Enforce exact CPU fixture and geometry, signature/ELF binding, current-source hashes and nonzero negatives. Run `python scripts/soc/run_cpu_record.py` and preserve actual command/outputs.

### 4. Verification and delivery
- [x] Run affected cpu_axil and Python runner tests; synthesize only new decoder with 8ns same-clock I/O budgets. Inspect setup/hold/constraints and preserve limitations.
- [x] Obtain independent review, update main spec/interfaces/README/STATUS/verification and machine evidence. Audit CRLF bytes outside hooks and external changes. Stage exact owned paths (STATUS index projection only), commit locally and verify parent/files/evidence/protected states.
