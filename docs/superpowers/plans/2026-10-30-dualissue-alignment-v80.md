# Dual-Issue Branch Alignment Timing Diagnostic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Derive one v78-based CPU candidate that removes the resolved-target low-bit mux from the misaligned-fetch fault path while preserving branch, JAL/JALR, X/Z, exception, and cycle semantics.

**Architecture:** Keep v78 as the parent and create a fresh CPU snapshot under `build/cpu`. Add a one-bit target-alignment result inside `triha_e1_branch`, selected from the already computed conditional/JAL/JALR targets. At the issue boundary, use a four-state case on branch direction: taken uses the precomputed target alignment, not-taken has no alignment fault, and X/Z falls back to the existing `resolved_next[1:0]` expression.

**Tech Stack:** Verilog RTL, ModelSim, Python 3.11, Windows RISC-V GCC 15.2, Pango PDS, existing `run_dual_sram.py` and `prepare_dual_physical.py` runners.

---

### Task 1: Freeze the v78 parent and create the candidate snapshot

**Files:**
- Create: `build/cpu/dual-align-precheck-v80/rtl/cpu/*.v`
- Create: `docs/verification/cpu/dualissue_align_precheck_sources.json`
- Create: `docs/verification/cpu/dualissue_align_precheck.patch`

- [x] **Step 1: Copy the accepted v78 CPU source snapshot.**
  Use the CPU files from `build/cpu/dual-sram/coremark-20261027T075648276873Z/src/rtl/cpu` into a new snapshot directory, preserving only maintained CPU modules.

- [x] **Step 2: Verify parent hashes.**
  Confirm every copied maintained CPU module matches `docs/verification/cpu/dualissue_branch_type_sources.json` candidate hashes before editing.

- [x] **Step 3: Record the new patch and manifest.**
  The manifest must retain the v78 candidate hashes for unchanged modules and record the new `triha_issue.v` hash after the alignment edit. The patch must be reproducible from the v78 candidate source.

### Task 2: Add the minimal alignment precheck

**Files:**
- Modify: `build/cpu/dual-align-precheck-v80/triha_issue.v` during candidate construction
- Test: `tb/cpu/tb_branch_alignment_precheck.v`

- [x] **Step 1: Add a failing directed check for the old late-mux behavior.**
  Cover taken aligned, taken misaligned, not-taken with misaligned target, JAL, JALR bit-0 clearing, and X/Z branch direction. The expected invariant is that only taken targets with low bits nonzero fault; unknown direction follows the old expression.

- [x] **Step 2: Implement the one-bit target alignment output.**
  Add `target_misaligned_o` to `triha_e1_branch`, compute conditional/jump/register low-bit checks from existing target wires, and select by instruction type with the same JAL/JALR priority as `branch_target_r`.

- [x] **Step 3: Replace the issue fault expression.**
  Add `branch_misaligned_case` with explicit `case (branch_taken)` handling. Use the precomputed target bit for `1'b1`, zero for `1'b0`, and the old `taken && (next_pc[1:0] != 0)` expression for default/X/Z.

### Task 3: Run semantic and CPU validation

**Files:**
- Create: `build/cpu/dual-align-precheck-v80/`
- Record: `build/cpu/dual-align-precheck-v80/result.json`

- [x] **Step 1: Run the directed branch-alignment test.**
  Expected: all alignment cases pass, including X/Z fallback and JALR bit 0 clear.

- [x] **Step 2: Run ordered and interrupt/return regressions.**
  Expected: PASS with no trap, recovery, flush, or mtval mismatch.

- [x] **Step 3: Run full SRAM CoreMark with `-O2` and profile.**
  Expected: CRCs remain `e9f5/e714/1fd7/8e3a`; cycle count and WB count remain equal to v78 unless the candidate changes timing semantics.

- [x] **Step 4: Run native compile/synthesize/dev_map checks.**
  Expected: dual issue remains enabled, six stages and predictor configuration remain bound, and no new wide state is introduced.

### Task 4: Prepare and execute one physical PNR

**Files:**
- Create: `build/cpu/dual-align-precheck-io-physical-v80/`
- Create: `docs/cpu/DUAL_ISSUE_ALIGN_PRECHECK_2026-10-30.md`
- Modify: `docs/cpu/DUAL_ISSUE_STATUS.md`

- [x] **Step 1: Freeze a physical package from the validated candidate.**
  Keep the original 10 ns clock, IO, hold, multicorner constraints, seed 1, and existing PNR budget.

- [x] **Step 2: Run exactly one fresh PNR.**
  Do not reuse v78/v79 route databases and do not sweep seeds.

- [x] **Step 3: Accept only actual final timing.**
  Require return code 0, unchanged inputs, Slow/Fast setup and hold pass, both pulse-width checks pass, and performance slack equal to the worst setup and nonnegative.

- [x] **Step 4: Record the result.**
  If timing still fails, record the real worst paths and stop before another unrelated RTL change.


**Execution result:** v80 completed one original-constraint PNR, TIMING_FAIL. Slow setup -1.112ns (v78 -0.175ns), all other setup/hold/MPW checks pass. Candidate rejected as an improved baseline; complete record in `docs/cpu/DUAL_ISSUE_ALIGN_PRECHECK_2026-10-30.md`. No default RTL promotion or next PNR.
