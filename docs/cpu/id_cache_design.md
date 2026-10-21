# CPU I/D Cache subsystem design

2026-10-21. User approved implementing I-Cache and D-Cache together, with the existing six-stage single-issue CPU. Backup: `cpu-before-id-cache-20261021` at `e4eae68`. Work remains in `D:/FPGA/TriHaRiscv-cpu-windows`, branch `cpu/windows-baseline`; preserve the deployed release and the main worktree's independent Video changes.

## Contract

- RV32IM/CSR, single issue, six main stages, BTB512/BHT512/RAS4, GShare off remain unchanged. Cache wait cycles use existing request/accept/completion stalls; no speculative early-load forwarding.
- I and D each contain 16KiB, two ways, 256 sets, 32-byte lines. Data and tag memories use synchronous read-first storage and explicit Pango block-RAM inference. Valid state must initialize without resetting the data array. Both caches ship in the same subsystem; neither is described as finished merely because its component simulation passes.
- Only `0x80000000..0x81ffffff` is cacheable CPU-private DDR. `0x82000000..0x87ffffff` is uncached shared DDR. ROM/SRAM retain their existing local paths; MMIO remains uncached. No cached alias of a shared region. Cacheability is checked at the subsystem boundary even if the CPU supplies a permissive attribute.
- D is blocking, write-through, no write allocate. Every store completes only after the lower write response; successful hit stores update the resident word with byte enables; failing hit stores invalidate the resident line and return an error. A write miss does not refill or allocate. No dirty state, writeback eviction or posted store completion is admitted.
- Read misses install a line only after all advertised beats complete successfully. Partial/failing refills remain invalid. CPU response tags are preserved. Maintenance commands complete through the normal handshake; reset is coordinated with CPU and fabric, never used to discard accepted live AXI traffic.
- I flush/invalidate must prevent stale refill publication. Validate FENCE.I with modified instructions and pending fetches before claiming instruction synchronization support. D invalidate/flush are clean-cache operations; writeback is an acknowledged no-dirty operation after prior transactions drain.
- Lower DDR boundary is the existing 128-bit AXI contract: 16B-aligned full-width transfers, 32-bit byte addresses, 4-bit IDs, INCR, no 4KiB crossing. A 32B refill occupies two 128-bit beats. A scalar write occupies one aligned beat with its exact byte strobes; no unprotected read-modify-write. Requests remain stable under backpressure; response IDs, errors, beat counts and LAST are checked. Existing Video/native DDR implementation is not copied or changed.

## Reuse and boundaries

Import the fixed reference's matching I/D Cache original files with a separate hash manifest, retaining the original 28 core files unchanged. Product modules and logs use TriHa/CPU names; provenance and licensing stay in manifests. Adapt the D controller's write policy explicitly; retain mature tag matching, replacement/refill and RAM organization where compatible. Do not import its writeback behavior or its platform assumptions silently. An isolated width adapter and I/D arbiter translate the reused cache-side transport to the existing DDR boundary.

New responsibilities are explicit: native cache RAM wrappers; I controller; write-through D controller; shared AXI adaptation/arbitration; CPU/local-memory routing; corresponding component and joint testbenches. Existing proven minimal-system/board targets stay usable until the new subsystem passes admission. Generic source lists never recursively gather all RTL.

## Verification and admission

Write independent CPU-request/memory-scoreboard tests before each behavior change. First watch missing-feature or policy-violation failures, then native ModelSim positives and deliberate corruption negatives. Exercise both I and D in the same joint test with random request/response backpressure, conflicts/replacements, byte writes, delayed writes, read/write errors, uncached shared accesses, maintenance and reset after drain. Verify memory requests and stored data, not only returned hit values.

Then execute real CPU programs through the cache subsystem, including self-modifying code synchronization and exceptions, and compare ordered observations against an uncached memory model. Run unchanged GCC15.2 `-O2`, no-LTO CoreMark under identical program placement and memory latency with caches off/on. Separate SRAM regression, modeled DDR results and actual board results; do not extrapolate an official score from a short RTL run.

Report bare core, cache/adapter and CPU-subsystem resource totals, including RAM subsets. Require actual post-route 100MHz with original I/O, hold and multicorner requirements; tool PASS is insufficient. Full DDR/board integration additionally requires the real current Video DDR version and shared-master completion/visibility checks. No Flash, COM12, merge, push or new toolchain; preserve the deployed CPU while the candidate is unaccepted.
