# Video capture MMIO implementation plan

> For agentic workers: use superpowers:subagent-driven-development task by task;
> spec and quality review precede final delivery. User already authorized
> continuing in the current Video branch; no worktree/branch migration.

**Goal:** A versioned AXI4-Lite capture endpoint and immutable event mailboxes,
verified with the existing three-branch capture core.

**Architecture:** Software shadow -> one-shot held capture request -> independent
accepted/completion mailboxes -> AXI-Lite polling or masked level IRQ. Preserve
real-time fault and historical results separately. No local core reset.

**Tech stack:** Windows Python, Icarus, PDS synthesis, existing RV32 GCC.

Specification: `../specs/2026-10-19-video-capture-mmio-design.md`, baselinef3c456f.

## 1. ABI generation

- [ ] Add config/video_regs.json with the exact spec table/access/bit definitions.
- [ ] First add tb/video/test_video_regs.py: deterministic RTL/C output, illegal
  base/version/offset/duplicate/type/access/bit definitions and stale-file errors.
  Run `python -m unittest discover -s tb/video -p test_video_regs.py -v`, retaining
  its missing-generator RED in build/video/mmio_red/.
- [ ] Add scripts/video/gen_regs.py using UTF8/byte-exact generation, --root,
  --config and --check; generate rtl/video/include/video_regs.vh and
  sw/include/video_regs.h. Re-run tests and `python scripts/video/gen_regs.py --check`.
- [ ] Compile a build-only C static-assert ABI probe using the installed
  riscv-none-elf-gcc with -march=rv32i -mabi=ilp32 -ffreestanding -c.

## 2. Endpoint and core integration

- [ ] Before RTL, add self-checking tb/video/tb_video_capture_mmio.sv. Retain
  the missing-module RED; implement rtl/video/video_capture_mmio.sv only afterward.
- [ ] Execute all transport, byte, identity, held-event, fault, IRQ/ACK race and
  reset cases specified in the design. Use independent literal expected offsets
  and payloads, not DUT internal register mirrors. Inject failures to prove guards.
- [ ] Add tb/video/tb_video_capture_mmio_core.sv with the real capture core, real
  AXI write arbitration and byte memory. Exercise success, stalled final input B,
  failed write, request slot/version and coordinated reset. Compare data against
  independent expected bytes; no synthetic completion bypasses core validation.
- [ ] Add explicit fpga/pg2l100h/project/video_capture_mmio.json component manifest
  and scripts/video/run.py --suite capture_mmio. Hash all generator/config,
  generated headers, component/core dependencies and tests. Add the suite to all.
- [ ] Add video_capture_mmio to scripts/video/build_pds.py component selectors;
  only synth is legal, using the existing8ns component constraint.

## 3. Review and delivery

- [ ] Run independent spec review, fix material findings test-first, then quality
  review. Bind current source/artifact hashes and retain rejected mutants/failures.
- [ ] Freeze source; run `python scripts/video/run.py --suite all` and
  `python scripts/video/build_pds.py --target video_capture_mmio --stage synth`.
  Verify input maps are current and prior three-board production sources unchanged.
- [ ] Update docs/interfaces/video.md, docs/video/README.md, docs/video/STATUS.md,
  docs/verification/video/capture_mmio.md and evidence/capture_mmio.json with actual
  results and CPU/fabric/visibility/allocator/board limitations.
- [ ] Stage only this batch's explicit owned paths, run git diff --cached --check,
  commit locally, and verify HEAD byte/filter identity plus unrelated preservation.
