# Video Probe Reset and IO Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline on the existing Video branch. Prior user authorization covers this component timing work.

**Goal:** Remove direct asynchronous reset release from the scan boundary/DUT and test native IO-register packing without changing product RTL or timing budgets.

**Architecture:** Two independent asynchronous-assert, two-edge synchronous-release chains feed the existing boundary and DUT resets; the core serial output gets the documented syn_useioff port attribute. No serial bit or steady-state cycle is added.

**Tech Stack:** Windows Python, Icarus and PDS 2022.2-SP6.4.

- [x] Freeze all pre-existing dirty/untracked files and copy baseline probe generator/RTL/FDC/manifest to ignored delivery output.
- [x] Add `tb/video/tb_record_probe_reset.sv` and a focused runner test. With the unchanged probe the second-edge release check must fail because reset releases immediately. Preserve the actual failing log.
- [x] Update `scripts/video/gen_record_probe.py` to generate local two-stage reset chains, route each domain's reset locally and add only the documented core_scan_o IO-register attribute. Regenerate the three tracked products.
- [x] Update `scripts/video/run_record_probe.py` with an independent reset-release scoreboard for the broad mapping fixture. Run the new reset TB and compiled negative mutations before full default idle/shadow checks.
- [x] Extend `tb/video/test_record_probe.py` to check synchronizer metadata and unchanged timing budgets/CDC rules. Run ordinary and `python -O` tests plus generator `--check`.
- [x] Run native full probe synthesis and same-policy placement/estimated-interconnect reports from frozen inputs. Verify product RTL hashes remain identical to ab63ea6. Preserve old routes and all negative timing results.
- [x] Record measurements and final route observations in a new verification record/evidence JSON; update spec and append shared STATUS via index projection. Obtain focused independent review, scope the local commit and audit protected files.
