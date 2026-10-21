# CPU I/D Cache functional checkpoint

2026-10-21. **Functional RTL and native mapping checkpoint; system/timing admission remains open.** Backup: `cpu-before-id-cache-20261021` (`e4eae68`). The deployed CPU release is unchanged. No COM12, programming, Flash, merge, push, WSL or agent work was used.

Both caches are implemented together: 16KiB each, two ways, 32B lines. D is blocking write-through/no-write-allocate; stores wait for the real lower response. CPU-private DDR is cacheable; shared DDR and other addresses bypass cache. An uncached fetch adapter preserves the same attribute policy for instructions. A fair single-transaction transport joins I/D to the existing 128-bit AXI geometry. Original source provenance and exact hashes are in the dedicated manifests; the original 28 core and nine benchmark files are unchanged.

## Native functional evidence

- Paired components: fills/hits, ways/conflicts, partial stores, held write responses, store-error invalidation, all eight refill-error positions, reset, I flush during refill and held D flush after an owned refill drains.
- Transport: 32B to two128-bit beats, scalar byte strobes, 8B uncached fetch lanes, stable VALID under independent channel backpressure, B/R errors, wrong IDs, early/missing LAST, 4KiB bounds and rejection of MMIO widening. Protocol failures quarantine physical traffic until coordinated reset; ordinary response errors remain recoverable.
- Shared-path joint test: real I/D competition, private and shared accesses, updated shared instructions without caching, maintenance and instruction changes.
- Actual six-stage single-issue CPU: byte/halfword access, replacement, shared memory, FENCE.I modified-code visibility, load/store/fetch errors, MRET and cancellation of the younger store after a faulting load. Cache on/off produced identical 154 WB observations and nine stores. These are directed observations, not full ISA/retirement proof.
- Corrupted-data and CRC negatives returned failure. CRC corruption executed the real benchmark, printed `errors=1`, and failed the software/host check. The six preflight tests reject source drift, address-policy drift and unsafe lists. All 44 existing SoC script tests passed.

One runner attempt failed while serializing a compiler-flag Path object. Its original RUNNING record was preserved and excluded from admission. The writer was fixed and the actual benchmark rerun; no successful result was fabricated from the failed host run. Other missing-feature/compile failures remain in their original build directories.

## Same-program CoreMark comparison

GCC15.2, RV32IM/Zicsr, ILP32, `-O2`, no LTO, 2,000-byte data and five iterations. Complete flags/commands are preserved in native result files. CRCs: `e9f5/e714/1fd7/8e3a`.

| Fixed modeled AXI memory | Cache off | I/D Cache on |
|---|---:|---:|
| Timed cycles | 10,646,732 | 4,699,674 |
| Short RTL CoreMark/MHz | 0.469627675 | 1.063903581 |
| Timed WB observations | 1,448,448 | 1,448,448 |
| Timed stores | 70,839 | 70,839 |
| CPU+cache/transport synthesis LUT | 6,632 | 6,890 |
| CPU+cache/transport FF | 4,096 | 4,326 |
| Distributed-RAM LUT subset, included above | 688 | 688 |
| DRM36K equivalents | 0 | 11 |
| APM | 4 | 4 |
| CoreMark/LUT at nominal100MHz, short RTL | 0.007081238 | 0.015441271 |

Cycles decreased55.858060%; throughput increased126.541926%. This applies only to the documented digital AXI model, including its fixed30-cycle write wait. It is **not a real DDR or board score**, and it must not be compared directly with the deployed SRAM measurement3.036877410/MHz. The short-run duration warning is retained; no official CoreMark claim is made.

Loaded code/data images are exactly identical. Raw ELF files differ only in the non-loaded `.strtab` source-path strings. Independent comparison verifies the identical loaded image and restricts this exception to that section. Timed WB/store traces match line-for-line except the initial absolute cycle sample and its stored value; the checker validates the cycle opcode and ELF `started` symbol before normalizing those values.

The Cache-on synthesis split is CPU6,438LUT/3,563FF/688RAM-LUT/0DRM/4APM and cache/transport452LUT/763FF/11DRM/0APM. Counts come from the same combined synthesis context and exclude serial observation fixtures. They do not substitute for a final routed SoC count. The standalone cache context gives different LUT optimization, and the prior SRAM board core5,933LUT uses a different enclosing boundary; do not attribute the entire difference to new CPU logic.

## Reproduce and continue

Use installed Windows tools:

```powershell
python scripts/cpu/check_cache.py
python scripts/cpu/test_cache_config.py
python scripts/cpu/run_cache.py --test components
python scripts/cpu/run_cache.py --test transport
python scripts/cpu/run_cache.py --test joint
python scripts/cpu/run_cache.py --test cpu
python scripts/cpu/run_cache.py --test cpu --bypass-caches
python scripts/cpu/run_cache.py --test coremark --iterations 5
python scripts/cpu/run_cache.py --test coremark --iterations 5 --bypass-caches
python scripts/cpu/run_cache.py --test coremark --iterations 1 --fault crc
pwsh -NoProfile -File scripts/cpu/run_cache_pds.ps1 -Target cpu-cache
pwsh -NoProfile -File scripts/cpu/run_cache_pds.ps1 -Target cpu-cache -CacheBypass
```

Fault runs must return1. The PDS targets are area-only serial fixtures, not deployable boards or frequency acceptance. Actual Slow/Fast setup, hold and minimum-pulse-width at100MHz are still required, as are local-memory/MMIO routing, real DDR/fabric/CDC binding and board validation. Do not replace the accepted image based on this checkpoint.

The [evidence index](id_cache_stage1.json) binds all selected native results and the independent comparison. Work proceeds under `docs/cpu/id_cache_plan.md`.
