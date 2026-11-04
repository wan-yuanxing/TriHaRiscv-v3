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

## 2026-11-02 局部阶段译码候选放置结果

`phase_decode_local` 通过负对照、正向组件回归、自然图真实模型加载整机仿真和综合，
但 seed 4 placement 退化为慢角 setup -0.674 ns / 313 个失败端点 / TNS -85.601 ns，
比生产 `control_decode` 的 -0.603 ns / 69 / -12.379 ns 更差。输入哈希和两个 DDR
gate sites 均通过核对；hold、recovery/removal、minimum pulse width 的结果已记录
在 `build/video/pds/phase_decode_local_place_20261101/placement_analysis/result.json`。
该候选不布线、不采用。此前 `interface_split_register` route 超时且无完整 STA，也不采用。
生产仍为 `control_decode`，下一步只根据真实关键路径继续拆分，保持 CPU、125 MHz 和
额外 0.2 ns setup margin 不变。

## 2026-11-02 graph_pair 放置结果与 stage_split route 结论

针对集成后控制线可能重复的问题，`graph_pair_compat_candidate` 的兼容接口回归、
自然图两帧 CPU/NPU/完整模型加载/逐像素显示仿真和综合均通过；其固定布局入口
保留 `PREVALIDATED_TASK_LAYOUT` 兼容参数，功能结果仍为 51,716,858 周期，输入
未变。综合为 43,686 LUT / 45,570 FF，较生产 `control_decode` 增加控制状态和
寄存器。

seed 4 placement 的完整分析已完成，两个 DDR gate sites、输入哈希和所有时钟对的
setup/hold/recovery/removal/minimum-pulse-width 摘要均已核对：慢角 setup
-1.420 ns / 1,337 个失败端点 / TNS -468.681 ns，快角 setup -0.594 ns；
慢/快 hold -0.227/-0.294 ns，慢/快 recovery -0.317/+0.158 ns，慢/快 removal
+0.433/+0.358 ns，最小脉宽两角均 +0.035 ns。placement-only 报告没有可接受的
max-skew 或 routed STA 签核；最差路径从 `saved_write` 到 `input_path/state[2]`。
相对生产 `control_decode`（-0.603 ns / 69 / -12.379 ns）明显退化，因此候选
淘汰，不启动 route、不采用、不生成位流。

冻结的 `stage_split_route_20261101` 已由 receipt 明确报告失败：PDS route 命令
运行 14,400 秒后超时，最终日志仍显示 41,362 个未布线网络；没有完整 route DB、
全角 routed STA 或位流验收依据。当前没有对应 PDS/Python 活动进程。生产继续为
`control_decode`；保持 CPU 配置、125 MHz 和额外 0.2 ns setup margin，未放宽约束，
也未进行板卡扫描、下载或 HDMI AC 验收。


### Architecture gate added on 2026-11-02

Before another PDS run, resolve the CPU-post semantic gap: the current implementation truncates to 64 candidates and sorts by raw product, while the reference hardware path considers up to 2100 eligible heads and sorts by rounded FP32 score plus candidate id. Add adversarial tests for late strong heads and rounded-score ties, then resume candidate synthesis only after the contract is explicit and passing. The corrected timing contract is 100 MHz CPU/NPU and 125 MHz DDR UI/video; the pre-fix all-125 MHz evidence is historical. The profile uses `M_LANES=2` and `QUANTIZER_LANES=1`; avatar remains disabled on the production face board.


## 2026-11-02 CPU/NPU 100 MHz 与 DDR/video 125 MHz 时钟契约修正

用户明确两个核共用 100 MHz，DDR 用户接口/视频处理使用 125 MHz，像素仍为 40 MHz。
旧板顶把 compute/video 同接 DDR core_clk；BOARD_PROFILE 仿真也把 compute 半周期改为
4 ns。因此既有 -0.603 ns 放置和 51,716,858 周期自然脸通过均属于旧 125 MHz compute
实现，不能外推为 100/125 MHz 的验收，也不能简单给旧 slack 加 2 ns 就宣布通过。

本批工作区修复板顶：厂商生成的独立 GPLL 由 125 MHz reference 产生 100 MHz compute
（125/1*4*2=1000 MHz VCO，再 /10）；CPU/NPU 仅接 compute。DDR UI、采集入口、
capture register、UART/model loader 保持 125 MHz。现有 AXI128/AXI-Lite CDC 复用；
PLL 失锁协调复位应用各域，DDR PHY 保持自身独立启动复位。无整域 asynchronous cut；
十个跨域 FIFO 的每向 Gray bus 均增加 6 ns datapath/max-skew 上界，状态同步器只排除
异域输入路径，各域保留 0.2 ns setup margin。约束实际端点和映射仍待 PDS 复核。

已验证：`build/soc/face_clock_boundary_20261102/result.json` 使用真实厂商 GPLL 数字模型
和真实板顶，测得 10/8 ns；覆盖失锁应用复位、PHY 不被复位，以及三个负对照
（compute 错接 125 MHz、UART 错接 compute、仅一侧复位）均检出。此边界测试将
无关 HDMI/face 数据通路黑盒化，不能替代整机或物理 PLL 验收。
`build/soc/axil_clock_split_20261102/result.json` 三个相位、两复位 epoch、背压和乱序
AW/W 回归通过。契约/物理约束辅助/固件安装单测为 12 passed、7 subtests passed。

已启动全模型 boot + 自然脸两帧整机回归：`build/soc/face_system-20261102T053407_618939Z`；
带真实固件的单次综合：`build/video/pds/20261102T053407_671522Z`。尚无新放置或布线。
旧源码备份及新旧字节哈希在 `build/soc/face_clock_split_20261102/result.json`。
首次诊断 `20261102T051230_933197Z` 因 core_release 约束端点不存在被拒绝，其连接及
整域切断也已修正，不能用于验收；冻结产物保留。NPU control_decode 字节未改，
未采用 trusted fastpath，未改 admission hash。CPU top64/同分排序、FPGA 调度/校验迁移、
avatar 接入仍待处理；不将本批时钟修复当作这些功能已完成。heartbeat 现有状态为 PAUSED，
间隔仍为 30 分钟，已修正其过时提示而保持暂停；当前运行由本聊天直接启动。


## 2026-11-02 时钟拆分整机/综合完成与关键路径复核

此前两项 RUNNING 记录现已完成：`build/soc/face_system-20261102T053407_618939Z/result.json`
为 PASS，真实 CPU/NPU、完整模型启动加载、两帧逐像素显示和释放复用通过，零错误/警告，
48,005,166 个 100 MHz compute 周期。不能与旧 125 MHz 周期数直接比较性能。
`build/video/pds/20261102T053407_671522Z/result.json` 综合 PASS，43,331 LUT / 45,519 FF /
77.5 DRM，冻结输入前后检查通过。仿真/综合共有 127 个冻结文件字节一致；两个 ELF 容器
哈希不同，但提取后的 ROM/SRAM 完全相同，也与实际综合镜像和仿真 hex 的字值一致。

综合慢角报告确认 compute 10 ns、DDR UI/video 8 ns。compute 同域 setup +0.095 ns；
DDR/video 同域 setup -1.352 ns / 1,423 endpoints / TNS -748.539 ns，最差路径从
`face/u_compute_cdc/ddr_release_q[1]` 到 `face/u_video/u_capture/fault_stage_code_reg[0:2]/CE`。
另有 sys→compute reset removal -0.404 ns、DDR PHY hold 最差 -1.564 ns。
这些是综合估算，尚无新放置/布线、全角物理时序、位流或板测验收。

本次检查无活动 PDS/Python/ModelSim 进程；heartbeat 保持 PAUSED，不能把空闲称为持续执行。
下一步先修 CPU 后处理全候选/舍入同分语义，并检查采集复位释放扇出和重复控制；随后依据
证据决定单次放置。图调度/模型校验迁移和 avatar 接入仍未完成。保留 0.2 ns setup margin，
未放宽约束，未进行扫描或下载。详细证据已更新至 face-timing-progress.json 与
`build/soc/face_clock_split_20261102/result.json`。


## 2026-11-02 CPU 全候选后处理修复与采集控制去重

已用旧实现负对照复现三个错误：top64 之前的大量重叠候选使第 65 个以后独立框丢失；
原始乘积不同但 FP32 分数相同的框排序错误；同分 NMS 留下错误候选。
证据为 `build/soc/cpu_post_red2_{suppressed_prefix_65,rounded_tie_order,rounded_tie_nms}_20261102/result.json`。
CPU 实现现按 FP32 分数降序、candidate id 升序，每批保留 64 个键，持续扫描后续批次并
保留 NMS 幸存框，直到全部 2100 heads 耗尽或得到 16 个显示框。64 仅是内存缓冲大小，
不再截断候选语义；无需堆或全候选框数组，最多 33 遍扫描，普通单脸仍一遍。

`build/soc/cpu_post_full_heads_final_20261102/result.json` 的 56 项测试 PASS，含 64/65/128/129
密集候选和 2100 heads；`build/soc/face_avatar/20261102T080140_459674Z/result.json` 应用测试
3903 checks PASS，RV32 编译/链接通过，text 16224、bss 2784 bytes。GCC 静态栈记录显示
已检查的后处理调用链合计 3232 bytes，低于预留 4096 bytes（不是所有运行路径的动态测量）。

综合报告的 -1.352 ns 路径实为 reset -> AXI B -> 多级 READY -> job_clear（271 扇出）
-> 像素 READY/packet_take -> fault_stage_code。现将 packer/downscale/bilinear 的清理提前
到已排空的 IDLE，身份/计数仍在请求被接受时更新，消除新请求握手对本地像素 READY 的
组合依赖；未新增寄存级、时序例外或更改时钟。新增 CASE=30 检查旧实现第 2 帧准备阶段
按预期失败：`build/video/capture_idle_prepare_red_20261102/result.json`；新实现 7 帧通过。
三路采集组件回归 `build/video/regression/20261102T080040_364035Z` PASS，307200 字节
独立 oracle 比对通过。连续采集全尺寸回归 `build/video/regression/20261102T080040_375190Z`
现已整套 PASS，含重用/背压/故障/晚脉冲场景及连续三帧全尺寸采集，累计核对 6,321,600 字节。

新整机回归已启动：`build/soc/face_system-20261102T080716_077928Z`，含真实 CPU/NPU、完整
模型 boot、自然脸两帧逐像素显示，100/125 MHz 不变。组件回归通过后，单次综合也已启动：
`build/video/pds/20261102T080926_876364Z`，使用该整机目录实际 firmware.elf；已核对两处 ELF
字节及实际 ROM/SRAM 字值相同。两项运行完成后检查原长路径、reset removal/DDR PHY hold、
CDC 与物理门限，决定 seed 4 单次放置；本批尚未布线。旧源码与新旧哈希集中在
`build/soc/cpu_post_full_heads_20261102/result.json`。NPU upstream/admission 字节未变。

根据用户继续推进并避免结束后闲置的要求，automation-5 已恢复 ACTIVE、间隔 30 分钟，
提示已要求以最新 active_runs 检查真实进程/结果、完成即核验并继续。图调度/模型校验仍在
FPGA，生产仍 BOX-only，avatar/物理时序/位流交付尚未完成；未进行板卡扫描、下载或 HDMI AC 验收。


## 2026-11-02 16:35 接续：整机/综合通过，进入单次放置

`face_system-20261102T080716_077928Z` 已 PASS：完整模型 boot、真实 CPU/NPU、两帧显示
逐像素及释放复用通过，48,005,166 周期，零错误/警告，与此前同为 100 MHz 的周期数相同。
综合 `20261102T080926_876364Z` PASS，43,258 LUT / 45,519 FF / 77.5 DRM；相较前次减少
73 LUT、FF 不变。127 个共有冻结文件以及仿真/综合 ELF 字节一致，实际 ROM/SRAM 字值
已核对，输入检查通过。

