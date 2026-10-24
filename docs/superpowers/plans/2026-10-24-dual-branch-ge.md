# Shared signed comparison diagnostic

**Goal:** Remove signed BGE's greater-than plus equality reconvergence from
measured operand-forwarding -> branch -> PC critical paths, with no new stage.
**Architecture:** Reuse the existing signed less-than function for BGE by
negating it. Keep all opcode decode, branch targets, ALU and registered branch
state unchanged. Remove the now-unused signed greater-than helper locally.
**Tech stack:** Existing Windows Verilog/ModelSim/PDS/GCC15.2-O2.

v14b's actual general branch path has18levels/setup-1.629ns; v15 separately
shows PC path-1.881ns alongside the zero-branch FIFO failure. The original
BGE expression combines greater_than_signed(a,b) with equality(a,b). For all
known operands GE=!LT. For X/Z operands, arithmetic becomes X unless known
opposite signs decide the result; equality cannot become definitely1 when
any bit is unknown. Thus the original gt|eq and !lt match in four-state RTL.
The pinned mature reference uses the same !alu_lts pattern for BGE.

Keep all original vendor files unchanged. In the build-only diagnostic,
append a separately named licensed execution derivative to the existing CPU
translation unit and instantiate it in the two original execution positions.
This avoids changing the production filelist or tool helpers during diagnosis;
there are still exactly two execution units, no additional hardware instance.
If admitted for production later, split the local module into its own file
with explicit filelist/manifest maintenance. No production promotion now.

- [x] Clocked golden-original execution oracle covers all outputs before/after
      edges, both signed/unsigned branches/JAL/JALR/ALU, boundary and randomized
      operands, X/Z and reset/hold/valid patterns. Parent baseline and negative.
- [x] Create build-only v16 from v14b; append renamed original derivative,
      change exactly BGE expression and remove unused greater function.
- [x] Run golden oracle and negative, zero-pair, ordered/IRQ and full SRAM/
      Cache-on same-image/complete-stream/measurement/profile comparison.
- [x] Preserve22source patch/manifest, reconstruct, review source and original
      10ns/no-region physical binding; no production/vendor source changes.
- [x] Actual original100MHz PDS, all six STA checks/hashes/mapping/CPU-only area.

Actual v16 tool0/verifier2,453output hashes; setup-1.346ns/hold+0.107/+0.049ns,
MPW PASS. New map/layout; still no100MHz admission. Actual worst is now the
wide RB -> zero compare -> FIFO control chain targeted separately by v17.
