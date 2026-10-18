# Three-branch HDMI board implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task-by-task.

**Goal:** Capture one physical HDMI frame into raw/preview/YuNet input, read back all three, and display the shared preview through a separate recoverable board target.

**Architecture:** Add video_three_engine around the accepted capture core and DDR bridge. Serial read ownership checks raw/preview CRC, reports the actual input CRC, then transfers ownership permanently to preview_display. Copy only the accepted board shell into a separately named target and preserve the clock/reset/CDC hierarchy.

**Tech Stack:** Windows PowerShell/Python, SystemVerilog/Icarus, PDS2022.2, existing vendor HDMI and DDR IP.

Baseline25482e8; design `../specs/2026-10-18-video-three-board-design.md`.
Existing user authorization selects continuation in the current Video branch;
no worktree switch, CPU migration, Flash, push or merge.

## Task 1: Reader mode and serial engine

Files: `rtl/video/video_frame_crc_reader.sv`, new `rtl/video/video_three_engine.sv`,
`tb/video/tb_video_frame_crc_checksum.sv`, `tb/video/tb_video_three_engine.sv`.

- [x] Write self-checking checksum/engine tests and save expected RED under build/video.
  Check checksum-only result against a separately computed byte CRC, reject unknown data,
  and retain held results. Engine memory must contain actual native writes at generated
  raw/preview/input slotA bases, with independent numerical input and padding assertions.
- [x] Add default-on `CHECK_EXPECTED_CRC`; gate only final expected comparison:
  `if ((^next_crc===1'bx)||(CHECK_EXPECTED_CRC && (~next_crc)!==expected_q)) ...`.
- [x] Implement engine request and accepted/completion consumption once per reset;
  raw/preview checked reader -> input checksum reader -> display. Input read geometry:
  `row_bytes=FRAME_WIDTH*2/5`, `stride=(row_bytes+15)/16*16`,
  `rows=3*(FRAME_HEIGHT*2/5+PAD_TOP+PAD_BOTTOM)`.
- [x] Verify nontrivial small geometry, delayed native port, wrong/corrupt responses,
  source fault, missing EOF, no early AR/commit, reset recovery and live health.
  Keep TIMEOUT_CYCLES default625000000; error cannot reset port or gate exposed VALID.

## Task 2: Board shell and transport

Files: new `fpga/pg2l100h/rtl/video_three_board_top.sv`,
`fpga/pg2l100h/project/video_three_board.json`, `tb/video/tb_video_three_board.sv`;
modify `scripts/video/read_board.py`, its tests, and explicit build/package/program selectors.

- [x] Add failing board/decoder tests first. For type8 decode six little-endian fields:
  `frame_id,preprocess_version,input_pixels,input_written_bytes,input_checked_bytes,input_ddr_crc`.
- [x] Reuse the old board shell with `video_three_engine` instance named `bist`, preserving
  `bist.display`/reset synchronizer hierarchy and original constraints. Add PAD_TOP/BOTTOM
  parameters only for small tests; production defaults40/40. Rotate UART kind0/1/2,
  snapshot672bits with coherent existing CDC, no separate unsynchronized multibit status.
- [x] Add the explicit target to PDS/package/program and regression commands; preserve
  old target selectors and source files. Check three UART packet types, heartbeat,
  KEY0/PLL/core/DDR/source-fault health and reset recovery using the digital DDR model.
- [x] Exercise real800×600 40MHz candidate stream through unforced ingress/FIFO and
  three-branch backpressure, checking no overflow and complete counts; record model limits.

## Task 3: Verification, synthesis and delivery

- [ ] Independent spec then quality review of new behavior; fix material defects test-first.
- [ ] Freeze source and run `python scripts/video/run.py --suite all`; every input hash
  remains current. Run `python scripts/video/build_pds.py --target video_three_board --stage synth`
  then `--stage bitstream`; unchanged8ns/6ns policies, no timing success on a failed report.
- [ ] Package only a current timing-passing bitstream; preserve prior recovery package.
  Scan/program/verify and collect UART only when the artifact qualifies; ask for real
  source/KEY0/visual observation only at the corresponding hardware checkpoint.
- [ ] Publish small verification Markdown/JSON, update interfaces/README/STATUS and stage
  exact owned paths. Commit locally and verify HEAD hashes, clean owned scope, untouched
  concurrent CPU/report/AGENTS work. Record pending physical checks explicitly.

Windows entry commands use existing Python helpers/tool discovery. All logs, RED runs,
simulations, native dumps, mutations, PDS products and temporary audit tools remain build/.
