# Real SRAM dual-issue profile (2026-10-23)

This is RTL diagnostic evidence, not physical timing or board acceptance.
Production RTL and integration worktrees were not modified.

The actual 8KiB ROM / 32KiB synchronous SRAM / MMIO system runs the frozen
six-stage dual-issue candidate with GCC15.2 -O2. The nonobserver and both
passive observer runs reproduce 1,253,888 measured cycles, 1,448,448 WB
observations, CRC PASS, and **3.987597 CoreMark/MHz**. At least 3,889 cycles
must be removed to strictly exceed 4 for five iterations. This is a short
estimate, not an official score. WB observations are not architectural minstret.

Loaded ROM/SRAM images match byte-for-byte across all three runs. ELF files
are not identical; do not claim same ELF. The two observer WB/store traces
are byte-identical. Each cycle and pair-rejection partition is asserted.

| Measured cycle class | Count |
|---|---:|
| A instruction issued | 1,048,566 |
| Frontend empty | 82,216 |
| Dependency wait | 123,103 |
| CSR wait | 3 |
| All other priority classes | 0 |

Of issued cycles, 399,882 issue a pair; 282,991 lack a valid B instruction,
96,581 are structurally blocked, and 269,112 fail pairing dependency gates.
Structural classes: 79,704 LSU/LSU; 16,876 branch A; 1 other.
Dependency classes use RAW-first priority: 237,834 A-to-B RAW, 0 remaining
WAW, 31,278 remaining older/resource dependencies. These are observations,
not additive potential saved cycles. False register-role dependencies and
remaining narrow-MUL forwarding opportunities are both zero.

Next investigation: queue occupancy, rejected fetch responses and full-queue
backpressure. Do not remove true RAW checks or pair two LSU operations on a
single LSU. Do not add same-cycle operand chains merely to cross the score
threshold. Any selected RTL change needs targeted tests, identical-program
comparison, and actual original-constraint 100MHz STA.

The original TCM result (1,249,840 / 4.000512) uses different linkage/memory.
The new system has 21,100 fewer pairs but 8,956 fewer frontend-wait and 8,096
fewer dependency-wait cycles. This is descriptive, not isolated memory cost.

## Reproduction and physical admission

```powershell
python scripts/cpu/run_dual_sram.py --test coremark --cpu-snapshot build/cpu/dual-pairing-reconstructed-v1/rtl/cpu --profile
pwsh -NoProfile -File scripts/cpu/run_dual_route.ps1 -PreparedDirectory build/cpu/dual-physical-sram-v1
```

The second command only verifies the prepared package; no PDS starts without
`-Execute`. The execution path has not yet been exercised. It reuses the
existing stage/configuration and six-corner-check timing parsers. It verifies
measured RTL/firmware binding, original FDC bytes, bounded Tcl, records actual
native exits, and snapshots verification helpers. It refuses visible PDS
occupation and existing route output. This guard does not replace checking
whether integration is actively between tool runs.

CPU-only resources remain UNKNOWN; system area is separately labelled.
Even a timing pass returns TIMING_PASS_AREA_PENDING, not full CPU admission.
No PDS or board operation was executed here. The integration thread was still
actively diagnosing its own physical timing; its results do not apply here.

Full run paths, measurements and hashes: [JSON evidence](dualissue_sram_profile.json).
