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