综合慢角 DDR/video setup 从 -1.352 ns / 1,423 endpoints / TNS -748.539 ns 改善为
-0.782 ns / 299 / -131.005 ns；最差路径已转到显示记录校验 `u_raw/N6_m1` 至
`record_reject_valid`。compute setup +0.045 ns。sys→compute removal -0.404 ns 与 DDR
PHY hold 最差 -1.564 ns 仍待物理审查，不能当成时序闭合；快角综合摘要为空。
编译约束 1,011 条、零错误，53 条 critical warnings 全为既有共享管脚 ConstraintEditor-2002，
不替代映射端点/板级 AC 验收。全时钟对综合摘要和哈希保存在
`build/soc/cpu_post_full_heads_20261102/synthesis_analysis.json`。

已启动唯一新运行 `build/video/pds/idle_prepare_100m_place_20261102`，从上述冻结综合 DB
映射并执行 seed 4 / place_only / gplace_times 1；无重新综合、无换 seed、无 route。
使用独立目录及哈希回执，冻结输入未编辑；映射后合并固定 DDR gate site 约束。
启动脚本首次把 result 的 report hash 当作 ADF hash，在启动 PDS 前被断言拦住；已修正为
分别验证报告与固定 DB 哈希，并仅启动这一次映射/放置。
下次接续读取该 receipt/log，完成后核对所有时钟对慢快角时序、max-skew/CDC、实际 gate sites
和输入哈希，再决定后续实现；setup 为负或复位/PHY/CDC 未闭环时不布线。
已将旧整机/综合 RUNNING 改为 PASS，新 active_runs 仅指向本次放置。板卡未扫描/下载。


## 2026-11-02 17:05 接续：放置 setup 全通过，复位/PHY/CDC 审查进行中

`idle_prepare_100m_place_20261102` 已完成唯一 seed 4 放置。全角分析在其
`placement_analysis/result.json`：输入哈希不变，两个 DDR gate sites 确认为
CLMA_357_354/660 FF3。慢角 setup 最差 +0.465 ns（DDR/video），compute +0.606 ns；
快角 setup 最差 +1.341 ns，所有时钟对 setup 均零失败。最小脉宽两角最差 +0.035 ns。

仍有 DDR PHY hold：慢/快最差 -0.322/-0.358 ns；复位 recovery 慢/快
-0.471/-0.219 ns，removal -1.226/-1.219 ns。复位违例从 sys 域 startup/free_release
到 compute CDC 释放链、IRQ 同步器 RS；PDS 映射名含 opit_0_srl，需检查实际器件结构，
不能仅凭 RTL 的 ASYNC_REG/syn_preserve 属性假定同步链保留正确。数据域 setup 为正
不等于整体通过。已请求 max-skew，但通用报告无独立 skew 汇总，尚未作签核。

已启动只读聚焦审查 `build/video/idle_prepare_placed_cdc_20261102`：复制 placed DB 到
独立审查目录，导出真实映射网表，针对十个 compute/video FIFO 双向 60 个 Gray bit
做完整端点查询和 6 ns 有界路径检查，保留原始 DB/报告和约束。检查实际复位连接、
同步器级数与映射后再修正实现；不新增宽泛 false path，不把 PHY hold 掩盖掉。
该审查使用 `build/video/audit_placed_face_cdc_20261102.py`，receipt/result 持续记录真实状态。
旧 placement RUNNING 已改为 COMPLETE，active_runs 仅为此审查；尚未启动布线。


本轮审查入口修正：PDS `gen_netlist` 要求 PNR 阶段，拒绝 placed DB，首次审查
`idle_prepare_placed_cdc_20261102` 标记 FAIL（仅工具导出能力不适用，原 DB 哈希未变）。
已改为 `idle_prepare_placed_cdc_v2_20261102`，用受支持的 `generate_constraint -prim`
导出两个 CDC 模块实际 primitive sites，并运行全部 Gray bit 聚焦放置时序。当前没有导出
功能仿真网表，不能声称已证明同步器实现；后续仍需结合实际原语/级间路径审查。
active_runs 已切换到 v2，未重复综合、放置或启动布线。


## 2026-11-02 17:35 接续：Gray 全位审查完成，修复状态同步器复位归属

聚焦审查 v2 已完成，原始 DB/报告哈希不变。`idle_prepare_placed_cdc_v2_20261102/review.json`
核对十个 FIFO 双向 60 个 Gray bit（20 组），慢快角共 120 条路径全部受到 6 ns
`-datapath_only` 上界约束；最大数据到达 0.925 ns、最小余量 4.976 ns，组内最大派生
到达时间差 0.435 ns。这是全位放置估算，不是独立 PDS MaxSkew 表或 routed 签核。
释放链映射为 FFAPP/opit_0_srl；名称/位置本身不证明级数丢失或结构不安全，未据此改 RTL。

确认并修复一处复位归属问题：`triha_face_system.v` 的 video_irq_sync/compute_fault_sync
原先直接用 rst_ni，绕过本域释放链。分别改用已有 compute_reset_n/video_reset_n，复位期间
不提前采样异域状态，复用已有接口，不增加释放状态机或修改时钟/约束。
`face_status_reset_red_20261102/result.json` 在旧连接分别检出 IRQ/FAULT 逃逸本域复位；
`face_status_reset_green_20261102/result.json` 三个时钟相位、三次复位周期通过，两个恢复旧
连接的负对照均检出。测试编译真实 SoC 状态寄存器 always 块，黑盒化无关数据通路并驱动
本域复位输出/状态源，不能代替完整 SoC 或亚稳态验证。

新整机回归 `build/soc/face_system-20261102T094505_126681Z` 和单次综合
`build/video/pds/20261102T094524_634464Z` 已启动，实际 ELF/ROM/SRAM 字值相同。备份及新旧
哈希在 `build/soc/face_status_reset_fix_20261102/result.json`；NPU 字节未改，无 admission 更新。
台账旧审查已改为 REVIEWED，active_runs 仅为这两项。仍须检查释放链异步输入的
recovery/removal 和 PHY hold；当前不启动布线、不加宽泛 false path、不宣称时序闭合。


## 2026-11-02 18:15 接续：状态复位整机通过，补齐释放链异步输入约束

本域状态复位修复的 `face_system-20261102T094505_126681Z` 已 PASS：完整模型加载、真实
CPU/NPU、两帧逐像素显示，48,005,166 周期，零错误/警告。综合 `20261102T094524_634464Z`
PASS，43,070 LUT / 45,519 FF / 77.5 DRM。127 个共有冻结源码、ELF 及实际 ROM/SRAM 字值
一致；证据 `build/soc/face_status_reset_fix_20261102/completion_verification.json`。两项旧
RUNNING 已改 PASS，当前没有仍在运行的整机仿真。

综合慢角 DDR setup -0.678 ns、compute setup -0.302 ns，仍为综合估算，不宣称改善或闭合。
compute 本域 recovery/removal 为 +3.133/+0.868 ns；sys→compute removal 的四个失败端点
全部是 `u_compute_cdc/cpu_release_q[0:1]/C` 和 `u_control_cdc/s_release[0:1]/C`，IRQ 已离开
原始异域复位。实际综合网表确认这两条链均为两个 GTP_DFF_C，第一级 D=1、Q 仅接第二级
D，第二级才向本域释放复位。该证据不替代后续 FFAPP 映射结构/物理级间时序审查。

新增 `scripts/soc/check_face_reset_constraints.py`，旧 FDC 负对照复现遗漏；仅对上述四个
异步清零 C 输入添加带首尾锚点的精确匹配。未改时钟周期、0.2 ns margin、Gray 6 ns 上界，
未改变其他例外；本域释放扇出、功能复位、级间 D 和 DDR PHY hold 仍受检查。green 回归及
五项负对照（缺失、误切 D、扩大引脚范围、两条链分别退化一级）通过；100/125 MHz AXI-Lite
三个相位/两次复位周期回归、实际厂商 PLL 板顶时钟/复位及其负对照也通过。旧 FDC 备份及
新旧哈希见 `build/soc/face_reset_constraint_fix_20261102/result.json`。NPU upstream 未改。

只改约束，复用已通过的整机仿真，不再重复长仿真。唯一新运行为
`build/video/pds/20261102T101304_076125Z`（单次综合，seed 4/seed_count 1），Python 33668、
PDS 26876 已确认存在。台账 active_runs 仅保留此项。完成后检查 PDS 实际匹配恰为四个 C、
本域 recovery/removal 与数据路径仍受约束、冻结输入一致，再进入单次放置及映射/CDC 审查。
尚未布线，PHY hold、独立 max-skew、位流、avatar、图调度/模型校验迁移继续开放；没有板卡
扫描/下载，也没有外部 HDMI AC 或板测验收。


18:17 工具阶段修正：`20261102T101304_076125Z` 在 FDC 导入阶段 FAIL，未产出新综合网表。
PDS 此时保留 `[1:0]` 总线名，位级 `[0]`/`[1]` 正则匹配为空；这不是时序或 RTL 功能失败。
已保留失败日志并立即从 active_runs 移除。匹配改为精确允许 `(0|1|1:0)`，仍限定两条链的
C 输入；检查器增加 PDS 总线形态并拒绝 `[2]`/`[3:0]`，新的红/绿及五项负对照通过。
当前唯一运行改为 `build/video/pds/20261102T101558_115107Z`（Python 46368、PDS 16040），
实际端点匹配应先得到两个 `[1:0]/C`，综合后对应四个位清零输入。下一步必须核实这些匹配、
本域释放时序覆盖及新综合网表，不能把约束源检查通过直接当作 PDS/物理通过。


## 2026-11-02 18:48 接续：PDS 精确端点导入已验证，串联受检查条件控制的综合/放置

`20261102T101558_115107Z` 已 FAIL，未生成新综合网表；旧 RUNNING 已移至失败记录。
编译数据库副本查询确认实际端点是 `u_compute_cdc/cpu_release_q[1:0]/C` 和
`u_control_cdc/s_release[1:0]/C`。单独正则及字面名称均可匹配，之前含分组选择的正则在
PDS 不匹配。现改为这两个精确字面总线名称，不再依赖分组正则；硬件仍对应四个清零输入。
`face_reset_literal_red/green_20261102` 检查及五项负对照通过。完整生产 FDC/CDC 的 PDS
导入验证也通过，仅保留诊断文件 stop.fdc 的预期停止错误。证据在
`build/video/face_reset_pin_query_20261102/review.json`，原编译数据库与副本哈希一致。
该目录的 max_delay 查询仅用于诊断副本，并在综合前刻意停止，未加入生产约束。

为减少半小时接续间隙，启动唯一受检查条件控制的运行：
`build/video/face_reset_literal_impl_20261102/receipt.json`，主 Python 45820。
当前综合目录 `build/video/pds/20261102T104632_695568Z`、子 Python 43984、PDS 32268。
脚本 `build/video/continue_face_reset_20261102.py` 在综合完成后验证冻结输入只有目标 FDC
变化、资源/固件/实际 ROM SRAM 一致、真实两级释放链、本域 recovery/removal 覆盖不减、
setup 不劣于先前综合；任一检查失败即 STOPPED_REVIEW_REQUIRED，不进入放置。
通过后自动执行唯一 seed 4 放置 `face_reset_literal_place_20261102`，再生成全角放置报告，
无需等待下一次心跳才接续。该脚本不启动布线，物理释放链/Gray/max-skew 与 PHY hold 仍需
审查后决定。台账 active_runs 只列这一串联运行，检查时先读其 receipt，禁止重复启动阶段。
未改 RTL/CPU/NPU/时钟周期/0.2 ns margin；BOX-only、图调度/模型校验迁移、avatar、位流及
外部 HDMI AC/板测仍未闭环。没有板卡扫描或下载。


## 2026-11-02 19:05 工期优化与放置结果

串联运行已完成综合、准入核验、seed 4 单次放置和全角分析，不再运行；active_runs 已清空。
`face_reset_literal_place_20261102/placement_analysis/result.json` 输入不变、DDR gate sites
正确。recovery 慢/快最差 +1.159/+1.353 ns，removal +0.443/+0.367 ns，均零失败；最小脉宽
两角 +0.035 ns。setup 慢角 -0.106 ns/10 端点、快角 +1.259 ns/零失败；hold 慢/快
-0.259/-0.303 ns，均为 DDR PHY 时钟对，仍未闭合。

