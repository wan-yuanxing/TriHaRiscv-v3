# 新头像发布配置资源／后布线时序只读核查

固定提交 `edfa1992f604e5887e04f7cad2d81aeff122dd4b`；发布 `face-photo-20261104`，`profile=avatar`，`ENABLE_AVATAR=1 / ENABLE_MINIMAL_BOX=0 / DEMO_BOX_ONLY=0`。下列数值可用于正文 **2.7、3.3.5**。仅写本目录的报告与摘要，未运行 PDS、仿真、硬件操作，未改 tex、图或 RTL。

**结论：综合总数为 45,716 LUT、41,848 FF、113.5 DRM36K 等效块、64 APM；内部 Slow/Fast 五类检查均通过。最差 setup 为 +0.100 ns，位于输入采集 DMA 的 125 MHz 域，10 级逻辑；旧 BOX 的 MMIO 路径及 12 级描述应整体替换。**

下文 `R:L87591` 表示证据 R 原文件的一基行号。完整路径、SHA256、339 行资源层级、十张时序汇总表及关键路径原文见同目录 `timing-audit.json`；S 为 ZIP07 中 SNR 原成员，行号仍是原报告行号，列摘要见 `snr-resource-excerpt.json`。

## 可直接替换的资源表（2.7及3.3.5总数）

| 统计对象 | LUT | FF | DRM36K等效 | APM | S原始行 |
|---|---:|---:|---:|---:|---:|
| 整机顶层 | 45716 | 41848 | 113.5 | 64 | 121 |
| 应用CPU及本地存储、路由 | 3416 | 2739 | 18.5 | 4 | 284 |
| NPU | 22968 | 17818 | 33.5 | 49 | 318 |
| Video应用引擎 | 9944 | 11920 | 43.5 | 10 | 422 |
| DDR厂商IP | 4701 | 5157 | 0 | 0 | 123 |
| 共享DDR仲裁与桥接 | 1350 | 689 | 4 | 0 | 419 |
| 计算数据跨域桥 | 71 | 153 | 7 | 0 | 407 |
| 视频控制跨域桥 | 61 | 149 | 2.5 | 0 | 413 |

上表依次对应 `triha_face_board_top`、`g_full.impl/face/u_compute/u_cpu`、`.../u_npu`、`g_full.impl/face/u_video`、`g_full.impl/I_ips_ddr_top`、`g_full.impl/face/u_memory`、`.../u_compute_cdc`、`.../u_control_cdc`。CPU行包含本地存储与路由，不是独立CoreMark CPU核的资源口径。模块行均为顶层子集，不应与总数相加。

| 资源 | 器件容量 | 新占用率 | 替换旧BOX占用率 |
|---|---:|---:|---:|
| LUT | 66600 | **68.64%** | 63.86% |
| FF | 133200 | **31.42%** | 32.59% |
| DRM36K | 155 | **73.23%** | 50.00% |
| APM | 240 | **26.67%** | 24.17% |

S:L55–66 的总数／百分比与 Q:L1039–1044 一致。LUT含1123个分布式RAM LUT，逻辑LUT为44593；DRM由70个36K与87个18K原语组成，`70 + 87/2 = 113.5`（S:L21–22、56–63）。旧总数 `42531/43408/77.5/58` 应整体替换；新旧差为 `+3185/-1560/+36/+6`。

补充层级：`face` 为39109/34968/109.5/63（L276）；`u_compute` 为27068/21265/52/53（L281）；紧凑显示子树为6793/9299/42.5/9（L423）；完整头像缓存 `u_renderer/g_avatar.g_full_cache.u_asset` 为560/420/**35**/0（L430）；像素叠加 `u_renderer/u_pixels/g_full_overlay.u_overlay` 为2243/664/**1**/**6**（L433）。这些仍是子集。NPU的33.5 DRM可以保留，Video的7.5 DRM必须改为43.5。资源属于同一**综合**报告，不标为布线后重新统计。

## 可直接替换的时序表（3.3.5）

| 检查项 | Slow (ns) | Fast (ns) | R最差汇总行（Slow／Fast） |
|---|---:|---:|---|
| 建立时间 | **+0.100** | **+2.891** | 75／175 |
| 保持时间 | **+0.187** | **+0.131** | 97／188 |
| 恢复时间 | **+2.066** | **+4.089** | 116／207 |
| 移除时间 | **+0.314** | **+0.206** | 132／223 |
| 最小脉宽 | **+0.035** | **+0.035** | 147、149／238、240 |

十张汇总表的失败端点数和负裕量总和均为0。Fast全局最差setup属于 `ddrphy_sysclk → phy_dq_sysclk_1`；Fast的DDR同域setup为+2.948 ns，不能与全局+2.891混淆。Slow的最差setup/hold/recovery属于DDR用户域；双角removal最差属于计算域；最小脉宽最差属于两个 `phy_dq_clk` 域。

