# Direct pending producer comparisons

**Goal:** Remove binary tag ->32bit scoreboard ->32:1 consumer read from the
actual E1 early-MUL -> issue/FIFO critical path, without changing scheduling.
**Architecture:** Normalize each original producer-busy predicate through the
same procedural IF, then compare consumer register IDs against four producer
tags directly. Keep all role, same-packet RAW/WAW, stall, interrupt and cancel
gates. No new stage, state, cycles or relaxed dependency checks.
**Tech stack:** Existing Windows Verilog/ModelSim/PDS/GCC15.2-O2 only.

Pinned mature pipeline source uses producer/consumer ID equality qualified by
operand-used and x0 exclusion (reference source is read only; implementation
remains Verilog). Preserve stronger original four-state indexed semantics:
unknown producer index writes nothing; unknown consumer index reads X even
when the array is zero; x0 never creates a consumer hazard. Busy=X is skipped
by original IF. Producer readiness and same-packet allocation are unchanged.
The global load->MUL/CSR/DIV wait remains an explicit existing condition.
Keep old bitmaps solely as unconsumed simulation observer shadow initially;
native synthesis must remove them from real control cones/resources.

- [x] Independent test uses original conditional indexed-bit writes/reads,
      not direct-match formulas; checks actual A/B acceptance and shadow map.
      Exhaust32 producer/consumer IDs for each source/lane/operand role plus
      randomized valid/roles/alloc/load/mul/early/tag X/Z; all bypass configs.
- [x] Parent baseline and actual forced-accept corruption negative.
- [x] Build-only v18 from v17 replaces six real role/hazard reads with direct
      comparison helper, preserving exact four-state known-index cases.
- [x] Component/packet/active pairing/ordered/IRQ and fresh SRAM/Cache full
      images/streams/cycles/profile; preserve/reconstruct22-source package.
- [x] Independent four-state/control proof and original10ns/no-region review.
- [x] Original100MHz PDS and actual all-corner STA, no production promotion.

Parent and candidate32773 checks in all4 bypass configurations; force-accept
negative detected x1 RAW. Coherent branch6166/negative and original packet
oracle pass; full images/WB/store/performance/profile match v17. Physical
package7de4423f... reviewed and original10ns private PDS launched.

Final native0/verifier2,511outputs; setup-1.110ns (new best), hold/MPW PASS.
CPU8692LUT/4108FF, no new state. New path is low-MUL decode after E1 flops,
not32bit scoreboard read; actual fanout98 early-MUL qualification is next.