9 个 DDR/video setup 端点共用显示 descriptor extent 乘加/边界判断至 mailbox CE 链；
另 1 个 compute 端点为 graph check_j 至 state，-0.016 ns。下一轮应围绕这两条控制链做
组件级负对照和简化，不能盲目换 seed。固定头像仍未接入：板顶 ENABLE_AVATAR=0，CPU
present 使用 BOX mode 1；已有通用 renderer 并不代表生产完成。将必要功能与路径修复汇总
后统一整机/综合/放置，避免先对 BOX-only 做长布线再因 avatar 重跑。此顺序调整不取消
avatar 或图/模型职责审查；全面迁移图调度不应在缺乏收益证据时成为交付前置大重构。
已通过且输入未变的组件/整机证据复用，修改部分先跑小回归；PDS 语法先用数据库副本
查询验证。维持 CPU/NPU100、DDR/video125、pixel40 MHz 和额外0.2 ns margin。


### 2026-11-02 RAW descriptor bounded arithmetic implementation

Authorized timing simplification: preserve RAW descriptor acceptance, unknown rejection,
handshake latency and ownership; exploit existing 16-byte alignment and [0x80000000,
0x88000000) window. For H>1 a necessary stride bound is floor((window_beats-row_beats)/(H-1)).
Reject larger strides before using the low bounded stride bits. Compute extent in beats,
with a 24-bit row product and 25-bit base-offset sum; H=1 ignores stride extent and retains
all previously legal aligned strides. Invalid geometry remains rejected. No skipped checks.
- [ ] Characterize current RTL with independent Python byte-address oracle; prove an unsafe
  32-bit truncation fails before production edits; cover exact upper end, overflow and X.
- [ ] Replace only descriptor extent math in rtl/video/raw_display.sv; preserve backup/hashes.
- [ ] Run new oracle and negative controls, then existing RAW display pixel/protocol suite.
- [ ] Combine with required avatar/remaining compute-control work before next full PDS flow.

### 2026-11-02 Fixed avatar integration continuation

Continue the authorized fixed DDR asset design (2026-10-21-avatar-ddr-cache-design.md).
Reuse the existing immutable full texture cache and shared read arbiter; the row cache
currently has no production prefetch connection. Budget full-cache storage against the
155 DRM device before a board build. No change to clocks, margins or CPU profile.

- [ ] CPU record tests must first reproduce the current primary-index-zero defect.
  Choose largest displayable post-NMS rectangle; tie by FP32 score then candidate ID.
  Preserve score-sorted BOX records and no-face behavior.
- [ ] Extend boot-loader tests for an optional seventh, fixed-address avatar segment:
  independent packet/whole-image CRC, exact cursor, retry idempotence, B retirement,
  immutable seal, health revocation and malformed/out-of-order rejection. Preserve the
  six-segment model-only configuration. Add host packet/ACK tests before implementation.
- [ ] Implement only that bounded loader extension in triha_model_loader.v and the
  host transport; never accept arbitrary wire-provided DDR addresses. Production board
  remains model-only until a frozen asset/CRC and cache-load handshake are connected.
- [ ] Add CPU asset metadata/uncropped target rectangle, connect fixed asset boot/cache
  and RAW/BOX/AVATAR mode control, then run component and whole-system pixel oracles.
- [ ] Combine required functionality and targeted timing fixes in one board synthesis,
  seed-4 placement, full-corner review, and only then decide on one route.

RAW continuation result: regression 20261102T111408_635407Z and standalone synthesis
20261102T111538_426628Z both PASS, inputs verified; 1308 LUT / 1954 FF / 4 DRM.
The earlier script-hash failure remains FAIL. No RAW validation process remains active.


## 2026-11-02 19:15 RAW 描述符范围运算简化

依据放置报告的 `u_raw/N6_m1 -> descriptor_invalid -> mailbox CE`，修改
`rtl/video/raw_display.sv` 的描述符范围运算：利用已有 16-byte 对齐和 128 MiB DDR 窗口，
先拒绝必然越界的 stride，再以 AXI beat 为单位使用 24-bit 行乘积、25-bit 地址和。
单行图像仍允许所有原先合法的大 stride；地址窗口、行尾填充、未知值、非法几何、slot、
最小 pitch 检查保留。不增加流水状态或握手延迟。旧源码和新旧哈希保存在
`build/video/raw_descriptor_range_fix_20261102/result.json`，NPU/CPU/约束未修改。

新增独立 Python 无限精度字节地址 oracle 和真实 RAW admission 测试台，旧 RTL 先通过
基线，错误 32-bit 截断负对照能检出。新实现 `raw_descriptor_oracle_green2_20261102`
通过 12 组几何、124,692 组数值输入及四种未知字段；缺少 pitch、误用排他上边界、去除
大 stride 上界三项新实现负对照均检出。范围等价通过不等于物理时序已改善。

首次完整 RAW 回归 `20261102T111124_635311Z` 的全部仿真用例已通过，包括 1,440,000 像素，
但末尾整体输入哈希失败：运行期间补充了范围测试脚本，而 runner 冻结全部视频脚本。
该运行明确记 FAIL，不作为通过证据。现已固定全部输入并启动唯一串联验证
`build/video/raw_descriptor_validation_20261102/receipt.json`（主 Python 24668），当前
完整回归目录 `build/video/regression/20261102T111408_635407Z`、Python11968/VVP45252。
完整回归通过后自动接续一次 standalone raw_display 综合；不会启动整机综合或布线。
活动期间不修改冻结 RTL/脚本。后续先整合固定头像和剩余控制链修复，再统一长验收。


## 2026-11-02 20:00 固定头像接入：组件闭环，整机未验收

RAW 范围修复的完整回归 `20261102T111408_635407Z` 和组件综合
`20261102T111538_426628Z` 已 PASS，输入已核验，1308 LUT / 1954 FF / 4 DRM。
其 RUNNING 已清除；旧脚本哈希失败仍保留 FAIL。

CPU 原 primary_index=0 已用红测试复现，改为在最多16个可显示 NMS 框中选择面积最大者，
同面积按 FP32 分数、候选编号决胜，原 BOX 排序不变。新增启动期不可变素材配置、
256x256 素材锚点/覆盖系数生成未裁剪目标方形（仅显示覆盖裁剪）、无脸清空素材字段，
以及 RAW/BOX/AVATAR 请求和复用现有池协议的同帧 mode-only 原子提交。默认现在为 RAW。
`build/soc/face_avatar/20261102T115452_649918Z` 4007 检查及 RV32 链接 PASS；五项
真实源码变异（主脸0、错误裁剪、素材代次错误、强制BOX、漏同帧切换）均被测试检出，
见 `face_avatar_integration_20261102/mutations2/result.json`。首次变异脚本因缩进警告失败，
修正后的独立 mutations2 才是负对照证据。旧整机/固件证据不适用于当前软件字节。

`triha_model_loader.v` 增加可选第七段固定素材区，AVATAR_BYTES=0 保留六段加载行为。
开启时必须整段 CRC 和最终 DDR B 都完成才封存；不能从 UART 指定地址。红测试证明旧
实现过早封存。`boot_uart-20261102T115133_989142Z` 含六/七段直连与实际串行检查、
完整262144字节七段检查（318536项）、CRC失败/越界偏移/幂等重传/背压/故障排空均 PASS。
主机传输七项测试 PASS。板顶目前仍未开启第七段，因此不能称生产头像已接通。

已生成可重现的原创几何卡通头像 `assets/avatars/triha`，提供SVG/PNG预览、RGBA原始字节
及锚点/覆盖参数/CRC/SHA清单。生成器 `scripts/video/gen_fixed_avatar.py --check` PASS。
实际素材 SHA256 c4897906fe809c679acea3b92ba8b4ac3ce25b62b48a67fcd863fc12536c485b。
接着用现有完整缓存读取全部实际 texel、第二像素时钟比及错误CRC做验证。完整缓存复用
已有64 DRM方案；板级总资源及真实路径仍须统一综合确认。未改CPU配置、NPU upstream、
100/125/40MHz、0.2ns margin和约束，不进行板卡扫描/下载。

后续：把该素材CRC/身份绑定到启动加载和固件，接通 boot seal→cache load 与独立模式键，
核对 CPU 记录/RTL guard/全像素参考，再合并板级实现。图调度/校验职责、PHY hold、
路由CDC/max-skew及最终位流尚未闭环，不启动旧BOX-only长布线。


### 20:14 头像真实字节缓存通过，启动系统集成运行

`build/video/avatar_ddr/20261102T120436_276365Z` 已 PASS 并移出活动运行：实际素材
65536 texel 在两个像素时钟比下各比较65538次，错误CRC拒绝 code5。其 Python/VVP 已退出。
生成器同时输出 `sw/include/avatar_preset.h` 与 `rtl/soc/include/avatar_preset.vh`；
两者与实际262144字节素材绑定 CRC32=6112fc3c、身份1/1、基址0x82600000。

SoC 新增默认关闭的 BOOT_AVATAR：开启时第七段完整CRC和最终B完成后，仅握手一次，
自动提交固定描述符到原头像DDR读取/CRC缓存。没有另建DDR通路。主固件读取显示模式
能力，只有平台支持AVATAR才配置同一生成清单；不把配置当成实际cache-ready。
新固件组件 `face_avatar/20261102T120939_836557Z` 4007检查及链接PASS，
`face_avatar_status_reset_20261102` 原始状态复位及两个变异PASS。

第一次系统启动探针 `face_system-20261102T121244_958310Z` 在0时刻因测试台遗留的
六段数量断言FAIL，已明确记录；仅将AVATAR_BOOT下预期段数改为7后重启一次。
当前唯一运行 `build/soc/face_system-20261102T121350_305980Z`，Python3320、ModelSim20872。
命令 `python scripts/soc/run_face_system.py --board-profile --boot-only --avatar-boot`。
它核对实际CPU、全部模型加素材UART包/DDR写后读回、自动cache-load、完整CRC、像素域封存；
不代表完成推理/显示，更不代表物理时序。实际板顶仍未开启BOOT_AVATAR，模式键尚待接入。
以台账active_runs为准，运行期间不改冻结RTL/固件/脚本/素材。完成后立即核验接续。


20:17 接续修正：`face_system-20261102T121350_305980Z` 已FAIL并结束。六个真实模型段
均完成，在第七段首字节遇到旧测试台将素材区当作采集 guard gap 的断言。只为
AVATAR_BOOT 且 boot_owner、未封存时开放精确0x82600000..0x8263ffff窗口，同时增加
逐字节重复检测、262144字节总数和封存后禁写检查；其他采集guard不变。
当前唯一活动运行替换为 `build/soc/face_system-20261102T121616_403404Z`，Python31548、
ModelSim24236，已确认实际进程存在。旧3320/20872不再运行。继续冻结当前输入直到结果。


### 2026-11-02 头像、模式键板级接入及下一轮验收

旧启动运行 `build/soc/face_system-20261102T121616_403404Z` 已结束，结果
PASS_BOOT_ONLY：7段、7940包、7394379周期，真实CPU准入、全部模型和262144字节
素材经DDR写后读回、完整缓存CRC/身份及像素域ready通过；不是三模式完整显示证据。
旧 RUNNING 文字是历史记录，当前进程以台账 active_runs / receipt.json 为准。

板顶现已接入固定头像全缓存及官方KEY1/C23，CPU读取新增只读MODE_REQUEST(0x84)
并保持唯一显示所有者，默认RAW，按键依次切换BOX/AVATAR；新增能力位16，记录ABI不变。
预览采集与显示器选择解耦，板顶明确关闭未用preview，未削减CPU/NPU配置。
模式键真实去抖/MMIO、长按/抖动/reset/stall及三个负对照PASS
(`face_mode_key-20261102T122623_604578Z`)；应用4007检查、原始状态复位回归及厂商PLL
100/125/40 MHz连线检查通过。上传器默认7段，--model-only明确用于旧6段位流；
8项主机测试与只读资产审计PASS，未访问串口/板卡。

