# 真实 HDMI 单帧 raw 采集验证

日期2026-10-16，基线 `598a064`，实施设计见 `docs/superpowers/specs/2026-10-16-video-hdmi-raw-capture-design.md`。本批把真实不可背压像素送入已板测packer/DMA/桥，不把前一批合成图样物理结果改称HDMI帧采集。

## 完成条件和范围

默认每次KEY0协调复位采一帧，预留测试区 `[0x87300000,0x87500000)`，raw为800×600×3=1,440,000字节、2400B行步长。源/目的时钟不假设同相；源只在合法帧首接纳完整帧，输出像素和good EOF；写DMA完整成功后独立读DDR做CRC。

成功需480000个像素、1440000个读回有效字节、源CRC等于DDR CRC、无overflow及任何错误、DDR初始化/PLL健康、当前RX模式和TX初始化正常。CRC32 ISO-HDLC字节次序为递增内存地址R/G/B；物理CRC比较有碰撞的固有限制，数字回归另以独立byte-memory oracle检查全部有效字节及padding/红区。

本地彩条仍由独立输出时序生成，不能把看到彩条当作采集内容已经显示。当前只验raw单平面；preview/input、三分支CAPTURE_DONE、显示读DMA、CPU fabric、多主争用和连续fps均不在此目标中。外部AC与厂商训练仿真仍分别记录。

## 组件、复位和CDC

`video_async_fifo.sv` 使用注册Gray指针、两级同步、同步读RAM和受阻稳定的输出寄存器；默认RAM2048×48bit，输出寄存器额外持一字。RAM满时不覆盖旧数据。水位是含指针同步延迟的RAM保守占用，不计输出寄存器，不用占用平均值证明最坏DDR等待。

`video_capture_ingress.sv` 接收core同步arm后在下一合格帧首包含首像素；逐像素检查x/y/count，下一frame_end才发布EOF元数据。不可背压像素遇full使整帧错误保持；EOF本身可等待空间。坐标/模式/readiness错误、cancel均停止源，不在协调复位前再采一帧。

入口支持FIFO地址宽1..11、宽/高1..2048，其余参数明确拒绝。两域复位只受KEY0/启动支配，本域同步释放；HDMI PLL/配置丢失不能单独清FIFO。RAM enable由本域run寄存器控制，避免原始异步复位进入RAM使能路径。

联合目标沿用 `I_ips_ddr_top`、core `telemetry` 与 `bist` 实例层次和原DDR FDC/RCF；补充HDMI FDC保持59个新增管脚，139/139 bit-port静态一致，无位置冲突。写Gray到core的delay/skew为20ns，读Gray到pixel为6ns；arm/cancel和故障的第一同步级单独例外。现有冻结快照bundle仍分别80ns/150ns，后续级间时序保留。

## 已取得的入口数字证据

- 实现：`build/video/hdmi-ingress-agent/verification.json`、`normal_verification.json`；800×600完整480000个PIX和EOF，独立CRC `75dbc668`，该测试配置RAM峰值20。
- 规格：`build/video/hdmi-ingress-spec-review/results.json`，独立29例；`negative-parameters.json` 7例。arm刚同步完成与帧首同拍漏像素的边界问题经RED/GREEN修复；满/空/回卷、占用、EOF满等待、源停钟/恢复、cancel、坏帧、协调reset及保持历史完成分别覆盖。
- 质量：`build/video/hdmi-ingress-quality/summary.json`，16组严格位宽/-Wall配置、29例独立回归及5个测试突变均通过，零编译警告。所有结论绑定当前组件哈希。
- 静态物理审计：`build/video/hdmi-constraints-audit/REPORT.md`；FIFO独立综合3 DRM、66 LUT、101寄存器、0 latch，不能代替联合布线时序或板测。
- 持久入口回归：`build/video/regression/20261016T130242_418988Z` 通过，含不同速比/相位、9×1与小FIFO EOF-full、13×3与小FIFO overflow路径；引擎、联合目标及最终全回归另记。

引擎实现证据 `build/video/hdmi-engine-agent/proof-96728bbc.json` 与独立规格 `build/video/hdmi-engine-spec-review/result.json` 已通过：13×3、16×3、1367×3各24个生产异常case，完整800×600为480000像素、1440000字节、90000个AXI128拍，CRC `d1ec37c8`。独立直接FIFO/native harness另35例和10组参数检查，核对读覆盖、两种EOF/DMA完成顺序、CRC错误、各通道受阻故障及复位。

规格审查复现两处X状态误判：未知EOF CRC、未知DMA tag曾被普通不等比较误当成功，均已用严格比较修复并RED/GREEN复核。PDS提前检查发现故障检测经DMA abort/READY回到自身的组合环，改为独立packet-present条件后消除；前次产物保持失败，不得下载。

