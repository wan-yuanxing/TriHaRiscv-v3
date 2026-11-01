# Face application boot and timing implementation plan

Goal: boot the admitted B03 assets into real DDR, then run the existing CPU/NPU face-box loop, while retaining timing margin.

User steering (2026-11-01): timing closure is not a LUT-minimization exercise.
Prioritize removal of repeated control/validation, redundant operations and
unnecessary valid-to-wide-data dependencies; split measured critical paths or
replicate local controls when useful. A small FF/LUT increase is acceptable if
it improves physical timing while retaining routing headroom and performance.
Report physical slack, failing endpoints, path depth/fanout and cycle impact
before resource percentages. Keep the CPU configuration unchanged.

Architecture: reuse the fixed-range THB1 loader and the existing write-port ownership switch. Add a small 8N1 receiver and reuse the byte transmitter. UART TX remains available for loader ACK retries after seal; periodic video-only diagnostic packets are omitted from this application target. DDR initialization, packet/image CRC, verified B retirement and model seal gate application admission. The asynchronous UART input passes through two synchronizer registers. RX B24/TX C24 and LVCMOS33 are verified against the board vendor UART example.

Execution stays in the authorized main project, without additional agents or approval checkpoints. Use the writing-plans, systematic-debugging, test-driven-development and verification-before-completion workflows. Do not alter frozen inputs of an active run.

- [x] Add `tb/soc/tb_uart_rx.sv` before the receiver: all byte values, false start, invalid stop, backpressure, overrun, partial-frame reset.
- [x] Implement `rtl/soc/triha_uart_rx.v`; run `python scripts/soc/run_boot_uart.py --loader` with both direct-byte and wire-level packet/ACK paths.
- [x] Connect RX/TX and enable the existing loader in `fpga/pg2l100h/rtl/triha_face_board_top.sv`; update explicit source list and verified pin constraints. Remove constant model seal.
- [x] Add a host uploader that audits frozen assets, sends only legal 256-byte packets and checks exact next-segment/offset ACKs. Test malformed replies, packet CRC, retries and full six-segment sequence before live serial use.
- [x] Finish the actual-CPU zero-input two-frame regression: commit, release, reuse and identical HEAD bytes. `face_system-20261101T042618_814181Z` passes; natural-image boot-to-display regression is a separate pending gate.
- [x] Verify all six model segments through the real loader and shared DDR bridge before CPU admission: `face_system-20261101T050522_122159Z` passes 6,916 packets.
- [x] Finish the independent natural-face two-frame boot-to-display baseline: `face_system-20261101T051349_433163Z`, 47,572,058 cycles, two exact HEADs/CPU records/full pixel frames, release/reuse. Optimized-source revalidation is separate below.
- [x] Integrate the independently tested and synthesized block-RAM boot packet buffer; UART/loader/buffer regression passes, and full six-segment model admission passes in `face_system-20261101T053455_541912Z`.
- [x] Restore conservative rejection of unknown address bits; 2,359,301 legality cases plus two/three-master and bridge fabric tests pass.
- [x] Optimize the measured NPU reset-to-handshake-to-state critical path. Quantizer capacity and registered-response specialization pass component and complete natural-image revalidation. Later synthesis exposes CPU/video paths instead.
- [x] Verify reset-independent quantizer capacity against the previous implementation: 40,000 cycle checks each for one/two arithmetic lanes, unchanged public signals, no extra cycles.
- [x] Replace DDR bridge expected-write storage with synchronous block-RAM banks. Standalone mapping: 3,739 to 874 LUT, 3,369 to 489 FF, +4 DRM; 215 byte/fault scenarios retain identical elapsed cycles.
- [x] Specialize the NPU block service for the actual registered AXI adapter. Keep same-cycle-response support as the default outside this connection. Adapter and block scoreboards retain exact transaction/cycle counts.
- [x] Complete full natural-image boot-to-display revalidation and synthesis of the combined candidate before physical admission. `face_system-20261101T054415_775926Z` passes in 51,716,858 cycles; synthesis is 43,038 LUT. The intermediate `face_system-20261101T053522_639068Z` run was deliberately stopped as superseded, not passed.
- [x] Evaluate and adopt the existing CPU extra-decode stage, retaining all other features and clocks. Production 103-case ISA, squash and cache/IRQ tests pass; new combined system revalidation is `062158`. Isolated 103-case ISA, squash and IRQ regressions pass; synthesis is 43,259 LUT with -2.088 ns core estimate. Single-seed placement is still negative (-4.502 ns final optimizer slack), so do not route this candidate blindly.
- [x] Separate the capture coordinate carry from late job-clear controls. Twenty-case cycle miter and mutation detection pass; candidate adopted byte-for-byte after synthesis benefit was measured.
- [x] Bind display/ingress/telemetry CDC protocols to explicit board-level endpoints and bounded data paths. Verify the actual constraint-check report; added FDC beside report_timing does not override an existing ADF. Never accept zero-wire-delay reports from a placed-only database as physical timing evidence. Main constraints are adopted; corrected placement exports verify both gate sites. Physical setup/hold closure remains pending below.
- [ ] Synthesize the actual ELF and final enabled boot hardware. Proceed to one P&R candidate only when the measured resource/path results justify it; require zero unrouted nets and setup/hold signoff before bitstream acceptance.
- [ ] Update `docs/video/STATUS.md`, packaging instructions and compact source-bound evidence. Board upload/detection remains a separate acceptance step.