PDS编译数据库确认模式键必须使用 `g_mode_key.u_key`，旧斜线层级不匹配。
补齐头像ready第一级输入豁免，保持第二级正常计时，两个身份捕获目标保留6ns
max_delay。所有生产约束端点重放通过，查询脚本以专门不存在的STOP端点停止综合；
诊断退出非零是预期停止，未计作综合或物理通过。原始证据
`build/video/face_avatar_cdc_query_20261102/review.json`，不增加宽泛false path。

紧凑显示回归19项MMIO/CDC/像素检查通过后，完整显示组合测试因测试台旧层级
`dut.u_mmio`无法绑定而停止；只修正脚本映射到 `dut.g_full_mmio.u_mmio`，
重新执行受影响的3个显示场景，旧19项须核对所有未变化输入后才复用。
输入备份、新旧SHA见 `build/soc/face_mode_integration_20261102/after_hashes.json`。

下一步用带守卫的串联运行完成实际自然脸、7段完整加载、真实CPU/NPU、RAW/BOX/AVATAR
逐像素核对，通过后自动使用同一次仿真的firmware.elf做单次综合，并比较共享RTL及
ROM/SRAM实际字；资源/时序人工审阅前不布局布线。三个显示模式使用独立Python数学
oracle，测试台加速去抖不改变生产125MHz/20ms。内部物理闭合、图调度/模型校验职责、
外部HDMI AC及板测仍未闭环。NPU仍为control_decode，准入哈希未变。


接续：紧凑显示兼容性已 PASS，共22场景（19项未变化输入复用，3个完整显示场景重跑）。
证据 `build/soc/face_compact_compat_20261102/result.json`。已启动唯一串联协调器
`build/video/face_avatar_validation_20261102/receipt.json`（Python42028）；当前SYSTEM阶段
`build/soc/face_system-20261102T125839_514465Z`，Python17952 / ModelSim20468，实际进程已确认。
整机通过后自动接续一次使用同一ELF的综合；失败立即停止并写真实状态，不轮换seed，
不自动放置/布线。冻结输入至协调器结束；此处仍未宣称整机三模式或物理时序通过。


### 2026-11-02 21:31 三模式整机及综合通过，单次放置准入

`face_system-20261102T125839_514465Z` 已 PASS，7段完整模型/素材、真实CPU/NPU、
自然脸两帧、RAW/BOX/AVATAR逐像素、模式独立提交与槽释放复用均通过：
49663086周期，modes=111，Errors/Warnings=0。旧协调器与ModelSim已退出，
active_runs没有残留RUNNING。综合 `build/video/pds/20261102T131939_550869Z` 已PASS，
51262 LUT (76.97%)、55283 FF (41.50%)、141.5 DRM (91.29%)、64 APM，零latch。

仿真/综合130个共享输入、同一firmware.elf、ROM/SRAM逐字一致，源码快照及原始文件
均未变化；实际100/125/40MHz时钟、计算/视频额外0.2ns setup、窄复位C引脚、模式键
官方来源及约束端点检查通过。证据 `build/video/face_avatar_synthesis_review_20261102/result.json`。
像素/RX/config/free域的物理验收仍须至少保留0.2ns setup余量，不能仅看非负slack。

综合估计setup slow -0.461ns/135端点、hold -1.748ns/371端点；recovery/removal/pulse
零违例。setup首路径为显示link.base到link.state CE；计算域首路径为释放复位到NPU
done_detail。综合无fast表，不替代真实放置/布线。DRM余量13.5块，路由可行性仍未证实。
当前准入一次已有综合DB的seed4放置，并自动接续全角时序/gate sites分析；无重新综合、
无seed轮换、不自动布线。图调度/部分模型校验仍在FPGA；外部HDMI AC和板测未完成。


### 2026-11-02 22:06 放置setup全通过，准入一次DDR hold修复布线

`build/video/pds/face_avatar_place_20261102` 已完成并自动分析，原Python/PDS退出，
active_runs已清空。慢/快setup最差+0.379/+1.223ns，零失败；计算域慢setup+0.699ns，
视频域+0.379ns，像素域+1.094ns。recovery +1.021/+1.215、removal +0.433/+0.358、
pulse +0.035/+0.035均零失败。输入、两个实际DDR gate sites均已核实。
实际映射51244 LUT/55181 FF/141.5 DRM，不把综合资源当实际映射。

hold慢角-0.349ns/115端点，快角-0.416ns/200端点，仅三个DDR PHY时钟对；报告列出的
97条违例路径起止均在厂商DDR PHY内。对应时钟对慢setup下界5.368/2.918/2.303ns，
扣除快角hold缺口仍为4.952/2.553/2.137ns。因此选择工具物理延时修复，避免无依据
修改CPU/NPU或降低频率。23个Gray bus的max_skew与同值max_delay约束均保留于实际映射，
有界数据路径setup通过；放置报告未提供数值max-skew表，最终布线仍需明确核验。
证据 `build/video/face_avatar_route_review_20261102/result.json`。

启动一次固定seed4放置DB的route，开启文档支持的multi-corner/fix_hold_violation及
fix_hold_violation_in_route。冻结源码、固件、约束及数据库；不重新放置/换seed，
不放宽时钟不增加false path。90分钟硬上限，超时记录并终止此PDS进程树，不自动重试。
完成后自动生成全角时序和routed gate sites，仍保留STA_REVIEW_REQUIRED，只有
零未布线、所有时序/偏斜及边界证据齐全才可进入工程/位流交付。此处不是时序闭合。


### 2026-11-03 布线超时，转向删除显示上下文重复副本

face_avatar_route_20261102 在90分钟上限停止，iteration15仍有63168条未布线网络；
输入哈希未变，相关PDS/Python进程全部退出，active_runs为空。没有最终route数据库或STA，
不能把此前放置setup通过当作闭合；不重启同一候选、不换seed。

综合u_pixels/u_context占7880 FF；compact renderer实际仍使用普通复制式CDC。
候选仅改用已有held-record消费者，MMIO原记录由link保持至扫描/像素联合反馈，
像素active副本继续保留；删除中间两份宽记录，保持ABI、三模式、输出延迟及释放语义。
先实际组合源破坏负对照、shadow并发写/忙提交拒绝、异步比率及逐像素组件回归，
再测量资源收益，收益成立才进入真实整机/单次综合。新增原记录到像素域6ns有界路径，
不加false path；端点和最终全角物理时序另行验收。源码备份及旧哈希在
build/video/face_held_context_20261103/before/及before_hashes.json。


接续：真实组合负对照已红/绿核实，握手接受后的源记录破坏在新组合准确触发
HELD_RECORD_SOURCE_CHANGED；旧组合未检测。首次注入早于接受边沿，已作废并修正，
以build/video/face_held_context_20261103/negative_review.json为准。
已接入候选并同步显式整机/板级source列表，BOX_ONLY参数兼容原分支；尚未物理采用。
新增的原记录到pixel_clk路径保持6ns上限，所有频率及0.2ns margin不变。

2026-11-03 00:22:56启动唯一协调器Python6980，组件Python48924及vvp49044实际在运行，
组件目录build/soc/resource_probe_video_compact_20261102T162256_315033Z。
receipt: build/video/face_held_validation_20261103/receipt.json。
流程为23项组件回归→同端口像素组件新旧资源比较→仅当至少减少4000FF、LUT增长不超过100
且DRM/APM不增加才接续真实三模式完整加载整机→同一ELF单次板综合。
失败立即写真实状态并清空active_runs；完成停在CDC/复位/资源审核，不自动放置或布线。
源码、脚本、约束已冻结；后续以该receipt及active_runs核对实际运行。


### 2026-11-03 00:42 23项组件通过，准入变化核实后接续资源比较

build/soc/resource_probe_video_compact_20261102T162256_315033Z/result.json 已PASS：
23项含两种时钟比逐像素、RAW/BOX/AVATAR组合、模式独立提交、槽/素材释放、
shadow并发写及忙提交拒绝、复位、源记录破坏负对照。所有组件实际输入哈希未变。

原协调器在组件结束后检测config/cpu_admission.json变化并正确停止，active_runs已清空，
没有残留Python/PDS/ModelSim。变化来自当前共享CPU CSR/LSU审查的准入清单更新；
本轮冻结期间仅该清单变化，CPU RTL字节及显示组件输入均未变化。
当前CPU admission_common.validate()重新PASS；核对本地CSR regfile已同步进入CPU、
SoC和板级显式source列表，保留对方修改。旧板级物理证据不覆盖当前CPU修正。
证据build/video/face_held_context_20261103/resume_admission.json，保存新清单实际字节。

未重跑已通过组件；新独立协调器build/video/resume_face_held_20261103.py以当前哈希冻结，
00:42:36启动Python49576，资源比较Python23708/PDS14196（子47336）实际运行。
新receipt为build/video/face_held_validation_resume_20261103/receipt.json；依次比较原/候选
像素组件资源，达到既定削减门槛后自动接续完整真实整机及同一ELF单次板综合。
完成停在CDC/复位/资源审核，不自动布线；原失败记录保留，不改写为PASS。


### 2026-11-03 01:09 资源报告解析修正，复用已完成基线

上一协调器在基线组件综合完成后停止：resource_report给出的根层级名称为u_pixels，
统计脚本错误要求以/u_pixels结尾。真实综合成功，非RTL失败，候选综合当时未启动；
该失败及无活动进程状态已保留。基线u_pixels实际8763 LUT/15475 FF/6 APM/0 DRM，
扫描夹具资源单列，不用于板级时序结论。

已用真实保存的.snr验证解析修正。新资源脚本复用原基线，核对每个冻结源码，且候选
扫描夹具必须除被测模块名外逐字相同；不重跑23项组件或基线综合。证据
build/video/face_held_context_20261103/resource_parse_review.json。
新协调器build/video/continue_face_held_resource_20261103.py于01:09:55启动，
Python41980/资源Python51492/PDS51144（综合子47408）实际在运行。
receipt: build/video/face_held_validation_resource_20261103/receipt.json。
达原资源削减门槛后自动接真实整机、同ELF单次板综合，仍不自动放置/布线。


01:10 接续：资源比较PASS。相同扫描边界下像素组件从8763 LUT/15475 FF降至
8853 LUT/7777 FF，即FF减少7698（49.7%）、LUT增加90（1.03%），6 APM/0 DRM不变。
所有实际源码与冻结副本一致，原基线未重跑。满足原门槛，已自动进入
build/soc/face_system-20261102T171030_980602Z，整机Python39712；完成通过后接同ELF板综合。
此资源结果仅证明组件收益，不宣称整板资源、CDC路径或物理时序已经通过。


### 2026-11-03 01:36 held-record三模式整机通过，综合正在运行

build/soc/face_system-20261102T171030_980602Z 已PASS：7段完整模型/头像加载、真实CPU/NPU、
RAW/BOX/AVATAR逐像素、模式提交、槽释放复用均通过。49663086周期，与此前三模式基线
相同，Errors/Warnings均为0；组件23项PASS仍保留。实际源码与仿真冻结副本、工具及
外部输入哈希均重新核对；同一ELF已进入板级综合。
证据build/video/face_held_context_20261103/system_review.json。

唯一活动流程已自动进入build/video/pds/20261102T173040_811236Z，协调器Python41980、
综合Python8548/PDS25580（子30532）实际运行。CPU CSR/LSU新字节包含在本次整机中；
旧物理证据不挪用。保持冻结输入，综合完成后核对实际资源、CDC新增6ns路径、复位和
约束命中，再决定单seed4放置；尚无该候选的板级综合/物理闭合结论。


### 2026-11-03 held-record综合完成，但CDC/复位失败，先修正再放置

build/video/pds/20261102T173040_811236Z 综合完成：51449 LUT/47583 FF/141.5 DRM，
相对三模式旧基线FF减少7700、LUT增加187（同时含已准入CPU CSR修正）。132个共享源码、
同ELF及ROM/SRAM逐字一致。所有旧进程退出，active_runs为空。

