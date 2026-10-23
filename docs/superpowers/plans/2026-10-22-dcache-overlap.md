# D Cache overlap implementation plan

Design: `../specs/2026-10-22-dcache-overlap-design.md`. User approval already
covers response/request overlap while retaining the load register.

1. Preserve parent `43e0428` and run baseline unit/component checks.
2. Add `tb/cpu/tb_cpu_dcache_overlap.v` and a native runner test selector.
   Exercise a held next request during a successful load response, different
   set/tag/word addresses, registered data/tag stability, byte stores,
   errors, uncached reads and maintenance. Run against unchanged parent RTL
   and record the expected missing-overlap failure.
3. Update only the D Cache successful-load response acceptance/read-address
   selection and sequential request capture. Keep STORE_UPDATE, error,
   uncached and maintenance responses serialized. Bind the new derived hash.
4. Run overlap, write-back, registered-load, transport, joint/FENCE.I, real CPU,
   local SoC and native DDR tests, including corruption negatives. Repair any
   profiling assumption about an IDLE gap; classify each accepted request once.
5. Run exact-window five-iteration native-DDR CoreMark; independently compare
   loaded bytes, complete normalized WB/store observations and event counts.
6. Review source correctness and resource overhead. Build native CPU-only
   area, matching 5000/one-iteration firmware and bounded actual 100MHz route
   only after a demonstrated benefit. No relaxed timing constraints.
7. Independently review all frozen bindings and final setup/hold/MPW/CDC
   reports. Prepare a matching image if admitted, update verification/status
   records, and commit only this CPU work. Keep the current board untouched.

## Completion record (2026-10-23)

Steps 1–7 are complete through final functional, same-payload performance,
native-resource, actual 100MHz route and prepared-image gates. Terminal index:
`docs/verification/cpu/dcache_overlap.json`; narrative and original result paths:
`docs/verification/cpu/dcache_overlap.md`. All 69 CPU and 45 SoC Python tests
pass. The isolated CPU branch/worktree is retained for board validation;
the main worktree and current board image remain unchanged.
