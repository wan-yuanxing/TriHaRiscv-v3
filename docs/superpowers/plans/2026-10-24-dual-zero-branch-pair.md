# Zero-source branch pairing diagnostic

Continue the authorized performance and original100MHz closure in the existing
isolated CPU worktree. Production, integration and board state stay unchanged.

The v10/v11 actual critical path repeatedly crosses operand forwarding and
full two-source A branch comparison before B issue permission. Limit A-branch
pairing to BEQ/BNE with at least one architectural x0 source. Compare the
other forwarded operand directly with literal0; retain all original
architectural branch execution/redirect and exception/IRQ/hazard controls.
Other A branches issue alone. No speculative memory effects or new stages.

- [x] Preserve full-base patch/22source manifest from v10 native RF.
- [x] Demonstrate old policy RED and new6166-check GREEN; forced permission
      corruption FAIL. Include actual B-MUL E1/tag and early consumer capture.
- [x] Actual SRAM and I/D Cache-on CoreMark GCC15.2-O2, five iterations;
      CRC PASS. SRAM4.030288/MHz remains strictly above4.
- [x] Compare same loaded images and complete1448448WB/70839store per mode;
      normalize only verified initial absolute cycle and matching started store.
- [x] Ordered exceptions and IRQ self-checks; all inputs/outputs rehashed.
- [x] Reconstruct candidate afresh and prepare original10ns/no-region physical
      package,20min PNR/1500s outer; preflight PASS.
- [x] Independent source/coverage/frozen package review and resolve findings.
- [x] Launch private PDS independently, without modifying integration jobs.
- [ ] Rehash terminal evidence; verify fresh stages, six Slow/Fast STA rows,
      performance slack and CPU-only area; inspect actual worst path.
- [ ] Only admit the same above4 candidate after actual100MHz passes;
      otherwise continue from the measured critical path.