该候选不准入放置：原记录到SOF overlay组合路径在6ns约束下-5.110ns/89端点；
组合双域复位引出recovery -6.879ns/74端点、removal -2.065ns/105端点。
证据build/video/face_held_retime_20261103/previous_synthesis_review.json。不是工具完成即闭合。

修正：复位各域两级同步释放，仅四个异域release链async C引脚精确例外；本地复位
扇出、D/Q/CE及同步级间仍计时。将原末级像素输出寄存器移到RAW入口，记录在SOF
先捕获到pixel active_data，overlay仅使用本地域数据，删除宽跨域旁路和选择器。
显示总延迟不变；素材请求9->10拍，提交证明相应等到首像素/故障已寄存，不能提前ACK。
不放宽6ns有界路径、频率或0.2ns margin，不修改CPU/NPU配置。

复位释放red已复现；定向green含首次采样故障、无空隙帧逐像素及pending reset均通过。
将新提交标记故意提前一拍的负对照准确触发RECORD_PIXELS_FALSE_FAULT_COMMIT。
证据build/video/face_held_retime_20261103/focused_review.json，before/及新旧哈希保留。
接续25项组件回归、完整真实整机三模式和同ELF单次板综合；当前尚未验证新物理时序。


### 2026-11-03 03:12 held-record重排通过整机与综合审查，接续单次放置

25项组件回归PASS；build/soc/face_system-20261102T182652_956679Z整机PASS：
7段完整模型/头像加载、真实CPU/NPU、RAW/BOX/AVATAR逐像素、模式提交与槽释放复用均通过，
49663086周期，Errors/Warnings=0。旧协调器/PDS/ModelSim均已退出，active_runs已清空。
综合build/video/pds/20261102T184655_932606Z：49056 LUT、47680 FF、141.5 DRM；
相比完整头像基线减少2206 LUT/7603 FF，相比首次held候选减少2393 LUT、增加97 FF。
132个共享源码、同一ELF及ROM/SRAM实际字一致，454个冻结输入重新核实未变。

新增双域复位链的综合网表确认各两级，stage0仅连接stage1；四个异域async C引脚
被PDS准确解析，D/Q/CLK/CE与本地扇出没有新增例外。5项审查负对照均被拒绝。
原记录的6ns限制保持，active_data先在像素域捕获，overlay没有跨域原记录旁路。
视频到像素域综合setup最差+2.297ns、零失败；recovery/removal/pulse均零失败。
综合最差setup仍为视频link.base到state CE的-0.431ns/102端点，hold -1.536ns/71端点；
综合fast表为空，不能充作物理通过。计算域setup +0.138ns已计入0.2ns uncertainty。
证据build/video/face_held_retime_synthesis_review_20261103/result.json。

准入一次复用该综合DB的seed4映射/放置，完成自动分析慢快角及实际DDR gate sites，
停在物理结果审查，不自动route；每个PDS阶段40分钟上限，超时终止对应进程树。
流程receipt为build/video/face_held_retime_place_flow_20261103/receipt.json，
放置目录build/video/pds/face_held_retime_place_20261103。所有输入继续冻结。
NPU仍为control_decode；图调度/部分模型校验迁移、最终max-skew数值核验、
工程/位流交付、外部HDMI AC及板测仍待完成。本次没有物理时序闭合结论。


### 2026-11-03 03:48 放置未通过，依据两类关键路径删除晚到控制链

held_retime seed4放置及全角分析已完成，所有进程已退出，active_runs已清空。
慢角setup -0.491ns/27失败端点、TNS -6.498ns；快角setup +0.462ns/零失败。
计算域慢setup +0.502ns；像素本域+1.175ns；6ns视频到像素有界路径最差+0.115ns。
hold慢/快-0.368/-0.412ns，60/94失败端点；recovery、removal、pulse均零失败。
实际两个DDR gate sites通过。max-skew数值最终仍待核实。本候选未启动route。
证据build/video/face_pointer_guard_20261103/previous_placement_review.json。

真实首路径从DDR ready状态经采集READY进入ingress FIFO的prefetch，再进入二进制加法及
Gray编码；另一类从record guard的lane[2]（扇出1033）经256位记录选择、坐标比较进入
错误结果CE。选择提前计算而非增加流水拍：FIFO恒定计算read+1/Gray及两个empty候选，
prefetch只选更新/保持；框校验在每个固定slice先判断，lane仅选择1位错误结果。
保持FIFO容量、出数顺序、背压、Gray协议、校验顺序及17拍成功延迟，不改变时钟或约束。
未修改板级ready安全门、CPU/NPU配置或NPU准入哈希。旧源码及新旧哈希均已保存。

先运行独立队列/逐项框边界oracle，破坏stall保护及矩形检查的基线负对照均准确失败。
候选FIFO五种深度/时钟组合及四种采集场景PASS；框校验246项PASS，覆盖所有16框/5点、
有符号坐标、零宽/反向高、缺失/保留字段、错误优先级、背压和逐项完成拍数。
同样的两种候选负对照均准确失败。证据build/video/face_pointer_guard_20261103/focused_review.json。
框定向测试已纳入run_video_compact.py，完整组件变为26项。

接续唯一协调器build/video/continue_face_pointer_guard_20261103.py：26项组件→完整真实
CPU/NPU七段加载/三模式整机→同ELF单次综合；使用已通过的9项FIFO/采集证据。
receipt: build/video/face_pointer_guard_validation_20261103/receipt.json。
综合后停在结构、资源及时序审查，不自动放置/布线。输入冻结至协调器结束。
此处只证明定向功能回归，未宣称新实现整机或物理时序通过。


### 2026-11-03 07:39 指针/框校验重排通过整机与综合审查，已接续单次放置

26项组件PASS（框校验246子项）；完整七段模型/头像加载、真实CPU/NPU及RAW/BOX/AVATAR
整机PASS，49663086周期，Errors/Warnings=0。结果build/soc/face_system-20261102T195356_684319Z。
综合build/video/pds/20261102T201358_344221Z完成：49087 LUT/47678 FF/141.5 DRM。
相对上一held_retime候选+31 LUT/-2 FF；相对完整头像旧基线-2175 LUT/-7605 FF。
132个共享源码、同一ELF、ROM/SRAM逐字一致，457个冻结输入重新校验通过。
验证协调器已结束，旧RUNNING已清除；本批没有重复启动综合或整机仿真。

综合网表独立连接审查确认11个FIFO变体的读binary/Gray寄存器D锥仅来自rd_binary，
prefetch仅进入CE；旧候选作为负对照被拒绝。框校验lane[2]实际primitive负载1031->10，
lane不再进入任何比较carry锥，旧候选仍会进入比较carry。原4个时序/物理约束文件字节未变。
计算/视频/像素周期10/8/25ns及0.2ns margin策略保持；双域释放链、四个精确异域C引脚、
6ns记录跨域界限和像素本地域捕获再次通过审查，5个复位/约束负对照均被拒绝。
综合视频->像素setup +2.267ns、compute setup +0.112ns；最差setup -0.461ns/107端点，
hold -1.536ns/71端点，recovery/removal/pulse零失败；fast综合表为空，不能宣称物理通过。
证据build/video/face_pointer_guard_synthesis_review_20261103/result.json。

已启动唯一seed4映射/放置协调器（Python PID 28072），复用上述综合DB，
每个PDS阶段40分钟上限，完成后自动分析全角时序及实际DDR gate sites，停在人工结果审查。
receipt: build/video/face_pointer_guard_place_flow_20261103/receipt.json；
placement: build/video/pds/face_pointer_guard_place_20261103。新运行输入继续冻结。
未启动route；最终零未布线、慢快角全时钟对、max-skew数值与全部margin仍须实测报告验收。
图调度/部分模型校验迁移、工程/位流交付、HDMI外部AC及板测仍未闭环；不扫描或下载。


### 2026-11-03 07:51 放置setup通过，立即接续固定放置的单次hold修复布线

本轮映射/放置合计516秒，分析已完成；旧协调器/PDS进程退出，旧RUNNING已清除。
慢/快角setup最差+0.827/+1.302ns，均零失败；视频域慢setup +0.832ns，计算域+0.827ns，
像素本域+6.282ns，6ns视频->像素有界路径+0.969ns。recovery/removal/pulse全角零失败。
hold慢/快-0.354/-0.413ns，140/225失败端点，三个失败时钟对都属于DDR PHY；
95条报告中的失败hold路径首尾均在厂商DDR范围内，实际两个DDR gate sites通过。
23组Gray max_skew与配套max_delay在映射记录中匹配，最终数值偏斜仍待布线报告核验。
证据build/video/pds/face_pointer_guard_place_20261103/placement_analysis/result.json。

准入一次已有seed4放置的物理hold修复route。每个失败时钟对的慢setup减去两倍快hold
缺口后，剩余4.752/2.052/0.242ns。最后一对余量有限；此为布线尝试筛选，不能视为
跨角修复保证或签核，原时钟、0.2ns margin及全部约束未变。相比旧路线的固定1ns
尝试筛选，现明确用双倍缺口与0.2ns剩余量评估；没有降低最终任何验收门槛。
准入证据build/video/face_pointer_guard_route_review_20261103/result.json。

已启动build/video/route_face_pointer_guard_20261103.py（Python PID 472，
启动PDS PID 33192），receipt为build/video/pds/face_pointer_guard_route_20261103/receipt.json。
固定放置不重综合、不换seed、不重做已通过的整机；route有90分钟硬上限，超时终止自身树。
布线成功后自动在独立PDS调用里生成全角时序及实际gate sites，修正旧脚本在route前
预解析尚不存在routed DB的问题，报告阶段10分钟上限。没有等待下一次半小时heartbeat才接续。
路由完成后仍须零未布线、慢快角全时钟对与0.2ns margin、max-skew数值、约束匹配及
实际gate sites全部验收。当前没有闭合位流，不扫描/下载。图调度/模型职责迁移与外部AC/板测仍开放。


### 2026-11-03 09:49 固定放置route超时，转入限时拥塞取证

route在09:20:29达到90分钟上限，按既定策略终止自身PDS树，未生成routed DB/全角报告。
第51次详细布线迭代仍有34720条未布线（总nets 99896）；最后几轮为35695、35417、
35041、34720，仍有进展但逐轮下降变慢。旧Python/PDS均退出，active_runs已清空；
480个冻结输入重新校验无变化。原receipt保留STOPPED_REVIEW_REQUIRED，工程台账明确
记录FAILED_ROUTE_TIMEOUT。没有位流/物理闭合结论，也不能把本次超时当作永远不可布通。
失败审查build/video/face_pointer_guard_route_failure_20261103/result.json。

映射使用49068 LUT/47575 FF/141.5 DRM（74%/36%/92%），存在多条数千扇出的控制网络。
日志无PDS错误，CPU持续工作；不能仅凭占用和慢进展断言某个RTL模块是拥塞根因。
本轮未开启厂商拥塞导出，缺少具体冲突网络及SRB位置。PDS User Guide第113页说明
Dump Router Congestion Plot会导出CongestionPlot和CongestionNetInfo；本机help确认
参数-dump_router_congestion_plot TRUE。当前也没有证据支持换seed或延长完整布线。

已启动单个短时诊断采样：build/video/diagnose_face_route_congestion_20261103.py，
Python PID 40636、PDS PID 4256。同一map/placement DB、同一频率/约束和路由选项，
仅打开拥塞明细导出；规范化脚本文本对比确认只有该开关变化。详细迭代>=5且两类文件
都产生即停止，否则10分钟硬上限；此运行是取证，不作为第二次交付布线或时序验收。
receipt: build/video/pds/face_pointer_guard_congestion_20261103/receipt.json。
下一步按冲突net层级和热点位置判断布局密度/硬块邻近/控制扇出/工具设置，再决定改动。
不改活动运行冻结输入，不扫描/下载，不触及technical-report。


### 2026-11-03 10:12 GitHub当前源码快照

