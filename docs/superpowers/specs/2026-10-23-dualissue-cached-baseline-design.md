# Six-stage dual-issue CPU: cached functional baseline

The user authorized this independent CPU design workstream and continued its
execution on 2026-10-23. Work is confined to branch `cpu/dualissue-windows` in
`D:/FPGA/TriHaRiscv-cpu-dualissue-windows`, based on `340bcc2`. The main, CPU
single-issue and SoC integration checkouts remain under their existing tasks.

## Architecture and first implementation

Retain six main stages, RV32IM/CSR, in-order issue and existing commit/exception
control. Reuse the maintained core's two integer execution paths, shared LSU,
shared multiply/divide resources and existing RAW/WAW/structural interlocks.
The second slot remains restricted by the existing legal pairing table;
CSR/divide, interrupt entry and dependencies serialize as already defined.
No second LSU, reorder buffer or predictor redesign is part of this stage.

Keep BTB512/BHT512/RAS4, GShare disabled, both 16KiB two-way/32B-line caches,
private-DDR write-back/write-allocate and uncached shared DDR. The external
instruction, data, cache-maintenance and AXI interfaces remain unchanged.
Expose the existing `DUAL_ISSUE` selection through `triha_cached_core` with
default zero. Add an explicit single/dual selection to its existing native
Cache verification runner and testbench. Default invocations remain single
issue. Verify the elaborated core selection and observe real paired issue;
an argument or source parameter alone is insufficient evidence.

The immediate alternative would be to redesign the register file before
measuring, or to add another memory pipeline. Both mix extra changes into
the comparison. First measure the existing dual path with identical software
and memory timing; then prioritize the actual limiting path and native-area
result. The retained dual register file is currently the generic four-read,
two-write implementation; the single path already uses Pango distributed RAM.
A later native dual register-file candidate should reuse the original
replicated-bank/latest-writer approach and installed Pango primitives, with
independent state-model tests before replacement.

## Verification and decision boundary

1. Existing single/dual smoke, software runtime and 14-instruction WB observer
   probe establish the initial functional baseline.
2. Run unchanged GCC15.2 `-O2` CoreMark on the same ELF in the existing TCM
   model for both modes. Label WB observations separately from architectural
   retirement, and do not call the short result an official or board score.
3. With tests first, parameterize only the cached core wrapper and verification
   inputs. Validate actual elaboration, positive program completion, both WB
   lanes, real paired issue and detection of memory/CRC corruption.
4. Compare same-software cached single/dual CoreMark using identical memory
   policy/timing. Keep full WB/store traces and disclose any stream difference;
   no performance claim can conceal a functional mismatch.
5. Assess register-file and operand/forwarding costs from evidence. Actual
   CPU-only resources and post-route 100MHz remain mandatory later gates.

Single-issue defaults and original source/license files are preserved. This
stage performs no PDS implementation, board programming or serial-port use.
Physical runs must be scheduled so they do not contend with the active SoC
integration work. Results are not merged into that integration branch here.
