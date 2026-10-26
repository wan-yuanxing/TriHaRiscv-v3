# SRAM dual-issue FIFO control-set experiment

**Goal:** Preserve the measured SRAM `-O2` score above 4 CoreMark/MHz and pass the original 10ns post-route checks. No Cache, DDR, board action, production promotion or integration changes.

**Architecture:** Return to the best completed v57 CPU. Change only the synthesis attribute on `triha_fetch_fifo`: `syn_reduce_controlset_size=192`. The ADS guide section 5.17 documents this module-scoped integer attribute. The parent has thirteen FIFO CE control groups of 17–147 registers; 192 is above their maximum. This tests whether moving their enable functions to D logic improves packing and the measured queue update path. It adds no RTL state or cycle and makes no timing guarantee.

**Tools:** Existing native Windows ModelSim, PDS and GCC. Use this existing private worktree, explicit frozen file lists and independent PDS directories.

- [x] Recover v60 evidence into a separate audit record. Preserve its original RUNNING result and report both process exit codes as unknown. Verify frozen inputs, all present outputs, final stage markers and six actual timing checks.
- [x] Run a mapping gate against the parent control-set report. It must reject the thirteen FIFO CE groups smaller than 192. A rejection is a physical-structure RED, not an architectural defect.
- [x] Reconstruct v57 with its checked manifest. Add the one module annotation, save a full-base patch and manifest, and verify that removing the annotation restores all parent CPU bytes exactly.
- [x] Run actual FIFO flush/history, prediction/head alignment and held-branch recovery checks. Run fresh full SRAM CoreMark with profile. Require the same images, WB/store traces, cycle count and profile as v57.
- [x] Prepare and execute one fresh original-constraint, seed1, IO-register PDS run with `-AllowConcurrentPds`. Keep private TEMP and preserve all outputs.
- [x] Verify actual synthesized FIFO control sets rather than assuming the annotation worked. Audit all input/output hashes and compile/synthesize/dev_map/PNR/report_timing markers, native/runner exits, CPU-only resources and six final timing checks. Reject any negative slack.
- [ ] Update status and evidence; commit named files only. If still failing, use the new actual path to choose a structural next step. Do not sweep seeds or claim a timing pass from tool success.

This is a bounded continuation of the user's authorized SRAM/TCM timing work. All broader ISA, board and official CoreMark acceptance remains separate.

Mapping checkpoint: actual FIFO13 CE groups removed; GTP_DFF_CE610 to0, ordinary FIFO FF6 to630. CPU9773LUT/4685FF versus parent9394/4652. Mapping checker strengthened after independent review to reject incomplete/unbound reports; three RED-to-GREEN checks passed. Final rejection audited: setup-.468/+2.667ns,hold+.114/+.103,MPW+3.655/+4.202;native0/runner2,292outputs. Bestv57 remains-.009ns.


## Follow-up: precompute complete FIFO update alternatives (v62)

**Hypothesis:** v57 head-PC-to-pop-to-storage path and v61 ROM-bypass-to-pop-to-storage path both traverse final wide FIFO update logic. Preparing complete values for no removal, A only, B only and A+B removal before the late decision can make dequeue a final selector. This is a structural hypothesis, not an established frequency gain.

- [x] Run original v57 with `tb_fifo_append_decode` arithmetic-cone poisoning: actual parent RED at head/tail data, not a compile error.
- [x] Reconstruct v57 only. In each FIFO entry compute four complete payload alternatives from old count, old slots and accepted input. Keep useful prepared boundaries with documented `syn_keep`, then use the existing two-state procedural removal decisions as final selection. Preserve count, reset, flush, B-only head retention and invalid metadata/data history.
- [x] Require arithmetic-cone isolation GREEN and true data-corruption negative, independent7168-state survivor oracle, prediction alignment both EXTRA modes, recovery, ordered/IRQ and full SRAM profile/traces. No cycle increase or new pipeline stage.
- [x] Only if >4/MHz, freeze and run original10ns seed1 IO-register PDS. Check actual mapped cone separation, resources and six final timing checks; reject negative slack.

v62 mapping checkpoint:1856 actual kept roots across all6 entries; no unknown upstream terminals and no pop0/pop1 support. Native LUT-to-pop corruption copy rejected. CPU10711LUT/4702FF. Fresh full SRAM identical to v57. Private original10ns PDS running; no timing claim.


v62 terminal: native0/runner2,500outputs audited; setup-1.315/+2.386ns,hold+.112/+.074,MPW+3.655/+4.202. Local preparation worked but complete graph worsened; worst reset input→data_accept→dequeue load696→FIFO. Reject. Bestv57 remains-.009ns.

## Follow-up: bounded FIFO capacity (v63)

Historical four-word SRAM measured3.987597/MHz versus six-word4.088695; the current required minimum is>4. Test five words before repeating the old four-word boundary. Return to exactv57 (no v58-v62 edits), expose the original local WORDS=2*DEPTH constant as an overrideable parameter with the same default, and select WORDS5 in both actual decode instances. Keep original two-word reserve, compaction/control/data behavior, pipeline stages and predictor512/512/4. Only the capacity/backpressure schedule changes.

- [x] Add actual decode five-word fill/reserve/drain test; parent RED reports actualcapacity6. EXTRA0/1 positive and actual payload corruption negative pass.
- [x] Run accepted-request alignment EXTRA0/1 and ordered97/IRQpair173.
- [x] Measure fresh -O2 SRAM. Require>4 before PDS; disclose cycle/profile changes and normalize only the verified first cycle-CSR read plus its matching started store when comparing full traces.
- [ ] If admitted, freeze/run original10ns seed1 IO-register package and audit all six final checks, actual CPU-only area, inputs/outputs and native exits.

v63 terminal RTL:1224859cycles4.082102/MHz,+2952cycles(+.241590%). Images identical; only verified first cycleCSR/started store normalized;allother1448447WB/70838store lines identical. No PDS prepared/started. User challenged repeated unproductive versions; complete architecture/method review before further physical admission. See docs/cpu/DUAL_ISSUE_TIMING_REVIEW_2026-10-26.md.