按用户要求推送当前应用版本，功能及物理边界见docs/verification/npu/2026-11-03-face-version-snapshot.json。
提交前重新核对162个整机源码、37个输出及外部输入哈希；头像/显示ABI生成检查、13项时钟与上传器
测试、CPU admission均PASS。包含当前整机依赖的CSR/LSU修正与来源记录；不包含技术报告及独立审查脏文件。
本次是功能回归通过的源码快照，route仍为90分钟超时、末次34720未布线，不代表可下载或物理闭合。

拥塞诊断已结束，active_runs为空，485个冻结输入未变，但未得到预期冲突导出，状态为
DIAGNOSTIC_INCOMPLETE_REVIEW_REQUIRED。receipt记录实际1174.6秒，超过设定600秒，计时及停止路径
需要单独核查，不能声称10分钟硬上限已经验证。该问题与具体拥塞根因均继续待查。


### 2026-11-03 10:35 核实系统待机干扰，修正布线耗时解释并接续取证

Windows Kernel-Power 原始事件确认，07:50–09:20 的90分钟route与08:06–08:29及08:39之后的
Modern Standby重叠约3863秒（64.4分钟）；09:48启动的短诊断与合盖待机重叠约1061秒。
待机期间可能允许部分后台工作，因此不能把重叠时间全部扣作PDS暂停，也不能把墙钟耗时
说成连续CPU计算时间。原route仍是超时且34720未布线，但90分钟不能用于推断连续计算
90分钟仍未收敛。诊断在10:08:01电源状态转换后约6秒结束；旧监控缺少逐段耗时，不能
精确区分调度暂停、文件查询与终止耗时。证据build/video/face_route_runtime_audit_20261103/result.json。

诊断日志未进入详细布线；厂商手册只承诺在详细布线阶段导出冲突数据，故缺少两个导出目录
尚不能说明导出开关失效。485个冻结输入再次核对不变，原运行已结束，台账无遗留RUNNING。

增加临时运行监督器，仅在PDS运行期间请求SystemRequired/ExecutionRequired，不改变系统
电源设置。每5秒记录进程树CPU时间、wall/Windows unbiased awake时间、日志大小及最大
轮询间隔；到600秒deadline或详细迭代>=5且两类证据齐全后停止自身树。明确合盖/手动
休眠可能覆盖请求，系统暂停时进程无法执行停止；恢复后立即检查deadline，不再称硬墙钟上限。
三项检查PASS：真实父子进程限时终止、拒绝只有全局迭代/单类导出的样本、电源请求异常退出释放。
未主动触发整机休眠测试。脚本build/video/route_runtime_guard_20261103.py。

下一次取证继续复用同一seed4 map/placement DB、全部时钟/约束和PDS选项，只有运行监督改变。
新receipt为build/video/pds/face_pointer_guard_congestion_awake_20261103/receipt.json；
实际活动进程以active_runs和该receipt为准。未开启新的完整验收布线、未改RTL、未扫描/下载。


### 2026-11-03 10:56 拥塞证据已取得，接续单变量布局实验

awake诊断于10:39:02结束：wall/awake均约266.0秒，最大轮询间隔5.016秒，停止进程树
0.389秒；两类导出各6份，487个冻结输入及12份导出哈希全部复核通过。PDS已退出，
旧RUNNING清除。前6轮未布线数量与原route逐项完全一致，导出开关未改变这段观测序列。

补充重要更正：原route逐轮打印的CPU时间累计4993秒（83.2分钟、52轮），因此待机重叠
不能当作丢失的计算时间；它在待机期间仍做了大量计算。上批关于待机的解释仅能说明
wall不等于CPU、短诊断受调度干扰，不能据此淡化原route的实际拥塞。不能继续仅等待。

第5轮77319未布线，冲突明细76524条、不同设计net 63149条，冲突分值总和202136；
最高10个net的合计占比约6.9%。plot有10083个非零网格，3531个网格分值>=20，
总分167745。NPU输入/vector、显示renderer、CPU、控制/MMIO等都有大量冲突。驱动
位置及实际primitive位置已导出；这些是冲突/位置统计，不能当作资源使用百分比或时序。
尚无证据把某个高扇出控制认定为唯一根因。证据build/video/face_congestion_analysis_20261103/result.json。

只做一次同seed4/同mapped DB的布局扩散实验：plc_decongestion显式设2（基线未显式设置，
厂商默认表为1）。依据手册使用空间扩散减少广泛拥塞的机制；LUT74%/DRM92%下可能
变差，故不是已确认的修复，也不轮换seed/扫参数。RTL、时钟、0.2ns margin及所有约束不变。
先放置及全角报告；仅当非hold全部通过、gate sites正确、仍只有DDR hold且原保守修复
筛选通过，才自动采样同样6轮，600秒deadline。第5轮未布线和plot总分均下降>=10%
才通过后续审查筛选；这不证明最终收敛，完整route仍不自动启动。

原放置正例及5类负对照验证筛选器PASS（setup/recovery、gate、非DDR hold及不足修复余量
均被拒绝）。协调器build/video/experiment_face_decongestion2_20261103.py；receipt
build/video/face_decongestion2_flow_20261103/receipt.json。实际活动状态以active_runs为准。
物理时序仍未验收，max-skew、全角最终报告及工程/位流、外部HDMI AC/板测仍待闭环。


### 2026-11-03 11:25 宽记录仅复位有效状态：设计及验证计划

布局扩散2实验已完成且全部进程退出，506个输入/12个导出复核不变。setup慢/快
+0.841/+1.290ns且非hold全角零失败；hold仍为DDR，慢/快-0.407/-0.443ns、164/247端点。
第5轮未布线77319->73670（仅4.72%改善）、plot总分167745->144537（13.84%改善），
未达到两项均>=10%的预定门槛，不准入完整route，也不继续轮换布局参数。
证据build/video/face_payload_reset_20261103/placement_experiment_review.json。

下一项限定为删除冗余宽数据复位。实际综合网表MMIO record_data 5120个、pixel active_data
3849个GTP_DFF_CE实例都带C复位。两者分别有完整160词装载及pixel_active资格保证。
对比方案：继续调布局不能解决控制需求；复制/加级复位增加状态和恢复拍数；本次选择只
移除这两组payload数据的复位，保持窄状态/有效位、owner、CDC同步器和复位释放链原样。
MMIO在LOAD/ARCHIVE才移位，INIT复位后的160词RAM清理和160词装载流程不变；像素
仅在apply_now捕获全记录。保持所有命令/像素/反馈拍数、完整guard和CPU资产准入。
像素未active期间保持64位资产tag输入为复位值，防止未初始化payload污染原有确定性idle tag。
不对数据总线新增false path，不改FDC/PCF/RCF或任何NPU字节。

- [ ] 备份原字节与哈希；新增冷启动/热复位后payload注入X的MMIO及像素定向测试，验证
      完整覆盖、重载、背压、无假提交/退休/故障、RAW/BOX/AVATAR逐像素结果。
- [ ] 先运行基线，确认测试能看到未限定的idle tag；负对照破坏完整装载或有效状态复位应失败。
- [ ] 改两个payload寄存器的写入块；只给asset tag增加局部有效限定，业务路径拍数不变。
- [ ] 定向测试和负对照通过后，跑扩展组件回归及完整七段加载真实CPU/NPU/显示整机。
- [ ] 以同一ELF做一次综合，核对资源、数据D/CE/C连接、复位负载、CDC约束和输入字节；
      再审查是否值得seed4放置，不自动route。

本设计处于用户已授权的接口/冗余控制优化范围内；按现有自主推进指示执行，不另加审批。
备份build/video/face_payload_reset_20261103/before/及before.json。


### 2026-11-03 11:28 宽记录复位候选定向通过，接续整机与综合

布局扩散2已复核并拒绝完整route：未布线只改善4.72%，小于预定10%；没有继续扫参数。
随后只移除MMIO record_data与像素active_data的宽payload复位，保留phase/pixel_active、
owner/CDC/同步器及全部窄控制复位；以pixel_active限定64位资产tag输入，保持idle tag确定。
原综合网表对应5120+3849=8969个带C引脚的数据触发器；新网表实际是否去掉C须综合后核验，
不把源码变化当成已降低物理负载。NPU字节、时钟及全部约束均未改，原字节/哈希保留。

四项新定向测试PASS：MMIO全记录/背压及热复位、像素三模式逐点oracle及pending热复位，
均在每次复位释放后注入未知payload，证明必须完整覆盖或由有效状态隔离。原实现负对照
检出idle资产tag未知；人为少装一个字、有效位不复位分别被拒绝。测试中的复位同沿采样
竞态已修正为NBA完成后检查，未为通过测试改动RTL。证据
build/video/face_payload_reset_20261103/focused_review.json。完整组件套件增加为30项。

接续唯一协调器build/video/continue_face_payload_reset_20261103.py：30项组件->完整模型/
头像七段加载、真实CPU/NPU/采集与RAW/BOX/AVATAR整机->同ELF单次综合。期间采用临时
防空闲休眠请求和逐进程CPU/awake/wall监督；输入冻结，综合后停在结构/资源/时序审查。
receipt: build/video/face_payload_reset_validation_20261103/receipt.json。此处仅证明定向组件，
不宣称新候选整机、综合或物理时序已通过。原placement和原时序证据仍只适用于旧字节。


### 2026-11-03 12:22 宽记录复位候选整机与综合审查通过，接续单次放置

验证协调器12:02结束，30项组件PASS；完整七段模型/头像加载及真实CPU/NPU、采集、
RAW/BOX/AVATAR逐像素整机PASS：captures4/requests4/results2/records2，两个完整像素帧，
modes111，49,663,086 cycles，0 errors/0 warnings。DDR为native存储代理；单自然人脸样例，
不外推成物理PHY、泛化准确率、长稳或FPS验收。459个冻结输入重新逐项校验不变，整机与
综合132个共享源码、相同ELF及ROM/SRAM词一致。旧Python/PDS/ModelSim已退出且无遗留RUNNING。

综合网表逐位核对MMIO5120+pixel3849=8969个payload触发器均为GTP_DFF_E且无运行时
C/P复位；保留全局配置GRS。MMIO其余259及像素其余1109个触发器的复位/时钟签名与旧
网表完全相同。旧网表被“payload不得带C”负对照拒绝。11组FIFO指针D锥、guard lane与
carry隔离、held双级释放/精确4个C引脚例外、记录6ns上界全部保留；四份FDC/PCF/RCF和
CPU/NPU/PLL源字节不变。资源49104LUT/47676FF/141.5DRM，相比前候选+17LUT/-2FF。

综合慢角setup最差-0.461ns/191端点，其中compute -0.316ns/90端点（前次+0.112ns）。
路径是NPU layer/state[1]到input_path/shadow_valid[3]，14级，逻辑1.593ns、估算布线
8.237ns。compute源码未改不能抹去这一估算退化，成因尚未证实，必须在放置重新检查。
video->pixel +2.267ns；recovery/removal/pulse零失败。此处只证明连接与功能，不宣称
物理拥塞改善或闭合。审查build/video/face_payload_reset_synthesis_review_20261103/result.json。

结构收益及资源变化足以支持一次固定seed4的默认mapping/placement测量；不使用已拒绝的
plc_decongestion=2。新helper与原默认流程生成TCL的AST比对完全一致，仅增加临时电源请求、
CPU/awake/wall监督及有界进程树终止。map/place各40分钟deadline，分析5分钟；系统暂停时
无法执行停止，恢复后检查deadline，不声称不可超出的墙钟硬上限。完成后自动分析全部慢快
角与DDR gate sites，停在审查，不自动完整route。实际进程/结果以active_runs及
build/video/face_payload_reset_place_flow_20261103/receipt.json为准。

待验收仍包括零未布线、全角全时钟对、数值max-skew、约束匹配、工程/位流及外部HDMI AC/
板测。图调度/模型校验迁移仍未闭环。未扫描或下载，未触及technical-report或NPU准入字节。


### 2026-11-03 12:52 控制判断复用：路径证据及验证计划