引擎质量审查 `build/video/hdmi-engine-quality/result.json` 另以8轮严格位宽/-Wall验证102个场景及参数探针，零编译警告；4个隔离突变均被拒绝。补充覆盖16个读回字节位置、最终字节与FINISH故障优先级、旧PASS撤销、受阻AR稳定/完整R排空，以及packer满且AW阻塞时的非法输入包。引擎实现提交为 `27960cb`。

联合顶层另将core/pixel本地复位直接取自同步释放寄存器Q（这些寄存器仍由全局reset异步清零），使原始free-clock启动网只到复位C/P而不进packer/FIFO数据使能；补充FDC显式覆盖嵌套FIFO复位端点，仍不切掉本地域释放的recovery/removal。`build/video/regression/20261016T134729_783323Z` 联合板级数字替身通过：实际UART、无初始化/core、HDMI失锁不清FIFO、KEY0重采、DDR停钟/失锁撤销旧PASS。该TB显式强制前端候选事件，真实RX光栅/I²C由独立既有套件覆盖。

## UART type5

TRV1/37字节/115200 8N1，小端，前36字节逐字节XOR。32字节payload为 `<4B7I>`：

| Payload | 内容 |
|---|---|
| byte0 | 类型5 |
| byte1 | flags bit0..7=DDRinit、busy、done、error、allDDRPLL、RXmodegood、TXdone、overflow |
| byte2/3 | phase（成功A5）/首错code |
| bytes4..7 | captured_pixels |
| bytes8..11 | checked_bytes |
| bytes12..15 /16..19 | source_crc / ddr_crc |
| bytes20..23 | frame_tag，默认1 |
| bytes24..27 | FIFO RAM保守最大占用 |
| bytes28..31 | 独立heartbeat |

host要求两包heartbeat不同且完整条件满足，置 `physical_hdmi_raw_capture_verified`；旧type4合成图样包不具有该资格。输入当前模式与历史帧数据结果区分报告，board watchdog撤销DDR/PLL/停core后的旧PASS。每秒状态包不等于每秒又采了一帧。

引擎首错码01=init丢失、02=overflow、03=源fault、04=PIX/包、05=EOF、06=DMA、07=总任务超时、08=几何/地址、09=读通道元数据、0A=状态、0B=计数/CRC；桥故障为80或桥码。独立板级E0/E1/E2/E3/E4/E5/E6分别为init超时、DDR init/PLL丢失、PHY失败、align、core快照停滞、HDMI初始化错误、HDMI PLL丢失。

## 原生命令与当前物理状态

```powershell
python scripts/video/run.py --suite capture_ingress
python scripts/video/run.py --suite capture_engine
python scripts/video/run.py --suite hdmi_capture_board
python scripts/video/run.py --suite all
python scripts/video/build_pds.py --target video_hdmi_capture --stage bitstream
python scripts/video/package_board.py --target video_hdmi_capture
python scripts/video/program_board.py --target video_hdmi_capture --start-server
python scripts/video/read_board.py --port COM12 --seconds 12
```

真实HDMI联合目标正在实施，尚未产生本批物理采集通过结论。联合顶层规格及质量审查已通过，记录为 `build/video/hdmi-board-spec-review/result.json`、`seed-addendum.json` 和 `build/video/hdmi-board-quality/result.json`。质量审查以真实引脚采样/光栅/计时/模式门控走完4个1056×628帧，独立核对1,440,000个DDR字节及CRC；仅强制HDMI初始化健康，DDR仍为数字替身。下述桥等价修改另以独立增量审查绑定新依赖哈希。

`build/video/pds/20261016T134740_921577Z` 已消除组合环及复位数据使能路径，全部hold/recovery/removal通过，但slow setup为−0.541ns，另有core到PHY的−0.238ns路径。仅优化固定种子1/2/3的 `build/video/pds/20261016T135851_729836Z` 最佳种子2仍有42个setup端点、WNS−0.209ns；core到PHY已分别+0.670/+0.871ns，其余7项多角检查通过。这两份失败产物均禁止下载。

剩余关键路径位于bridge的COLLECT写缓存使能；通用poisoned把互斥读回阶段的256bit比较带入该路径。本次只为缓存写入新增阶段等价的collect_poisoned，保持通用错误锁存/响应不变。新桥哈希 `03081f944fa934b2100741e883867dba9eaa4e492f13eb4e39d019c985eb0950`，原桥 `c180dbce…`。原191例、23,712组四态及65例旧/新逐周期公共输出对比通过；独立规格审查另52,384组四态通过，含reset、legal、外部控制X/Z及所有9组缓存内容。未知WVALID可能使原始guard值不同，但外层if不执行，实际cache CE及状态语义一致。记录为 `build/video/hdmi-timing-guard-review/applied_result.json` 和 `build/video/hdmi-constraints-audit/collect-guard-spec/result.json`。引擎和DMA保持不变。