The CPU postprocessor uses bounded Q16 pixel-domain NMS with top64 candidates. It does not promise exact Q40/model-domain equivalence for every input. The immediate demonstration needs detected boxes, not landmarks or recognition of identity.

## Follow-up after control-path placement (2026-11-01)

The graph pair pipeline plus parallel gather check is NOT adopted: full placement
setup -1.067 ns is worse than the admitted vector-only -0.924 ns. No route is
launched. Both original targeted paths disappear, but vector terminal-control
and quantizer tag-generation paths remain; positive component synthesis alone
does not qualify adoption.

Continue within the user's authorization to adjust the application architecture:

- [x] Prove that the existing frame MMIO accepts only the three generated layouts:
  all 32 bit mutations of 11 region words per slot must be rejected, and the
  accepted task must remain immutable while held. Check the generated JSON map's
  disjointness and bounds independently.
- [ ] Add an opt-in prevalidated-layout specialization, default OFF in generic
  graph/frame/service modules. Enable it only at `npu_frame_top`, after its exact
  frame-MMIO admission. Reuse the existing checks to omit the redundant graph
  REGION/PAIR sweep; keep epoch/window-change, transport and completion guards.
  This avoids the rejected extra pair pipeline and does not reduce CPU features.
- [ ] Evaluate precomputing vector terminal and quantizer-position metadata during
  existing preparation states, removing carry/comparison feedback without adding
  steady-state cycles. Verify qualified transactions, cancellation and CE holds.
- [ ] Measure the combined resource and physical timing result before adoption;
  retain the vector-only production baseline until all required gates pass.

The selected layout specialization is preferable here to keeping two dynamic
layout validators because the main application already has a fixed, generated
ABI and a single enforcing entry point. Arbitrary direct engine callers retain
full validation by default. No broad timing exception or frequency change is
part of this iteration. The user has already authorized ongoing restructuring
to reach the final face-box application; this is not a new approval checkpoint.

### Isolated implementation and gates

`build/npu/layout_metadata_candidate_20261101` implements the opt-in parameter
through graph/frame/service, enabled only after frame MMIO. It also prepares
`final_chunk` in NEXT and `quant_position` in QPREP. Production is unchanged.

- `layout_budget_red_20261101` fails on the original redundant sweep at state 23;
  `layout_budget_green2_20261101` passes 48 admission/abort/watchdog scenarios.
  Initial invalid-window stimulus was removed from this direct-engine test:
  the prevalidated contract requires a valid window at admission, supplied as
  generated constants by the real service. Mid-flight window changes remain tested.
- `vector_metadata_baseline2_20261101` and `vector_metadata_green_20261101` pass
  8,192 terminal/wrap and 2,048 qualified quantizer/CE/cancel scenarios. The first
  baseline attempt used the wrong opcode field in its stimulus; corrected before
  candidate implementation. Terminal and tag mutations both fail the oracle.
- `layout_generic_green_20261101` retains all 1,024 generic region checks,
  80 cancel cases and 50,000 gather cycle comparisons.
- `vector_metadata_transfers_20261101` passes 66,051 transfer and 8,192 address cases.
- Full isolated boot-to-display regression: `face_system-20261101T082202_226530Z`.
  Combined synthesis: `layout_metadata_probe_20261101`. Both were started with
  frozen inputs; their completion receipts determine the next physical gate.

The combined synthesis completes with 43,501 LUT (65.32%), 45,518 FF, 77.5 DRM,
59 APM and no latches. The -2.032 ns synthesis setup estimate is not physical
signoff. `layout_metadata_place_20261101` is the only placement of this candidate.
The two exact vendor reset protocol tests and flattened startup-reset fanout
audit pass (47 C, 1 P, no core data/CE sinks). 122 common simulation/synthesis
inputs match; ROM/SRAM words are identical despite LF/CRLF file differences.

Mapped hierarchy shows 23,558 LUT in NPU, 3,444 in CPU and 4,676 in DDR IP.
Within NPU, input handling is 5,526 LUT, vector processing 3,353, graph control
2,192, and the two-lane dense MAC array 238 LUT / 16 APM. These are nested counts,
not additive global totals. Further DSP substitution should target demonstrated
arithmetic cones; reducing MAC parallelism alone offers little LUT saving here.

