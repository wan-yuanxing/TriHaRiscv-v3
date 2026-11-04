# CPU source admission and native regression

The maintained source is in this main project. `config/cpu_admission.json`
binds exact source bytes and original source/destination mappings. The CPU
implementation was migrated from dual-issue source commit `12733df` on
2026-11-04; the application keeps `DUAL_ISSUE=0`. Each migrated file records
its full immutable `source_commit`; retained helpers/tests keep their older
provenance (`340bcc2` / `febadb3`). Main CSR legality, IALIGN=32 EPC/xRET,
custom cache-maintenance addresses and the minimal control profile remain.
Source-header notices are stored separately in `rtl/cpu/HEADER_NOTICES.json`.

Explicit acquisition, when needed, uses `import_cpu.py --source-root <checkout>`.
It validates every source and destination before writing; `--apply` enables
exclusive creation, and matching existing files are left unchanged. A conflict
never authorizes overwriting a user edit. Simulation uses local admitted files
and the main-tree ISA evidence archive; it does not invoke Git or another
checkout, install tools, or run WSL.

For reviewed integration deltas the importer checks both the immutable base
hash and the reviewed working-tree hash. Header transforms have separate
versioned algorithms; old V1 records keep their original byte output. The
migration record is `docs/cpu/2026-11-04-dual-core-single-issue.md`.

Run from the main project with the installed Python, ModelSim2020.4 and GCC15.2:

```powershell
python scripts/cpu/test_import_cpu.py
python scripts/cpu/test_admission_support.py
python scripts/cpu/run_isa_regression.py --self-test
python scripts/cpu/run_isa_regression.py --suite all
python scripts/cpu/run_isa_regression.py --suite all --minimal-control 1
python scripts/cpu/run_isa_regression.py --suite riscv-tests --filter 'rv32ui-p-add$' --dual-issue 1
python scripts/cpu/run_csr.py
python scripts/cpu/run_document_csr.py --phase green
python scripts/cpu/run_squash.py --delay 32
python scripts/cpu/run_squash.py --delay 64
python scripts/cpu/run_cache_soc.py --test router
python scripts/cpu/run_cache_soc.py --test router --bypass-caches
python scripts/cpu/run_cache_soc.py --test runtime
python scripts/cpu/run_cache_soc.py --test irq
```

These deliberate negatives must return **1** and reach their intended check:

```powershell
python scripts/cpu/run_csr.py --broken
python scripts/cpu/run_squash.py --negative store
python scripts/cpu/run_squash.py --negative mmio
python scripts/cpu/run_squash.py --negative csr
python scripts/cpu/run_squash.py --negative load
python scripts/cpu/run_cache_soc.py --test router --fault data
python scripts/cpu/run_cache_soc.py --test irq --fault irq-return
```

Each invocation creates a unique `build/cpu/` directory, source snapshots,
tool/source/output hashes and `result.json`. The ISA runner reconstructs the
50 riscv-tests and 53 no-C ACT4 ELF/oracle inputs from the SHA-bound archive
already in `docs/verification/cpu/isa_support`. Archived DUT verdicts are never
reused; ModelSim executes all tests again. The historical Sail-generation
metadata remains provenance, and `new_sail_execution` is false.

`config/cpu_sources.f` is the explicit core synthesis/elaboration list.
`cpu_admission.json` separately lists caches, CPU AXI transport, local memory
primitives and test fixtures. `core.sources` and `core.headers` are executable
inputs; the embedded original core manifest's other fields are historical
metadata, not a main-project PDS target.

The old standalone address headers, router, memory fabric and cached SoC top
are isolated under `tb/cpu/fixtures`; their 0x10000 SRAM boot/test ABI is only a
regression fixture. They are not the production main top, address map or MMIO
authority. The five admitted `rtl/soc/triha_*` helpers do not replace existing
`cpu_native_axil.v`, Video modules, shared DDR bridge, arbitration or ownership
logic. `triha_cached_core.v` is an optional DDR-only wrapper, not the final SoC.

The ISA bench checks every cycle that the second issue channel is inactive
in single-issue mode. `--dual-issue 1` affects only that isolated testbench.
The squash runner enables `TRIHA_SIM_CTRL_EXTERNAL` because its bench observes
the simulation-only exit CSR. Normal production builds still reject that CSR.

The focused import excludes historical PDS/board build drivers, debug capture
scripts, CoreMark sources and old SoC generators. `CACHE_ADAPTATIONS.json`
retains its original historical mapping-fixture entry; that unused FPGA scan
fixture is not an admitted production dependency. Current shared-fabric/CDC,
DMA visibility, reset-epoch integration, final CoreMark and physical timing
still require verification in the assembled main target after CPU changes.
The current face board clock contract is 50 MHz compute, 125 MHz DDR/video,
and 40 MHz pixels; standalone CPU targets are separate. No board or
COM operation is part of these regression commands.
