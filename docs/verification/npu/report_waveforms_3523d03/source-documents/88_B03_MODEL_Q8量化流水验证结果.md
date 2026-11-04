# B03 MODEL Q8 量化流水验证结果

版本：v0.1；日期：2026-10-28（北京时间）。对应[[87_B03_MODEL_Q8量化流水接口与单元验收规格]]及[[86_B03真实首层MODEL分块执行规格]]的S1第一项。**Q8单元真实APM功能仿真与独立波形回放通过**；16×16卷积阵列、实际P/O缓存、程序FETCH、DDR和完整首层尚未接入，S1整体仍未完成。

## 1. 本轮实现

新增`rtl/platform/b03_model_q8.v`，固定8lane，每lane4个冻结scalar乘法leaf。实际ModelSim层级包含32个`GTP_APM_E2`；没有用行为乘法代替原语，也没有修改冻结`b03_mul25x18_loan.v`。实现33bit bias检查、四部分积的I64求和、RNE/U8限幅、每lane错误和完整128bit标签。

输入受理与输出退休均须满足共同`advance`。数据及控制经历E0 bias、E1/E2原语、E3部分积、E4乘积、E5商余数、E6舍入、E7输出，共8个包含受理沿；输出展示后在下一个允许推进沿退休。run_ce=0时，即使out_valid/out_ready均1也不消费。这是内部共同CE口，后续连接P/O须一起推进，不能套用普通DDR ready/valid的消费定义。

缺失leaf有效或错误mode/epoch按独立预期token返回error4，没有以“所有leaf都有效”作为继续运行条件。mask=0的lane及前门已非法的lane按规定忽略此返回故障，所有错误lane的product/rounded/value均0。未来执行器遇任一活动lane错误必须隔离任务，不能把该0作为合法输出写入并发布成功。

## 2. 正式运行与覆盖

正式目录`build/platform/b03_model_q8_v1`，报告原字节归档为`yunet/baseline/b03_model_q8_validation_v1.json`，SHA256：

`c09c911d854805681387f6ee2446c51a68204ed46aa0b20bea7431358cc02d4d`

| 项目 | 实际结果 |
|---|---:|
| ModelSim真实进程 | 退出0，无超时，墙钟12.630秒 |
| console/transcript全量诊断 | 均0错误/0警告；另核各自两条summary均0/0 |
| 原语层级 | 32个唯一APM实例，真实加载GRS/APM/leaf/Q8/TB |
| TB检查周期 | 22724；共同推进14842次 |
| token账 | 13871受理 = 13847退休 + 24清空，最终pending0 |
| 算术向量 | 105321个有效lane，按13166组打包 |
| 新bias/非法参数/优先级边界 | 43个输入lane，6组 |
| mask | 256种全部覆盖；包括空mask和无效lane垃圾参数 |
| 真实首层量化输入 | 4组输入×3个16M tile×16Co = 3072lane，384组 |
| 连续吞吐 | 最长256组连续受理、248组连续退休；共同推进II=1组 |
| 输出保持 | 7840次完整tuple保持检查；其中1873次CE0且valid/ready均1不消费 |
| 输出反压 | 5967个周期；无输出时ready0仍允许推进8次 |
| 清空 | clear/reset各覆盖8个在途位置；另一次满流水清空8组，总清空24组 |
| 原语故障 | 7个有效返回故障、2个按mask/前门错误忽略的故障；额外有效脉冲不产生新组 |
| 已退休lane错误计数 | bias溢出4、M非法6、shift非法2、leaf异常7 |

`lane_checks=173520`包含输出保持期间的重复比较，不是173520个不同输入。算术向量、真实向量、控制向量及mask向量分别计数，不把它们简单相加宣称为独立图像数。四组真实输入沿用资产实际名称`zero`、`full255`、`pattern`、`calibration_image_000`；第86篇black/white是零图/满255图的描述性名称。

真实样本取每组空间起点0、12800、25584的16M切片。主机独立从原输入及Co16权重计算**未加bias的完整K部分和**，再送实际Q8；Q8输出逐lane核对冻结tensor184。通过说明硬件量化与真实模型数值相符，**不表示FPGA已完成卷积或完整首层**。

## 3. 独立公开波形回放

新增`yunet/python/replay_b03_model_q8_wave.py`，读取正式VCD中的实际输入总线，按受理沿独立使用Python整数/Fraction构造期望；不读取bench的expected总线或期望结果文件。另核真实leaf故障端点、8级token位置、整组标签、busy、保持、清空和退休账。

报告`build/platform/b03_model_q8_wave_replay_v1/b03_model_q8_public_replay_v1.json`原字节归档到baseline，SHA256：

`50defcc0dc4422094cf0fb5ce59b1ae07257d7b4f02f44fbeb6ff091e47b2dc3`

回放的13871/13847/24、7840次保持、1873次CE0未消费、5967次反压和7+2故障，与正式bench及日志回放一致。VCD有22725个实际时钟上升沿，比TB的22724次tick多一个初始化上升沿；这不是额外任务或丢失周期。