桥修改后的 `build/video/pds/20261016T141414_953504Z` 最佳种子1仍有一个setup端点−0.030ns，路径为FIFO包合法性经descriptor清零使能进入DMA字节计数器；另两个种子为−0.071/−0.167ns。全部hold/recovery/removal仍通过，失败产物禁止下载。审计确认单独移动计数器always块仍保留合法清零依赖，故保持RTL不变，构建脚本改为固定种子4..9六组串行搜索和该目标3600秒超时，原约束不变。最终脚本规格/质量补充审查分别为 `build/video/hdmi-board-spec-review/seed4-timeout-addendum.json` 和 `build/video/hdmi-recipe-quality/result.json`。

`build/video/pds/20261016T144157_393343Z` 最佳种子6仍有5个setup端点、WNS−0.066ns，全部其余检查与CDC约束通过；该产物也禁止下载。最差路径为bridge的beats/RLAST经读回元数据故障进入packer/DMA控制。源端弹性寄存器不能切断该路径，因此未采用。

第二处阶段等价修改把读回元数据故障从inactive写控制中拆出：`transfer_fault_now` 保留所有原有非读回故障，`fault_now` 按原优先级重新插入0x09（高于0x07总任务超时，低于其余先行故障）。只有packer.pixel_valid及DMA.abort使用transfer_stopping；状态推进、描述符与对外诊断继续用完整stopping。READ_*只能在DMA退休后进入，此时DMA已IDLE且不可重新获得写事务。实现提交 `86aed0d`，引擎哈希 `f556f95048044d8aa15a709bd061d2e502f4b80593b17fd4ccadc1273f2f7451`。

`build/video/hdmi-control-timing/result.json` 记录前后65例逐周期与76,073组四态对比；独立规格 `build/video/hdmi-constraints-audit/engine-transfer-spec/result.json` 另58,432组检查；独立质量 `build/video/hdmi-control-quality/result.json` 另23,040组控制、65例逐周期及131,534个读回阶段所有权/状态采样，均通过且零编译警告。诊断故障仍检查严格RID/RESP/LAST与原首错优先级。新网表中读回元数据到packer D/CE端点由150变为0，通用诊断检查仍保留。

最终PDS `build/video/pds/20261016T152024_020998Z` 通过并选择种子7，125MHz slow setup WNS+0.233ns，fast+3.096ns；hold+0.137/+0.102ns、recovery+3.454/+4.966ns、removal+0.278/+0.187ns，全部失败端点为0。资源12043 LUT、12174寄存器、4 DRM。约束和125MHz目标均未放宽。位流SHA256 `2e01feb8e69d3ce4c832650daebf9cea3b64e03b2ad80eb7411c2f9c52e1e70b`，下载包 `build/video/releases/video_hdmi_capture_2e01feb8e69d`。

最终完整回归 `build/video/regression/20261016T152024_025404Z` 的18个套件通过，94个输入哈希均匹配；38项Python测试中37通过、1项Windows符号链接权限跳过。新引擎完整800×600仍为480000像素、1440000字节及CRC d1ec37c8。

独立物理时序审核 `build/video/hdmi-constraints-audit/interim-20261016T152024_020998Z/result.json` 通过：56个Gray位保留实际20/6/20ns约束、本地同步级setup/hold及80/150ns快照均通过，复位无D/CE/RAM接点，139个引脚无冲突。PDS不输出独立max-skew断言表，报告明确区分逐位delay及由数据到达时间计算的spread，不把它们伪称工具直接skew断言。外部AC及厂商训练仿真均未签核。

较早全回归因构建脚本/桥输入在运行中改变而失效，不作为最终通过证据。`143005_472008Z` 构建和 `143025_874418Z` 回归因工具会话重置中断，保留interruption.json及局部日志，没有最终通过结论。

当前开发板保持上一批RX彩条镜像；本批当前脚本对应的恢复构建为 `build/video/pds/20261016T143015_641311Z`，已通过内部时序并打包为 `build/video/releases/video_rx_board_26d25f7dd060`，尚未重新下载。联合目标尚未Program/Verify：23:39和23:41下载前串口复查发现当前输入不合格，像素频率约19.84MHz且场时序未锁定；已请求用户唤醒源电脑并核对活动信号800×600、60.32Hz，尚待回复。JTAG预检已识别PG2L100H/0x00602899。恢复合法输入后才下载，继续实际CRC、60秒状态、KEY0新帧及恢复RX验收；不能将本次数字/内部时序通过当作物理采帧通过。上板前摘要为 `evidence/hdmi_raw_capture_preboard.json`。
