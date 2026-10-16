# Video 参考来源与适配决策

核对日期：2026-10-16。机器可检查来源为 `fpga/pg2l100h/ip/video_reference_manifest.json`。仓库仅保存清单与工程适配，原始厂商字节保留在板卡包及忽略版本控制的构建目录。

## 已核验的参考

| 来源 | 包 SHA256 | 本批验证 |
|---|---|---|
| `2_Demo/4_12_HDMI_IN_DDR3_HDMI_OUT.rar` | `ff55b502f52a8467bae6ec6dcc025f1e04b0c316b1cda6af28cf54cf3512a05b` | 18 个选中文件逐字节/哈希一致；DDR IDF 引用的 82 个文件在包内存在 |
| `2_Demo/2_9_ddr3_test.rar` | `2d5a28f5a32e694a88e91f80acdfb117ba0bf5c41a64b5f7c3726ae67c7bb6cf` | 5 个选中 DDR wrapper/IDF/PHY/FDC/RCF 文件一致 |

清单引用旧工程的 `video/hdmi/vendor_sources.json` 与 `ddr/hmic_contract.json` 并记录其哈希。完整参考文件名和包内路径均在机器清单中；不维护第二份人工哈希表。

## 复用安排

| 内容 | 决策 | 适配条件 |
|---|---|---|
| `ms7210_ctl.v`、`iic_dri.v` | 已复用，TX-only wrapper 已板测 | 独立初始化、失败可观测、不等待 RX |
| `ms7200_ctl.v` | 已复用，RX wrapper 数字验证和本版板测通过 | 替换固定 EDID；下降沿采样实测全部同步/porch 合格，60 秒串口记录无坏帧 |
| `ms72xx_ctl.v` | 参考共享 I²C 顺序，不直接用作首版彩条控制 | TX 的 rstn 依赖 init_over_rx，会等待输入频率检测 |
| `sync_vg.v` | 用作时序交叉参考 | 本工程已有小型可测试固定时序，按有效区原点定义接口 |
| `cfg_pll.idf` | 27 MHz → 10 MHz，原生生成运行已验证 | 集成时再核对复位与时钟约束 |
| `pll.idf` | 配置基础 | 旧配置为 148.5 MHz，必须重新配置/生成 40 MHz |
| `ddr3_test` IP | 官方 IP 复用 | 完整依赖 staging、native 差异、约束层次、BIST/真实校准 |
| 旧 `axi128_hmic256.sv` 和 CDC | 通用桥候选，本批未迁入 | 重跑并适配总工程子集、吞吐、跨主端 RAW/复位 |
| 旧视频应用/帧缓存/固件 | 不整包迁入 | 旧地址、RGB565、1080p、双缓冲/快照和应用逻辑与 v0.6 不兼容 |

## 已发现的具体差异

1. 官方 HDMI top 将 RGB888 截成 RGB565，输出补零；本工程必须保留 24 bit 像素。
2. 官方时序与像素 PLL 为 1920×1080/148.5 MHz；本工程只采用 800×600/40 MHz。
3. `ms72xx_ctl` 的 TX 复位由 RX 初始化完成控制；RX 完成依赖输入频率变化。首个彩条目标使用独立 TX 配置，不被未接视频源阻塞。
4. `ms7200_ctl` 的 EDID 基础块首选详细时序为 3840×2160/297 MHz，基础和扩展块校验和有效；不能把“EDID 有效”当作已协商 800×600。后续明确设置源模式或适配并验证 EDID。
5. 原例程 TX 使用 10 MHz 配置时钟，I²C 400 kHz、16 bit 寄存器地址、8 bit 数据；8 bit 地址字节 RX/TX 为 `0x56/0xB2`（对应 7 bit `0x2B/0x59`）。最终按实际芯片核对。
6. FMC 示例遗留 Tcl 指向 PGL50H/FBG484 与旧绝对路径，不能直接执行。HDMI 示例 PDS 的目标为 Logos2/PG2L100H/FBG676。
7. DDR 为 HMIC 非标准 AXI native；没有 WVALID、RREADY、B 通道。其 125 MHz 参考与 PHY 约束不得混用为 27 MHz 主时钟。
8. 参考 FDC/RCF 包含特定实例层次与来源问题，需要独立审核，不整体导入旧 warning 白名单。

## 复用边界

`prepare_reference.py` 只提取选中的 18/5 个文件。新增 `gen_ddr.py` 按 `video_ddr_manifest.json` 从已安装的 PDS 2022.2-SP6.4 锁定 71 个保护源，运行原生 IP 生成器，再核对全部保护源、两个原参考 wrapper 和固定 slice 输出哈希及精确 74 文件集合。每次生成独立目录，通用生成 FDC 从不作为本板管脚依据。

DDR top 保留 `I_ips_ddr_top` 层次、原时钟/PHY site 和字节一致的 RCF。71 个 DDR bit-port 属性逐项匹配官方 HDMI FDC；D18 独立时钟按实际 27 MHz，125 MHz N3/N2 参考采用 standalone 的 SSTL15D_I。参考中的 HSTL/SSTL 差异显式记录，未自行改写内存数据脚电气属性。原 standalone 的 N3/D18 重复 freeclk 和 J8/L8 UART 约束未带入。

`.gitattributes` 对此单个 DDR RCF 禁用文本换行转换，保留原始 CRLF 字节和来源哈希；其他工程文本沿用仓库 LF 规则。

MS7200 原控制器保持字节一致，通过 wrapper 替换 EDID 数据、观察 ACK/STOP、处理启动等待和冷启动频率事件。实测前不推测未公开寄存器含义；资料无完整输出 setup/hold，外部 AC 签核仍待补齐。生成 IP、副本与厂商库始终进入 build。

原始审计可查 `build/video/audit/native_smoke_20261016_145614/reference_inventory.json`；选中提取结果可用 `prepare_reference.py` 重新生成和校验。厂商来源保持原 notices 和分发条件。