宽payload复位候选放置12:34完成且进程退出；461项协调器、12项map/place、5项分析输入
重新校验。setup慢角compute -0.120ns/4端点、video -0.070ns/4端点；fast +0.919ns零失败。
hold慢/快-0.354/-0.398ns、75/148端点，仅DDR对；recovery/removal/pulse全角零失败，
gate sites正确。现有布线筛选器按setup_slow拒绝，不启动拥塞探针或完整route。
证据build/video/face_payload_reset_20261103/placement_review.json。数值max-skew仍待最终物理验收。

两条实际路径：display link seq经100位反馈身份比较的串行carry进入owner release CE，
16级；NPU op[7]经重复opcode解码、DW横坐标选择、边界比较进入ROI req，11级。
选择保持原拍数的控制复用，而非新增流水或换seed：
1. owner保留完整100位身份核验，按4/32/32/32位并行case equality并保留分组边界；向MMIO
   导出同拍“匹配反馈已接收”，MMIO删除重复lease_inflight及第二套身份/握手判断。
   owner仍是提交/错误/退休的唯一判定者，保留同拍commit+旧帧retire能力。
2. NPU仅DW横坐标选择复用现有接受START时锁存的完整32位is_dw_op，替代code==2。
   不新增加级、寄存器或延迟，原先已通过的control_decode结构保留；其余NPU逻辑不改。

先备份全部旧字节和哈希。扩展反馈每位错误/X/Z、背压、同拍退休、复位检查；比较原版和
候选公开行为并做省略seq/提前feedback接收负对照。NPU在原控制测试中增加实际input_path
横坐标端口校验、START后输入扰动、高位非法opcode；错误复用dense decode负对照必须失败。
定向通过后备份新字节并更新UPSTREAM.json/import_b03.py admission hash、运行准入；
再做组件/完整七段加载三模式整机和同ELF一次综合，先审查实际网表再决定放置。
全部频率、0.2ns margin、CDC及FDC/PCF/RCF保持原样。该项为已授权的控制去重，继续自主执行。


### 2026-11-03 12:55 控制复用定向通过，接续整机与综合

owner导出同拍feedback_accepted供MMIO复用；删除MMIO lease_inflight和第二套反馈判断。
完整100位反馈身份仍逐位核验，按4/32/32/32分组保留综合边界。NPU只将DW横坐标选择的
code==2替换为既有is_dw_op；无新增状态/拍数。原和新RTL、UPSTREAM与admission脚本均已
备份至build/video/face_control_reuse_20261103/before与after；独立新进程准入41项PASS。

原版先通过新增测试。候选owner在1/128/5120位context各12项（共36项）通过；每宽度覆盖
100个身份位分别翻转/置X/置Z共300种错误，另含早到反馈、错误后正确反馈排空、同拍旧帧
退休/新帧提交、背压/模式/序号wrap/热复位。MMIO9项回归23个公开输出逐周期trace与旧版
完全相同，共42191周期。NPU8416项控制检查覆盖实际input_path坐标端口、START后源opcode
改变、CE0/取消组合及高位非法opcode。省略seq比较、提前接收未发送命令、DW错用dense选择
三个负对照均以预期功能错误失败。扩展测试已加入正式TB与回归入口，compact套件增加为42项。
focused_review.json保留全部证据/哈希。

启动唯一协调器build/video/continue_face_control_reuse_20261103.py：新进程source admission、
已安装字节NPU控制检查、42项组件、完整七段加载/真实CPU/NPU/三模式像素整机，再以相同
ELF单次综合；全程冻结输入、临时电源请求及CPU/wall/awake监督。综合后审查feedback分组
实际carry长度/源复用与NPU selector是否脱离opcode宽解码，及资源/全域时钟/CDC，再决定
单次放置。本条未宣称新候选整机/综合/物理通过。实际活动状态见active_runs与
build/video/face_control_reuse_validation_20261103/receipt.json；无自动完整布线。


12:55补充：首个协调器因layer_controls测试输出与监督日志目录重名，在启动ModelSim之前
以FileExistsError停止，462项输入未变且进程已退出。保留原失败receipt；新建v2协调器，
仅将测试输出独立为layer_test，未改RTL。实际活动receipt改为
build/video/face_control_reuse_validation_v2_20261103/receipt.json；原失败不计为功能失败或活动运行。


### 2026-11-03 13:54 控制复用整机与网表审查通过，接续固定 seed4 放置

验证协调器13:30完成且Python/PDS/ModelSim已退出；42项组件和完整七段模型/头像加载、
真实CPU/NPU/采集、RAW/BOX/AVATAR像素整机通过：captures4/requests4/results2/records2、
两个完整像素帧、modes111、49,663,086 cycles。462项冻结输入不变；整机/综合132个共享
源码及ELF、ROM/SRAM词一致。DDR为native存储代理，单人脸样例不外推成物理PHY、准确率、
长稳或FPS验收。验证receipt为build/video/face_control_reuse_validation_v2_20261103/receipt.json。

综合网表确认完整100位反馈身份仍在；4/32/32/32分组分别为0/16/16/16个carry单元，
原最长50个carry的反馈比较已被旧网表负对照拒绝。owner接受结果连接到MMIO，重复
lease_inflight触发器消失，其余非payload复位/时钟签名保持；DW坐标13位锥使用锁存
is_dw_op，无原opcode宽解码根，旧网表也被该检查拒绝。NPU只有一行选择修改，准入41项通过。
8969个payload FF仍无运行时C/P、保留GRS；11组FIFO指针、guard/carry隔离、held双级
释放与精确4个异步C引脚例外、记录6ns上界保持。100/125/40MHz及0.2ns余量和四份约束不变。

资源49148LUT/47677FF/141.5DRM，相对前候选+44LUT/+1FF。综合compute setup从-0.316ns/
90端点改善为+0.088ns/0端点；video仍-0.461ns/101端点，hold最差-1.536ns/71端点。
综合估算不足以验收物理时序。审查结果PASS_SINGLE_PLACEMENT_ADMISSION，证据：
build/video/face_control_reuse_synthesis_review_20261103/result.json。

接续build/video/continue_face_control_reuse_place_20261103.py，复用已核验默认放置/分析
helper，不换seed、不启用decongestion覆盖。map/place各40分钟deadline、分析5分钟，
临时防休眠请求及CPU/awake/wall监督；系统暂停期间无法执行deadline检查。完成后自动
报告慢快角全部时序类型及DDR gate sites，停在审查，不自动route。活动状态以active_runs及
build/video/face_control_reuse_place_flow_20261103/receipt.json为准。

物理布线拥塞、最终零未布线/全角全时钟对/数值max-skew/约束匹配/工程位流仍待验收；
图调度及CPU模型校验迁移、外部HDMI AC和板测仍有未闭环项。没有扫描或下载板卡。


### 2026-11-03 14:22 控制复用放置通过 setup 筛选，接续单次拥塞采样

seed4默认放置及分析于14:05完成，旧Python/PDS进程已退出，active_runs已自动移除。
本次复核480项协调器、12项map/place、5项分析输入，以及500项合并审查输入的哈希均不变。
映射60.1秒、放置501.4秒，awake/wall一致，最大轮询间隔5.06秒，无休眠导致的长空隙。

慢/快角18组setup均零失败，最差+0.289/+1.342ns；compute慢角+0.816ns，video慢角
+0.289ns，原compute -0.120ns及video -0.070ns路径已不再违例。全角recovery/removal/
minimum pulse width零失败，DDR gate sites正确。hold慢/快-0.354/-0.398ns、77/131端点，
仅三个DDR PHY时钟对；报告83条hold路径的起终点均位于厂商DDR层次内。保守扣除两倍
fast hold缺口后的setup预算分别3.876/2.062/1.739ns，仅用于判定有条件尝试布线，不能
作为hold已修复的证明。23组Gray bus的delay/skew指令均出现在mapping报告，数值max-skew
仍无可验收表。171条外部I/O未约束警告与上一放置完全相同，保留DDR/HDMI外部AC边界。

审查build/video/face_control_reuse_20261103/placement_review.json通过有界拥塞采样准入。
接续build/video/probe_face_control_reuse_congestion_20261103.py，复用旧采样的全部PDS参数，
仅换成本次冻结mapped/placed DB和独立输出目录；仍固定seed4、原时钟/0.2ns余量/约束。
600秒wall deadline或详细布线iteration5采样齐全即停止，临时电源请求及CPU/awake/wall监督。
自动比较同一iteration5的未布线数和厂商拥塞图分数；两者都须比已核验pointer_guard基线
改善至少10%才考虑完整route。这是预定成本筛选条件，不是收敛或时序闭合保证。
不会自动启动完整route，输出及进程以active_runs与
build/video/pds/face_control_reuse_congestion_probe_20261103/receipt.json为准。

物理布线、hold修复、数值max-skew、最终约束匹配、工程位流和外部AC/板测尚未验收。
完整功能仿真已通过的范围保持不变，图调度/CPU模型校验迁移仍未闭环。


### 2026-11-03 14:58 控制复用拥塞筛选拒绝，转向点范围比较合并的隔离测量

采样14:28以sufficient_diagnostic_sample正常停止，331.4秒awake/wall一致，进程树停止
0.435秒且Python/PDS已退出。516项冻结输入和12份导出重新验证；active_runs已自动清空。
第5轮未布线73624，比基线77319减少4.78%；拥塞图163746比167745减少2.38%，未达到
两者各10%的预定门槛，拒绝完整route，不重试seed或布局参数。诊断进程的exit1来自预定
停止，不是工具错误；日志无E。冲突分数前十网络仅5.52%，问题仍广泛分布。
证据build/video/face_control_reuse_congestion_review_20261103/result.json。

下一项仅隔离测量display_overlay关键点范围比较：综合网表该模块直接含3652个carry
单元，renderer为高冲突组之一。每个点每轴现在同时做coord>=pixel-R与coord<=pixel+R。
推荐改为16位unsigned(coord-(pixel-R))<=2R，一次差值后比较小常数；不改变方框、颜色、
avatar、13拍寄存器或任何接口。数学范围：coord属于[-32768,32767]，pixel属于[0,2047]，
R属于[0,31]，差值属于[-34815,32798]；负数按16位回绕后的最小值30721大于最大2R=62，
所以回绕不会被误收。保留完整16位坐标，不假设CPU已经裁剪。综合能否减少实际carry未知，
必须比较相同边界的原版与候选。其他方案为坐标高位范围分解或改记录存储结构，前者收益
尚未测量，后者影响CDC/租约较广；本轮不并行修改。

- [ ] 新增tb/video/tb_display_point_interval.sv，用数学绝对距离作独立oracle，测试两个轴
      所有signed16值、完整11bit像素边界、全部80点lane及X/Z/禁用情况，先跑原版。
- [ ] 原版通过后只在build/video/face_point_interval_20261103生成候选；R=0/1/2/15/31逐项验证。
- [ ] 边界<=误改为<、差值误缩成13位两个负对照须在真实RTL上失败。
- [ ] 两版定向功能通过后，仅作独立overlay综合资源对比，无映射/布线；原版与候选采用
      相同25ns组件约束。它不替代整机准入，主工程RTL与冻结物理输入保持原样。
- [ ] 若实际资源改善再审查采用；采用后跑历史全输出miter/独立像素oracle、42项组件、
      七段加载真实CPU/NPU/显示整机，再评估同ELF单次整机综合和seed4放置。

以上是已授权的冗余运算优化与证据筛选，无需另加审批。NPU/CPU/约束及外部AC边界不变，
图调度/CPU模型校验迁移仍未闭环，没有跳过任何模型校验，也未扫描或下载板卡。


### 2026-11-03 15:24 点减法资源退化已拒绝，继续高低位范围分解

减法实验15:05完成，Python/PDS均已退出，active_runs为空。重新核验34项输入/报告/
网表哈希，生产display_overlay字节仍等于实验baseline。两版各2782240项独立数学oracle
检查及两个负对照符合预期；独立综合LUT4641→5473（+832），FF1645/APM6不变，直接
carry3688→3848（+160）。台账标记REJECTED_RESOURCE_REGRESSION，未采用候选。
审查：build/video/face_point_interval_20261103/review.json；原始receipt保持原样。
前节的测试、负对照与A/B综合四项已完成，采用门槛失败，因而无需为该候选跑整机或布线。

