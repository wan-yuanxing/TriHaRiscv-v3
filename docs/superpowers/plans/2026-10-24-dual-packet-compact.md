# Reuse the existing CPU clock-region placement on measured v20

**Goal:** Address actual route-dominated CPU paths while keeping the best measured v20 RTL and all timing budgets.

**Architecture:** No RTL or firmware change. Reuse `prepare_dual_physical.py --compact` and the existing `cpu_minimal_soc_compact.fdc`: CPU PAP_REGION(0,64,150,199) plus existing output-FF packing. The clock/IO/hold constraints remain the same bytes, and no timing exception is added. New full compile/map/place/route, original10ns,20min/1500s. No board, serial, production or integration operations.

**Tech stack:** Existing native Windows PDS; accepted SRAM/Cache-on simulations from v20 are reused by exact source/image hashes.

The best no-attribute v20 has setup-0.805ns; the same-source I/O-packing v20 has-1.198ns. The clean physical comparison for the region option is against that I/O-packing run, because compact includes the same I/O setting. All runs use new mapping/placement. Actual v20/v22 critical routing is73%-82% of datapath delay. Placement locality is a separate diagnostic after v21/v22 did not beat the parent; no frequency benefit is claimed from locality itself.

- [x] Prepare exact v20 source/firmware package with fixed existing physical constraint whitelist; verify original29inputs plus the compact attribute file.
- [x] Independent package/constraint/source review before launch.
- [ ] Inspect actual applied region and mapping resources; confirm full fresh stage success and every frozen input/output hash.
- [ ] Accept only actual Slow/Fast setup/hold/MPW plus consistent performance slack and the bound same-source >4/MHz. Otherwise retain failure and diagnose actual path.

Prepared58c1910a... independently reviewed; private PDS launched21:18:23, wrapper17340. No new RTL simulation needed because the full accepted v20 source/image hashes are exact. Actual region/STA pending.
