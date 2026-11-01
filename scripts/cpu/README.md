# CPU source admission and native regression

The maintained source is in this main project. `config/cpu_admission.json`
binds the exact source bytes, original source/destination mapping, accepted
implementation `febadb3`, and evidence commit `340bcc2`. The only admitted
production changes after that commit are the reviewed IALIGN=32 EPC/xRET fix
in `triha_csr.v` and its `ADAPTATIONS.json` record. Original vendor files and
licenses retain their bytes.

Explicit acquisition, when needed, uses `import_cpu.py --source-root <checkout>`.
It validates every source and destination before writing; `--apply` enables
exclusive creation, and matching existing files are left unchanged. A conflict
never authorizes overwriting a user edit. Simulation uses local admitted files
and the main-tree ISA evidence archive; it does not invoke Git or another
checkout, install tools, or run WSL.

Run from the main project with the installed Python, ModelSim2020.4 and GCC15.2:

```powershell
python scripts/cpu/test_import_cpu.py
python scripts/cpu/test_admission_support.py
python scripts/cpu/run_isa_regression.py --self-test
python scripts/cpu/run_isa_regression.py --suite all
python scripts/cpu/run_csr.py
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

The focused import excludes historical PDS/board build drivers, debug capture
scripts, CoreMark sources and old SoC generators. `CACHE_ADAPTATIONS.json`
retains its original historical mapping-fixture entry; that unused FPGA scan
fixture is not an admitted production dependency. Current shared-fabric/CDC,
DMA visibility, reset-epoch integration, final CoreMark and physical100MHz
timing still require verification in the assembled main target. No board or
COM operation is part of these regression commands.