| Slow同域setup | 时钟／周期 | 新裕量 | 替换旧值 | R行 |
|---|---|---:|---:|---:|
| CPU/NPU计算域 | compute_clk，50 MHz／20 ns | **+2.287 ns** | +1.854 | 81 |
| Video/DDR用户域 | ddrphy_sysclk，125 MHz／8 ns | **+0.100 ns** | +0.183 | 75 |
| 输出像素域 | pixel_clk，40 MHz／25 ns | **+9.406 ns** | +7.681 | 68 |

R:L3–15确认PDS 2022.2-SP6.4 build146967、PG2L100H/-6/FBG676、Production model，输入为 `ringr6d/place_route/triha_face_board_top_pnr.adf`，属于最终布线报告。重新解析的9110条有裕量详细路径与资格记录一致；这是 `-max_path 128` 选出的详细记录数量，不是所有可能路径的枚举。另有484条外部未约束记录（Q:L1003–1015），不是484个物理管脚；物理端口数为141。

## 最差setup路径：替换旧MMIO起止点、12级和全部延迟

首条并列最差路径（R:L87591–87687）：

```text
报告Startpoint:
g_full.impl/face/u_video/u_capture/u_input_dma/dma_base_reg[14]/opit_0_inv_AQ_perm/CLK
首个实际数据弧（CLMA_21_894/Q1，tco=0.203 ns）:
g_full.impl/face/u_video/u_capture/u_input_dma/dma_base_reg[12]/opit_0_inv_AQ_perm/Q
Endpoint:
g_full.impl/face/u_video/u_capture/u_input_dma/u_dma/row_base[22]/opit_0_inv_L6QL5Q_perm/CE
```

**必须保留CLK标题为[14]、Q数据弧为[12]的原报告区别**（R:L87591、87625、87627–87628）；不可把标题擅改成Q或把数据位写成[14]。这两种名称来自映射后的同一报告；本次没有读取原生映射数据库解释命名成因。概述建议写“输入采集NCHW DMA的基地址／描述符有效性控制至行基地址寄存器CE”，不要写成显示MMIO或CPU关键路径。RTL关联为NCHW:L78将 `dma_base_reg` 送入 `req_base`，DMA:L57–64、103–110检查描述符并更新 `row_base`；这不是单纯寄存器D端的数据搬运。

| 因素 | 新值 | R原始行 |
|---|---|---|
| 发起／接收域 | ddrphy_sysclk → ddrphy_sysclk，125 MHz，周期8.000 ns | 87604、87655 |
| 组合逻辑级数 | **10**（不是流水线级数） | 87651 |
| 逻辑／布线延迟 | **1.734／5.335 ns** | 87652 |
| 总数据路径延迟 | **7.069 ns**；逻辑含0.203 ns clock-to-Q，组合弧合计1.531 ns | 87627、87629–87652 |
| 发射／捕获时钟插入延迟 | **5.571／4.121 ns** | 87597–87598 |
| 时钟悲观量移除CPR | **+1.195 ns** | 87599、87677 |
| 有效时钟偏差 | **−0.255 ns** | 87596 |
| uncertainty／setup time | **0.350／0.226 ns** | 87678、87680 |
| 数据到达／要求时间 | **12.640／12.740 ns** | 87684–87685 |
| 建立裕量 | **+0.100 ns** | 87687 |

```text
数据到达 = 0 + 5.571 + 1.734 + 5.335                  = 12.640 ns
数据要求 = 8 + 4.121 + 1.195 - 0.350 - 0.226          = 12.740 ns
有效偏差 = 4.121 - 5.571 + 1.195                      = -0.255 ns
setup裕量 = 12.740 - 12.640                           = +0.100 ns
          = 8 - 7.069 - 0.255 - 0.350 - 0.226          = +0.100 ns
布线占比 = 5.335 / 7.069                              = 75.470%（正文75.47%）
```

10级器件弧依次为 `N144_3_8/COUT、N144_3_10/Y、N181_mux32_525、526、548、568、12、7、N1244、N1321`（R:L87629–87647，完整后缀见JSON原文）。F:L296–297显式设置0.200 ns，但该路径工具实际扣除0.350 ns，计算须用后者；报告未分解额外0.150 ns的来源。另有终止于 `row_base[24]、[26]、[28]` CE的三条并列+0.100 ns路径（R:L87692–87990）。不得将首条称为唯一最差路径。

## Gray CDC界限与范围

**23组、116位、928次源／目的时钟观测；全组双角、early/late覆盖成立。最大保守到达偏差界由旧4.233改为3.479 ns。** 本次从R重新核对232条Gray数据路径，均为0级组合逻辑；从CR重新计算全部928次时钟观测，与C及Q完全一致。

最差组为 `face/u_compute_cdc/u_ar_fifo/wr_gray → wr_gray_rd_sync1`，3位，compute_clk → ddrphy_sysclk，约束6.000 ns（CDC:L55–56；C:L324–367）。其Slow计算为：