## 4. 实际仿真图

以下四图均来自本次正式VCD和原始日志，PNG及manifest绑定源码/向量/厂商依赖和报告SHA。图中group_in/group_out显示128bit tag的组号字段，不代表只检查了32bit身份；实际比较为完整128bit。

![Q8实际八级流水与连续吞吐](仿真截图/b03_model_q8_v1/01_actual_Q8_pipeline_and_II.png)

第一组从接受到E7展示经历8个包含沿，后续连续每推进拍一组；退休计数比展示晚一个允许沿。仿真的100MHz理想时钟不等于实际布局布线STA签核。

![真实首层量化输入与负数RNE](仿真截图/b03_model_q8_v1/02_actual_Q8_model_inputs_and_RNE.png)

上部取真实校准图的量化样本，输入/输出组号明确区分流水前后。大乘积只在图中文字中以科学计数法缩略，正式比较仍是完整I64。下部显示−9经shift1舍入为−4后限幅0，不能仅看最后的0判断负数舍入正确。

![Q8共同CE和输出反压](仿真截图/b03_model_q8_v1/03_actual_Q8_CE_and_backpressure.png)

CE暂停与输出反压时完整tuple保持，恢复推进后受理/退休继续；run_ce0且out_ready1不重复消费。

![Q8返回故障和复位恢复](仿真截图/b03_model_q8_v1/04_actual_Q8_faults_and_reset.png)

上部抑制一个真实leaf valid，预期组仍按原流水位置返回error4，邻组正常。下部为CE暂停期间reset清空旧输出，之后新组重新运行。clear和reset所有8个位置的覆盖以完整日志/独立回放为准，图仅选择实际窗口。

## 5. 开发插曲与证据保存

`b03_model_q8_dev01`中RTL及bench完成，但runner把结构化`error=000000`误识别为工具ERROR，并且层级计数未兼容行尾原语类型；该尝试保留为失败。修正诊断词必须有空白/冒号等分隔及层级解析后，`dev02`完整日志0E/0W，但公开FLUSH事件同时含原pending及追加pending，报告构造发生字段重名TypeError；改为queue_pending。两次没有改变RTL或放宽算术判定。

`dev03`与fresh正式v1通过；旧目录、日志、输入快照保持。独立VCD回放另有开发目录，未改写正式raw。绘图dev01曾有底部标签重叠和窗口过宽；正式版调整布局、组号显示及实际窗口后，四张图逐张目视核查。未伪造界面截图。

516项旧冻结源、正式owned源/快照、两份厂商模型、向量及源资产运行前后SHA一致。主要新源码SHA：

| 文件 | SHA256 |
|---|---|
| b03_model_q8.v | `1ebc2cec224227332eb69c3ba4dc592e56d9ed662a2ec11346a1274de24f302b` |
| tb_b03_model_q8.sv | `05ac962dc3a7b19df2cc5ab41bd3dd2521efaef568463a30c51724aef24d6d1a` |
| run_b03_model_q8_checks.py | `d653f1dc55ca156c258a74fc73bcc149cbf90b63b8197482decdf05b8c662786` |
| replay_b03_model_q8_wave.py | `0cde7b2a0c2f89fc07941445652f0acf102b67c969c8c58d50b5f50aab98f113` |

## 6. 复现入口与下一步

在工程根目录执行，输出目录须不存在，旧正式目录不可覆盖：

```powershell
.\jiaoben\zgtc\run_b03_model_q8_checks.ps1 -OutputDir build/platform/b03_model_q8_recheck01
& 'D:\anaconda3\envs\npu-cifar\python.exe' -X utf8 yunet/python/replay_b03_model_q8_wave.py --vcd build/platform/b03_model_q8_recheck01/simulation/trace.vcd --validation-report build/platform/b03_model_q8_recheck01/b03_model_q8_validation_v1.json --output-dir build/platform/b03_model_q8_replay_recheck01
.\jiaoben\zgtc\render_b03_model_q8_wave.ps1 -BuildDir build/platform/b03_model_q8_recheck01 -OutputDir build/platform/b03_model_q8_figures_recheck01 -Development
```

下一项继续S1：新增通用16M×16Co的128 SIMD APM乘积/INT32累加阵列，实际A/B供数、K16+11的P写入/清寄存/重载，最终P→Q8→O连接及尾mask/CE/错误隔离。保持完整K后一次bias/RNE，不用bench写计算结果冒充P存取。之后才是S2程序FETCH、ROI gather及DDR取存，S3代理完整首层。

本轮没有PDS。E4两级64bit加法、E5变量移位/比较和advance扇出仍须新100MHz实现评审；32个仿真APM实例不是完整mapped LUT/FF报告。未验证16×16、真实P/O、DDR、生产scope/发布、整网或板上30fps，没有新增B03位流。P41原HMIC两条ERROR/整体FAIL及P18、M01/G2继续保留。
