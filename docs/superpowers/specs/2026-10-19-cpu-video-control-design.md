# CPU to Video control integration

Baseline `704b076`. User's continued execution authorizes the previously stated
CPU bus integration step. Work remains in `video/windows-bringup`; no worktree
migration, CPU branch edits, merge, push, Flash or board programming.

## Choice and scope

| Approach | Assessment |
|---|---|
| Add a native CPU to AXI-Lite adapter, then test a frozen real CPU | Selected: independently testable control path without interrupting CPU timing work |
| Import the whole current CPU/SoC | CPU branch is actively changing and has no formal fabric; separate integration decision |
| Change the CPU to speak AXI-Lite | Unnecessary CPU pipeline change and coupling |

Add production Verilog `rtl/soc/cpu_native_axil.v`, a same-clock, one-outstanding
adapter restricted to the Video register window `0x20010000..0x2001ffff`. Existing
`video_capture_mmio` and capture/DMA RTL remain unchanged. The adapter is a control
endpoint adapter, not a shared memory fabric, cache, interrupt controller or CDC.

The CPU baseline for diagnostic execution is committed revision `8a2a07c` (full
object ID frozen in fixture config). Export exact selected blobs from the shared
Git object database into each build directory, never read active dirty RTL or
copy CPU sources into the production Video tree. Preserve source/license and
adaptation manifests. A missing object is a clear failure, with no fallback to
another HEAD. These local diagnostic runs require that pinned CPU object; the
portable adapter/Video suites and production synthesis do not depend on it.

## Native interface and transport

All ports use `clk_i/rst_ni` and `*_i/*_o`. Native inputs:
`cpu_addr_i[31:0]`, `cpu_wdata_i[31:0]`, `cpu_re_i`, `cpu_wstrb_i[3:0]`,
`cpu_cacheable_i`, `cpu_req_tag_i[10:0]`, `cpu_invalidate_i`, `cpu_writeback_i`,
`cpu_flush_i`. Outputs: `cpu_rdata_o[31:0]`, `cpu_accept_o`, `cpu_ack_o`,
`cpu_error_o`, `cpu_resp_tag_o[10:0]`.

AXI-Lite ports are `m_axi_{awaddr[31:0],awprot[2:0],awvalid,awready,
wdata[31:0],wstrb[3:0],wvalid,wready,bresp[1:0],bvalid,bready,
araddr[31:0],arprot[2:0],arvalid,arready,rdata[31:0],rresp[1:0],rvalid,rready}`
with normal master directions and `_o/_i` suffixes. PROT is fixed zero.

Native request is read, any write strobe, or any maintenance flag. IDLE advertises
accept (only out of reset). On request AND accept, snapshot every needed field.
No further acceptance until the response pulse has finished. There is no native
response backpressure. Echo all 11 known tag bits on the single registered ACK.
ACK and error reset to zero; error is asserted only together with ACK. Read data
and response tag hold between completions, reset to zero. Write/local-error
responses use zero read data. Do not create combinational AXI-error-to-CPU paths.

Read: hold AR payload/VALID until accepted, then accept one R. Write: independently
hold AW and W payload/VALID until each handshake. Only enable BREADY after both
have been accepted; RREADY only after AR acceptance. Responses cannot complete
the CPU early. AXI response 00 is success; every other code or unknown response
is an error. Read error data is zero. No timeout withdraws a published VALID.

Reject locally with one error ACK and no AXI VALID: outside Video window,
unaligned native address, cacheable request, simultaneous read and write, any
maintenance operation, or unknown required control/address/tag/write payload.
The CPU LSU already aligns byte/half accesses and positions data/strobes; preserve
them exactly, do not shift or silently align illegal external addresses. Idle
payload and read-only unused WDATA do not create requests/errors. An unknown tag
on an otherwise active malformed request returns zero tag with error. Simulation
unknown checking does not imply silicon X detection.

Reset is coordinated with CPU, adapter, endpoint and in-flight capture/DMA. It
clears adapter state and AXI VALID/READY response gates. No local abort/reset API,
retry, allocator, display command or continuous capture is introduced.

## Verification and software

Adapter TB uses independent native/AXI scoreboards and literal requests. Cover
all 2048 tags, read/write ordering, AW-first/W-first/random independent stalls,
held native requests, long channel/response waits, each AXI response code,
all nonzero byte strobes, address boundaries, invalid/cacheable/maintenance/X
rejection and coordinated reset at each outstanding phase. Reject compiled
mutants for tag truncation, early response, repeated AW/W and stale payload.

Real CPU diagnostic compiles a small RV32I/Zicsr freestanding firmware with the
installed GCC, runs the frozen CPU under installed ModelSim, and connects its
native data port through the actual adapter and actual MMIO endpoint to the real
three-branch capture core, DMA arbitration and byte memory at small geometry.
The test ROM/SRAM use the spec's 0/0x10000 ranges but are simulation memories,
not production Boot ROM/SRAM IP. No test exit MMIO is added; completion is an
ordinary test signature in SRAM. IRQ directly connects Video level IRQ to the
CPU external interrupt input for this one-source diagnostic, not a formal PLIC.

Exercise polling success, interrupt/ACK success, failed capture before accepted,
and load/store access fault from real MMIO error responses. Check actual native
tag/accept/ACK transactions, CSR trap cause/PC/value and that IRQ clears only
after software ACK. Require independent expected raw/preview/input memory bytes,
good EOF and all B responses before a successful completion. Run controlled
backpressure and CPU single/dual modes. Clearly separate firmware execution,
portable simulation, component synthesis and physical timing/board conclusions.

All runs are fail-closed, isolated in `build/`, bind exact input/copy/tool hashes,
invalidate old latest PASS at start, and preserve RED/mutant results. The source
freeze/export helper validates safe explicit paths and copied bytes. Installed
PDS primitive model uses its pinned hash, without copying or altering tool files.

## Delivery

Add explicit component synthesis manifest and 8ns clock constraint; no route or
bitstream for this target. Include portable adapter tests in the normal Video
all regression; keep pinned-CPU diagnostic execution as a separate explicit
entry. Run complete Video regression, native component synthesis, real firmware
diagnostic and independent spec/quality review before local commit. Update
Video interface, README, STATUS and a dedicated verification/evidence record.
Preserve all pre-existing main-tree changes; never edit CPU worktree files.

Shared DDR fabric and cross-master write visibility, CPU/NPU ownership, PLIC,
CDC, production memory IP, CPU timing closure, multi-frame rearm and new board
integration remain separate work. This control test cannot publish SoC-wide
INPUT_READY or prove any shared-buffer visibility guarantee.