The isolated layout/metadata full boot regression passes with all counters and
51,716,858 cycles identical to the production baseline, zero errors/warnings.
Its placement is nevertheless REJECTED: slow setup -1.245 ns, 1,231 failing
endpoints, TNS -505.909 ns. DDR gate sites and frozen inputs are verified. No route.

### Next measured root cause: operation decode and qualified payload gates

The actual worst path has ten logic levels: layer `op[11]` through the full
opcode comparison and shared core enable (593 loads) to input `shadow_valid`.
Another ten-level path runs from layer state through quantizer-valid gating,
the 256-bit payload mux, TDM lane mux and bias add into the quantizer core.
Both contain about 6.5 ns of estimated routing delay; further seed retries do
not address these long shared control/data chains.

- [x] Establish independent accepted-op/stage-boundary tests: 8,192 qualified
  token/backpressure cases plus 224 invalid high opcode-bit cases. Baseline
  `layer_control_baseline2_20261101` and candidate `layer_control_green_20261101`
  pass; broken enable/payload mutations fail the respective assertions.
- [x] Implement isolated `control_decode_candidate_20261101`: capture exact
  dense/DW flags on the existing START edge; select wide quantizer payload from
  the stable op mode, leaving valid/mask/tag conditions unchanged. No new cycles.
- [x] Measure `control_decode_probe_20261101` synthesis, then one placement only
  if justified. Full boot regression is `face_system-20261101T084921_612281Z`.
- [x] Adopt control_decode after functional identity and physical improvement gates; timing remains open.

## 2026-11-01 控制重构已采用，继续拆分真实关键路径

主工程已采用 control_decode（七个 RTL 的采用前备份及新旧哈希见
`build/npu/control_decode_adoption_20261101/result.json`）。完整模型加载、真实
CPU/NPU 两帧 HEAD/人脸框及逐像素显示通过，51,716,858 周期与基线相同，
ModelSim 零错误/零警告；采用后组件回归通过。整机证据为
`build/soc/face_system-20261101T084921_612281Z`，采用脚本核对编译字节一致。

综合 43,457 LUT（65.25%）、45,519 FF、77.5 DRM、59 APM。seed 4 放置
慢角 setup -0.603 ns / 69 失败端点 / TNS -12.379 ns，相比前生产
-0.924 ns / 380 / -128.017 ns 显著改善，仅少 46 LUT。快角 setup +0.758 ns；
PHY/core 最差 hold slow -0.211 ns、fast -0.255 ns，尚待布线修复。
gate sites、冻结输入与复位协议/网表扇出均验证通过。

未启动完整 route，时序未闭合，无新位流或板测。下一步拆分 graph 的
64 位累加→溢出/尺寸比较→状态控制路径，并评估 input transfer 末尾的
重复加法/比较前移；保持 CPU、125 MHz、额外 0.2 ns setup margin 不变。

## 2026-11-01 关键路径拆分候选：整机通过，启动单次布线

隔离 stage_split 候选将 graph 最终乘加结果先写入原累加寄存器，再做溢出及
尺寸检查，保留数学检查和错误码；在原 input PLAN 提前保存下一偏移及结束标志，
保留 32 位比较语义和传输周期。CPU 配置、时钟约束不变。

512 组乘积/错误检查、5 类新状态退出、4,096 组 burst 规划边界及负对照通过。
输入默认模式 34 场景/46 公开输出逐周期对照通过，信任模式 34 场景也通过。
完整自然图/模型加载/CPU 人脸框/逐像素显示两帧通过：
`build/soc/face_system-20261101T092149_415619Z`，零错误/警告，所有事务计数及
总周期 51,716,858 与基线一致。尺寸检查理论上每帧多 632 个使能周期，但该
受视频帧节奏控制的完整测试总周期未增加，不据此推导通用 FPS。

综合 43,503 LUT / 45,555 FF / 77.5 DRM / 59 APM，相对生产多 46 LUT / 36 FF。
seed 4 放置慢角 setup -0.440 ns（原 -0.603），TNS -8.557 ns（原 -12.379），
89 失败端点（原 69）；快角 setup +0.576 ns。core hold slow +0.023 ns，
全 clock-pair hold slow -0.226 ns / fast -0.270 ns；复位检查通过。
原 graph 乘加检查和 input transfer 完成链退出最差路径，当前首要路径是
gather pad_left 到 k_ci CE，其次量化器 collected 到 dense CE。

`stage_split_place_20261101` gate sites/输入核对通过；现复用该放置结果在
`stage_split_route_20261101` 做单次完整布线和 hold 修复。生产仍为 control_decode，
候选尚未采用。时序尚未闭合，无新位流/板测。

长布线跟进：当前线程已创建每 5 分钟 heartbeat `automation-5`（人脸框工程时序收敛跟进），
检查现有 stage_split_route，正常运行且无可行动变化时保持静默；结束后继续核对
全部物理时序并按实际路径推进。不得重复启动当前运行。生产与候选、仿真与物理
结论仍按上述记录区分；用户暂不接板。工具会话 37156 仍在运行。