```text
源时钟跨度界 = 4.991 - 4.225 + 0.002 = 0.768 ns
目的时钟跨度界 = 5.515 - 4.121 + 0.002 = 1.396 ns
数据路径保守界 = max(6.000 - 每位setup slack + 0.002) = 1.315 ns
总到达偏差界 = 0.768 + 1.315 + 1.396 = 3.479 ns < 6.000 ns
余量 = 2.521 ns；该组Fast界为2.483 ns。
```

0.002 ns为文本舍入保守项（FT:L203、GC:L61–65）。这是保守上界，不是工具直接报告的实际skew。`native_max_skew_report=false`（C:L1013）；R的“所有约束满足”本身不能替代此独立检查。原资格记录提供映射位覆盖与物理站点校验，本次没有取回／重算sites PCF及ADF，因此不将此次复核升级为完整新CDC结构、MTBF或外部I/O签核。

## 正文替换与证据限定

- **2.7**：替换资源表与四项占用率；最差路径描述改为上述DMA控制路径。NPU的33.5 DRM及50/125/40 MHz时钟可保留。资源表出处从旧 `face_box_report_20261103` 改指本次头像发布证据，不沿用旧BOX归档作新数值来源。
- **3.3.5**：替换总资源、五类双角时序、Slow三域、Gray最大界、关键路径起止点／10级／延迟计算／75.47%占比；不能仅把+0.183改成+0.100。
- 保留通过项与范围：`internal_timing_met=true`、`routed_internal_timing_closed=true`、`cdc_timing_met=true`；资格记录同时保留 `timing_closed=false`、`physical_board=false`、`external_io_timing_verified=false`（Q:L3–8、2175–2178）。后续实板功能通过由A独立记录，不意味着外部HDMI或DDR板级AC全面签核；板级FPS未测。本次不重跑这些验证。
- 路由receipt的scope仍含历史“BOX”字样（V:L10），但基底为 `face_photo_ring_50_map_20261104`，Q明确绑定avatar参数和新位流；报告保留这一元数据措辞，配置判定以参数、哈希链为准。
- **源码身份无未解释差异**：340项快照均与固定Git提交逐字节一致；其中338项与发布manifest直接一致。`review_face_route.py`及`test_face_route_audit.py`只是Git LF与Windows CRLF字节表示不同，逐字节LF→CRLF后SHA256与manifest精确相等，未改变文本内容。JSON记录两种哈希，并关联主任务的 `source-identity.json`。不能把这两项写成未解释源码不一致。
- ZIP13全文件SHA及使用的本地资格／RTR成员SHA已重新核对。SNR通过GitHub范围读取定位于ZIP07，验证解压后成员SHA及CRC；只读取ZIP07–12目录尾部及所需成员，共约0.45 MiB额外ZIP字节，未下载额外整包，**未声称验证ZIP07全包SHA**。ADF哈希仅核对资格记录之间的一致引用，本次未重哈希该数据库。

## 原始证据定位与SHA256

SNR成员为 `build/video/pds/face_photo_ring_50_map_20261104/synthesize/triha_face_board_top.snr`。R和CR分别为 `ringrev6d/timing/report_timing/triha_face_board_top.rtr`、`ringclk6d/report_timing/triha_face_board_top.rtr`，均在 `build/technical-report-avatar-edfa199/evidence/build/video/` 下。M/A在固定快照 `source/releases/face-photo-20261104/`；Q/V/C分别为对应目录的 `result.json`。源码证据别名及绝对路径全部见JSON。

| 证据 | 字节数 | SHA256 |
|---|---:|---|
| M | 505954 | `98bcd6f51b1a9efe5ae291bd7903306ae3fa2ca1600d02be645a033d18d4dffb` |
| A | 3810 | `64dd7fa19522b8a1a8929dcb39263fabd8071aca54b654476ae25fa9757ae9f7` |
| Q | 113983 | `004f50053d737ac28694048d6c9f4070c601113dbe06bd1a9d796141c92386d5` |
| V | 129811 | `3d1b7f437b451b259a3128231f5c6a7e21fbd00a590b94eb0d9eea0c40a3d1fe` |
| R | 65285797 | `f2e4de0d6047c77d1eab0c332562ef681110ba1c306e5e70f437754805e7f115` |
| C | 36417 | `68e44d4a2ca5045368e4d6319b5b1f7b96a6889a667c4bb93b991e0c791b9220` |
| CR | 7732742 | `c3c0b6f19a33c76a114b35a0ee7b3bcf829eaaef17f97d8be8f27d9579db3ade` |
| S | 1233731 | `4630de740388975958b7ab298f048c6c233658aa74d0f6e147326553d6d21848` |

ZIP13 SHA256：`72ca56a54c69747b52ccb796108910402cff129d3fc2faefa8b4d86e2716162b`。绑定位流SHA256：`c7875faa32568d9b8e1d16d4b450c78e4cec6586dff94e411d4c875d1d61c0fd`；绑定最终ADF SHA256（记录值）：`9e35e6e6fe6a2064a13e649516709d8918cbd2f8dc58499049ada619a8f101a6`。
