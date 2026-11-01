# Direct B Load Forwarding Implementation Plan

> **For agentic workers:** Execute inline with superpowers:executing-plans. Follow TDD and verify each gate before the single physical run.

**Goal:** Preserve the accepted95MHz baseline and target original100MHz without adding a pipeline stage or changing CoreMark cycles.

**Architecture:** Derive from v78. Export the existing E2 memory-selection predicate and its non-memory result separately from each pipe controller. Reuse the existing procedural tag-priority method for a flat B-operand selector with one direct LSU memory input; A operands and all issue/exception/commit controls retain their source.

**Tech Stack:** Existing Windows ModelSim/PDS/GCC15.2 and Python runners; no Cache, DDR, new environment or board programming.

1. [x] Preserve95MHz Git commit541185b, tag, full frozen runtime archive and SHA manifest.
2. [x] Create `tb/cpu/tb_direct_load_forward.v` and `scripts/cpu/check_direct_load_forward.py`. Extract the real parent/candidate B operand expressions and E2 result-selection expressions. Check all tag hit masks, x0, known/unknown tags, LOAD/STORE/MUL/valid priority and X/Z data.
3. [x] Run old semantics and old shared-E2 poisoning test. Require old semantic PASS and poisoning FAIL. Add a true output corruption negative.
4. [x] Reconstruct v78 into `build/cpu/direct-load-forward-v81`. Change only `rtl/cpu/triha_issue.v` and `triha_pipe_ctrl.v`: flat B selector, separate memory predicate/non-memory result outputs. No new state or validity changes.
5. [x] Run component positive/poison/negative tests; ordered and IRQ single/dual; actual recovery and LSU tests. Require the full `-O2` SRAM CoreMark, profile and complete WB/store streams equal v78.
6. [x] Preserve verbatim replay patch/manifest under `docs/verification/cpu/dualissue_direct_load_forward*`; reconstruct independently and verify all source hashes.
7. [x] Run native compile/synthesize/dev_map. Inspect the real B operand selector: direct memory data must reach B operands without the shared E2 result data mux, while selections retain registered-metadata inputs. Unknown/ambiguous graphs HOLD.
8. [x] Only after source, functional and mapping gates pass, run one fresh100MHz PNR with original IO/hold/multicorner and seed1. Final report and all input/output hashes decide acceptance;95MHz archive remains unchanged.
9. [x] Record actual timing, CPU-only area and performance. Keep any rejected candidate as a diagnostic, not a promoted baseline.

Terminal: v81 TIMING_FAIL, Slow/Fast setup -0.951/+2.676ns, hold +0.053/+0.024ns,
MPW +3.655/+4.202ns.357 Slow failures,398 outputs/30 frozen inputs checked.
Actual route mapping PASS and unchanged1221907 CoreMark cycles do not override STA.
Reject v81; retain95MHz v78. See `docs/cpu/DUAL_ISSUE_DIRECT_LOAD_2026-11-01.md`.

Other considered approach: register/elasticize dequeue control. Defer it until its throughput cost is quantified. Existing4.091964/MHz leaves about2.30% extra-cycle budget for the >4/MHz requirement; no blanket load-return stage is authorized by this plan.
