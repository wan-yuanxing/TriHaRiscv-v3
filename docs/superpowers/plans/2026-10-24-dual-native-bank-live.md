# Encode the native RF live bank directly

**Goal:** Remove the actual v20 best route's written-mask -> bank-data gating dependency without adding cycles or storage.

**Architecture:** Reuse the existing two-writer/four-read-replica native RAM topology and live-value table. Encode each register's live source using two mutually exclusive FFs (bank0 live / bank1 live), replacing written/source, still62FF. Reset00, port0 write10, port1 write01; port0 retains same-address priority. Each bank's data is qualified independently, then ORed, avoiding a selected-bank mux followed by a separate late written mask. Data/address hold chains, RAM instances/initialization, write gating and all single/parameter fallback paths remain unchanged.

**Tech stack:** Existing native Windows Verilog/ModelSim/PDS/GCC15.2 -O2.

Scope matches accepted native RF: reset-reachable metadata; no Z write data, pre-first-reset or arbitrary forced metadata equivalence. X write payload is supported. Source/live FFs are always known after reset even when reset or write indices contain X/Z, because the existing procedural IF and collision ordering are retained. Unknown/zero read addresses still default0. State invariant: live0=written&~source and live1=written&source; output OR is equivalent for known onehot enables and0/1/X data.

This is independent of v21 address arithmetic: reconstruct v20 again. First physical experiment retains original10ns/no-region and no I/O attribute, matching the best -0.805ns parent option. Compare actual mapping and final timing; do not combine unmeasured candidates.

Native-stage caveat from independent review: v20 N1537_6[0] already packs the written mask and bank mux together in one LUT4. Therefore this candidate changes metadata encoding, control distribution and fanout; it cannot promise one fewer native LUT level. The current motivation is the actual written flag's indexed selection/high-fanout control path. Only measured post-route timing establishes a benefit.

- [x] Extend independent RF storage oracle with expected bank-ownership state and both live encodings; parent PASS and corruption FAIL before implementation.
- [x] Reconstruct isolated v22 and replace only metadata encoding/read qualification; preserve22-source patch/manifest.
- [x] Ownership/storage/unknown/reset/collision, complete operand and coherent B-MUL, ordered/IRQ, fresh SRAM/Cache-on full streams/profile.
- [x] Independent state-invariant and frozen package review before PDS.
- [ ] Actual bank gating topology, CPU-only area and final six STA checks; >4/MHz same-source mandatory.

Independent source/terminal/package review passed. Original10ns/noRegion/noIO20min PDS launched privately; actual topology and final six STA pending. Same short4.030288 SRAM and3.084289 Cache-on estimates/complete streams/profile preserved.