实际网表解释：80点×2轴，原每轴两比较分别8+7个carry（每单元处理两位，合2400）；
完整差值每轴16个carry（合2560），还要输出位及常数范围解码。这证明合并RTL运算符
不等于减少物理硬件。下一项改用范围性质，而非继续轮换减法形式：POINT_RADIUS合法
范围0..31，区间长度2R<=62，因此最多覆盖两个64坐标块。保留signed16完整坐标，
高10位只与符号扩展后的上下界高位作相等比较，低6位作范围比较。负数到零的跨块仍由
完整二进制高位相等识别，不裁剪、不缩窄坐标、不增加级数或状态。

备选是仅删掉坐标高位比较（不能保留完整signed16语义）或改记录存储结构（涉及CDC/
租约，改动更大）；本轮仅测高低位分解。条件在同一块时为high_eq && low>=lo && low<=hi；
跨块时为(high==lo_high && low>=lo_low)||(high==hi_high && low<=hi_low)。像素侧跨块
判定共享，所有点共用，不修改方框、avatar、13拍输出、CPU/NPU或约束。

- [ ] 在build/video/face_point_bins_20261103冻结baseline和独立测试副本；在既有全signed16/
      全像素边界/80lane/XZ测试上补所有2048像素的区间内部、邻点和64倍数别名，及每位X/Z。
- [ ] 先跑原版R=0/1/2/15/31；之后生成build内候选，同样运行，任何失败立即终止。
- [ ] 同块分支误用OR、遗漏高位匹配两个负对照须被实际RTL测试拒绝。
- [ ] 单次A/B独立综合使用同一25ns组件约束，核验资源与point carry分组。LUT和carry都须
      严格减少、FF/APM不得增加才准入后续评审；不自动修改生产代码、不自动综合整机。
- [ ] 通过后仍须历史全输出miter/像素oracle、组件和七段加载真实CPU/NPU/显示整机及
      源码/ELF一致性，再评估整机综合、seed4放置和有界拥塞采样；不能以组件收益宣称收敛。

继续已授权的结构性冗余优化。物理拥塞、DDR hold、数值max-skew、最终时序和位流未验收；
图调度/模型校验迁移与外部HDMI AC/板测仍待完成。本轮没有活动布线进程。

高低位分解实验于15:25以隐藏进程启动，协调器PID23856；启动后确认vvp子进程PID4720
实际执行baseline_r0_TEST，编译日志无错误。receipt与active_runs均为RUNNING，输入冻结。
证据build/video/face_point_bins_20261103/receipt.json；本次只作隔离测试与组件综合，
不自动采用，不执行映射或布线。长运行交还，由下一次半小时heartbeat核验并接续。


### 2026-11-03 15:55 用户确认真实 CPU/NPU 主脸框首版优先

用户已接受先交付真实检测+主脸框，头像、多框/关键点和模式切换暂缓，图调度及CPU模型
校验迁移不再作为首版前置项。计划 docs/superpowers/plans/2026-11-03-face-first-box.md。
此前高低位点范围实验已结束，34项输入/报告/网表哈希一致、6572096检查与负对照通过，
但LUT4641→4805、carry3688→3696，已拒绝并归档，未改生产overlay。

新box配置由config/face_board_profiles.json显式定义，保留full版本。构建入口
scripts/video/build_pds.py --target triha_face_board --face-profile box --stage synth
使用ENABLE_MINIMAL_BOX=1、ENABLE_AVATAR=0、DEMO_BOX_ONLY=0，真实CPU/NPU不变。
发现旧最小显示参数会同时跳过记录guard，实际组合负对照已复现非法记录被接受；现已
解除耦合，始终保留guard和所有权。CPU既有record builder严格检查x/y/width/height在
800x600内并选择最大面积主脸，因此沿用原有主脸渲染路径，不变更算法或固件。

定向验证PASS：16主脸索引、6373像素用例与13拍逐周期对齐；非法header拒绝、合法RAW
接受、无AVATAR能力时模式2拒绝。旧guard绕过和错误主脸索引两个负对照均失败。
4项profile测试、5项时钟契约检查、41文件NPU准入通过。PDS真实小网表证明参数须用
{name value}对：NAME=value只报警并静默保留默认值；构建新增实际展开参数强制核验。
证据build/video/face_first_box_20261103/focused_review.json。

原四份时钟/CDC/物理约束未编辑。box生成副本精确省略不存在的头像ready/身份两条和
模式键first-stage一条约束，所有有效端点指令与0.2ns余量保留，原始/生成文件均冻结。
后续需审查实际映射端点，不将选择性裁剪误报为全时序通过。

接续协调器build/video/continue_face_first_box_20261103.py：资产离线审查（--model-only，
无COM端口）→42项组件回归→六段加载真实CPU/NPU/采集/主脸框完整两帧→同ELF单次
box综合，核对源码/ROM/SRAM字节及实际模块。任何失败停止并更新真实状态；综合后
审查资源、CDC/复位再进入单次seed4放置。此时尚未有新首版整机/综合/物理通过结论。
半小时heartbeat已更新为首版优先，不回到三模式局部优化。无板卡扫描/下载。

首版验证于15:55启动，协调器PID11548；459项冻结输入复核无变化，实际进程已确认。
权威运行回执build/video/face_first_box_validation_20261103/receipt.json，完成后自动接续
已配置的整机和综合步骤；不自动启动物理布线。


### 2026-11-03 16:32 首版整机发现 RAW 启动遗漏，已修复并接续验证

42项组件回归已通过，目录 build/soc/resource_probe_video_compact_20261103T075602_599797Z，
37项组件输入仍一致，可复用。六段加载整机 face_system-20261103T080128_481032Z
确实完成真实CPU/NPU推理、记录、释放复用及两帧像素，但 modes=001，仅显示RAW。
原整机通用PASS不足以验收首版，外层 modes=010 断言已正确停止综合；此运行标记为
首版功能不通过，保留原始日志/result/receipt及全部哈希证据，无活动物理进程。

根因是face_avatar_init清零mode，而main仅在有模式按键时选择模式；此前“无按键自动
选择BOX”的判断不成立。main现依据能力：无模式键、无头像且支持BOX时主动选择1；
RAW-only及完整三模式默认不变。保留guard、真实CPU/NPU、预检、时钟和约束。
新增生产main启动流程测试（仅替换MMIO/fence并在首次step退出）：旧源码稳定失败
expected=1 actual=0；修改后6项通过，原应用4007项检查与RV32编译链接通过。
整机TB在首次非BOX提交即失败，并要求完整输出模式010；Python入口同时强制帧1/2
各480000像素BOX输出。旧实际RAW日志、缺第二帧、混合模式均被新验收拒绝。

证据 build/video/face_first_box_startup_fix_20261103/review.json；修改前459项冻结输入及
整机输入/输出哈希均核对一致。原冻结目录不修改，新运行使用独立快照。
新协调器 build/video/continue_face_first_box_startup_20261103.py 复用已验证组件证据，
重跑六段加载真实整机，只有两帧主脸框逐像素通过才接续同ELF单次box综合；综合完成
仍须审查后单次seed4放置。本次不宣称首版整机、物理时序或板测通过。
16:32已确认协调器PID13356、整机Python PID26088、ModelSim PID50812/21952实际运行；
回执 build/video/face_first_box_startup_validation_20261103/receipt.json，stage=SYSTEM。


2026-11-03 用户要求不再设置后台任务，已删除 automation-5 半小时heartbeat。改为当前
对话实时核对现有进程/日志并接续；已运行的整机与同ELF综合链继续，禁止重复启动。


### 2026-11-03 16:51 首版真实整机主脸框通过，实时接续综合

FACE_SYSTEM_PASS captures=4 requests=4 results=2 records=2 commits=2 releases=1 reuses=1 full_pixel_frames=2 modes=010 cpu_reads=4296 nativeAW=91016 nativeAR=376746 cycles=48005166

六段模型加载，真实CPU/NPU/采集与两帧各480000像素BOX，释放/复用通过；
输入/输出哈希复核一致，ModelSim Errors=0, Warnings=0。证据
build/soc/face_system-20261103T083156_179658Z/result.json。DDR仍为native存储代理，
不代表物理PHY、HDMI AC或板测通过。同ELF综合已启动：
build/video/pds/20261103T085038_859482Z，实际PDS进程已确认。


### 2026-11-03 17:00 首版综合准入，当前对话启动单次seed4放置

首版综合44529 LUT / 43388 FF / 77.5 DRM，相比完整配置减少4619 LUT、4289 FF、
64 DRM；真实CPU/NPU、guard和1079个像素记录捕获寄存器保留，头像缓存已裁剪。
132项共享源码和同ELF一致，ROM/SRAM文本仅CRLF/LF差异，所有加载字一致。
23组Gray约束、精确复位例外及两级同步拓扑核对通过，精确裁剪3条缺省硬件约束。
证据build/video/face_first_box_synthesis_review_20261103/result.json。综合慢角视频
setup仍-0.461ns、DDR hold仍-1.501ns，不能宣称时序通过；资源下降支持单次布局测量。
直接前台执行既有映射/放置脚本，复用综合DB内已选择的BOX约束，seed4不轮换，
目录build/video/pds/face_first_box_place_20261103；先全角评审再决定布线。


### 2026-11-03 17:09 首版seed4放置全角评审，准入一次固定布局布线

放置慢/快角setup最差+0.553/+1.370ns，全部时钟对setup、recovery、removal、pulse
均零失败。hold慢/快角-0.368/-0.412ns、38/43失败，仅三个DDR PHY时钟对；每对按
两倍快角hold缺口扣除后仍有至少1.363ns慢角setup余量。DDR两个gate sites正确，
23组Gray延迟/skew全部存在于映射约束。证据face_first_box_place_20261103/placement_analysis
和build/video/face_first_box_route_review_20261103/result.json；这仅准入一次布线尝试。
前台执行固定mapped+placed数据库，启用多角优化及hold修复，不重放置、不轮换seed，
不改变时钟或约束。完整布线使用独立监督，不使用第5迭代自动停止的拥塞采样器。
布线后从XML rtr.db提取慢/快角23组数值max-skew，仍须零未布线及全部时序验收。

### 2026-11-03 17:40 首版布线已结束，直接分析现有数据库

固定seed4布局的布线耗时25分32秒，详细布线第712轮达到零未布线。PDS退出码0，
日志明确为“has been routed successfully”，routed DB已保存。外层脚本误要求合并的
“placed and routed”成功句，故记录STOPPED_REVIEW_REQUIRED；该运行已从active_runs
移出。原始输入/日志/回执保留，不修改冻结脚本，也不重复布线。
常规hold修复后仍有STA-3017：3条clock path经SRB的路径未达到200ps hold余量，
最差pixel_clk路径149ps。启动只读诊断build/video/face_first_box_route_diagnostics_20261103，
从已布线DB生成全部慢快角时序、23组数值max-skew及DDR gate sites；未宣称闭合，未生成位流。


### 2026-11-03 21:01 最后一次布线超时，按用户要求停止

CSR 首版固定 seed4 布线触及既定 90 分钟上限，回执耗时 5405.21 秒（含停止清理）。
最后完成第 161 轮，仍有 11933 条未布线网络，近期迭代在约 1.2 万条附近波动。
监督器已停止其 PDS 进程树；独立核查无 PDS/Python/ModelSim/vvp 工程进程，active_runs 为空。
489 项冻结输入逐一 SHA-256 复核一致。没有本轮 routed DB、最终 STA 或新位流；
本次结论是布线未完成并超时，不能将先前版本的时序结果当成本轮验收。

用户“这一版再失败就停止”的条件已触发，工程推进已停止，无下一次运行。
备用像素候选仍未采用，不启动仿真、综合、放置、布线或后台任务，不操作板卡。
先前真实六段模型加载/CPU/NPU/两帧主脸框功能仿真证据保留；最小上板交付未完成。
原始回执/日志不改写；最终核验见
`build/video/pds/face_first_box_csr_route_20261103/final_review.json`。
预整理包仅保留输入，`RELEASE_STATUS.json` 标记未发布。
