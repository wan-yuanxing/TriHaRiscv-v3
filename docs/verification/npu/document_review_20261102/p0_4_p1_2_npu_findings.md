# P0-4 / P1-2：NPU整数语义与真实数据流核查片段

任务日期：2026-11-02；执行跨至北京时间2026-11-03。仓库提交：`af324195d07ee15dca5d37e451aaff731a79a780`。
这是供父任务汇总的NPU片段，不是最终审核报告。工作区已有未提交修改，本次未切分支、未提交。

## 结论与修改决策

| 问题 | 真实实现与根因 | 处置 |
| --- | --- | --- |
| P0-4：首层被统一写为S8×S8 | 首层算子记录`src0_dtype=1`（U8），PE按`input_signed=0`零扩展激活，权重符号扩展；文档把权重类型泛化成了全部激活类型 | 仅改文档，明确U8×S8，无减128、无零点补偿 |
| 内部是否全部S8 | 不是。首层输出U8；下一逐点卷积U8→S8；随后DW为S8×S8并输出U8。模型另有S8→S8普通卷积和S8→S16的DW回归头 | 增加阶段类型表，避免“只有首层U8，其余均S8”的错误概括 |
| 补边、通道存储 | 全部零点为0。视频上下各40行写整数0；卷积窗口越界另行返回0；DDR输入恰为3个NCHW平面，307200 B，不是8通道 | 分开描述视频补边、卷积补边及尾通道掩码 |
| P1-2：Systolic Array与Configurable PE Array | Dense为操作数广播、本地累加；没有邻接PE转发，DW为独立16通道通路 | 正文统一为可配置并行MAC阵列；图只给建议 |
| 64/128乘加、跨输入通道块部分和 | Dense每有效拍16M次乘加，8M个SIMD APM；板级M=2，模块默认16。Dense要求完整K≤128，不支持任意部分和回装 | 写清参数与板级取值；删除未经实现支撑的跨K分块叙述 |
| 各类缓冲32 KiB及乒乓预取 | ROI=64 KiB，A/B/O各16 KiB，ROW_STAGE=4 KiB；参数另有小存储。Dense和DW部分和在计算通路内 | 改为实际银行配置、ROI驻留/滚动行复用、分阶段所有权交接 |
| 算子调度与接口 | 正式实例为`npu_frame_top`，硬件图控制器逐层派发；256-bit块服务经`npu_service_axi128`接AXI128。原文混入了独立标量算子端点的描述 | 在独占章节内同步为帧提交与图调度，补充块服务/AXI宽度、串行事务与读回语义 |

没有发现本次所核查U8/S8解释、零点、补边或现有整数用例的RTL/导出功能错误；没有修改RTL、固件或导出脚本。此结论限于下列源码核查及测试范围。

## 已编辑文件

- `docs/technical-report/latex/chapters/02-system/03-NPU设计.tex`：输入有无符号、实际并行度、24位本地和与I32接口、Dense/DW示例、缓冲、DMA和任务控制语义。
- `docs/technical-report/latex/chapters/02-system/06-模型部署与应用软件.tex`：量化说明、阶段类型表、算子映射、图调度及概率查表所在单元。
- 唯一新增LaTeX标签为`tab:npu-stage-types`，定义1次，正文引用2次。

未改其他LaTeX、任何图、NPU验证章、整机空章、最终审核报告。未编译总文档、未渲染或查看PDF，未运行PDS或板测。

## 数值来源与关键代码

路径均相对`D:/FPGA/TriHaRiscv-main`。完整SHA-256在本次build目录的`source_hashes.json`。

| 事实 | 来源 |
| --- | --- |
| BGR、NCHW、U8、scale=1、zero_point=0、storage_channels=3、上下40行 | `config/video_cfg.json:25`；`rtl/video/detect_nchw_dma.sv:5`、`:44`、`:49`、`:132` |
| 正式整帧实例和内外存储接口 | `rtl/soc/triha_compute_system.v:264`、`:323`；`rtl/npu/npu_frame_top.v:175`；`rtl/npu/b03_frame_service.v:171` |
| 活跃板级M=2、QUANTIZER_LANES=1；模块默认M=16 | `fpga/pg2l100h/rtl/triha_face_board_top.sv:30`；`rtl/npu/upstream/b03/rtl/platform/b03_array_apmacc_rowctrl.v:11` |
| U8零扩展/S8符号扩展、权重符号扩展 | `rtl/npu/upstream/b03/rtl/platform/b03_mac_pair_rowctrl.v:32`；`b03_layer_exec_payload.v`中的`.init_signed(sdt==2)`与`.input_signed(sdt==2)` |
| Dense广播、固定归属与S24→I32扩展 | `b03_array_apmacc_rowctrl.v:92`、`:110`、`:131`；`b03_mac_pair_rowctrl.v:1` |
| DW 16通道独立I32累加、K=1或9 | `b03_full_dw16_parallelfault.v:2`、`:29`及其`sums`/`acc`更新 |
| A/B/ROI银行容量、滚动行与驻留条件 | `b03_model_input_payload.v:131`、`:276`、`:320`、`:324`、`:331`、`:621` |
| Dense窗口越界0、DW越界0 | `b03_gather_lean.v`的`a_write_data=0`及逐像素有效条件；`b03_model_input_payload.v:378` |
| 输出O与Tile容量，完整K限制和循环次序 | `b03_layer_exec_payload.v:319`、`:438`、`:453`、`:470`、`:477`、`:484` |
| 输出行写回及同端口读回 | `b03_row_tile_store_rotate.v`的`mem_req_verify=1`；`b03_block_dma.v:1`及`verifying`分支 |
| 256→128、低半字先发、每AXI突发至多16拍、4 KiB拆分 | `rtl/soc/npu_service_axi128.v:1`、`:44`、`:54`、`:100` |
| Bias和完整K后重定标、最近偶数舍入、饱和 | `b03_quant4_core.v:86`、`:188`、`:235`；主机`ptq_integer.py:17`、`:214`；`compile_b03_runtime.py:229` |

表内省略目录的B03文件均位于`rtl/npu/upstream/b03/rtl/platform/`。
主机数值源码使用本仓库恢复的冻结副本`build/npu/b03_assets_20261030/frozen_upstream/yunet/python/`，没有执行旧仓库工作区的Python实现。

冻结数值契约为`build/npu/b03_assets_20261030/frozen_upstream/yunet/models/integer_numerics_v1.json`，SHA-256：
`8152d6bbf187bb7041d225f23f35f731d5e20ccc1be7410c46e000c9aeb060a2`。
该文件规定`real=scale*q`、全部零点0、权重[-127,127]、full-K后一次Bias/requant、padding_code=0、ReLU输出U8。
`ptq_integer.py` SHA-256为`78454d13a2175379e3f12b8ae65f6eb101ed95961063a506d3bb92be8a56e42f`。

运行记录来自`build/npu/b03_assets_20261030/assets/runtime_decoded.json`，其原始身份由`model/yunet/upstream/b03_558280b/package_manifest.json`固定。前3项为：

| op_id | 算子 | 输入→输出类型 | 几何 | K |
| --- | --- | --- | --- | --- |
| 0 | Dense，源Conv_0 | U8→U8 | 3×320×320→16×160×160，3×3/s2/p1 | 27 |
| 1 | Dense/PW，源Conv_2 | U8→S8 | 16×160×160→16×160×160，1×1/s1/p0 | 16 |
| 2 | DW，源Conv_3 | S8→U8 | 16×160×160→16×160×160，3×3/s1/p1 | 9 |

Dense绝对和上界`128*255*127=4145280`落在有符号24位内；APM两个24位累加槽分别属于两个输出通道，出阵列时符号扩展到I32，随后才加Bias。这里的24位实现不等于改变INT32模型数值契约。

## 示例计算与银行归属

首层取板级M=2，一个计算块是2空间位置×16输出通道。K以输入通道、核行、核列顺序走27项；每拍一个A向量（2有效字节，固定16字节接口）和一个B向量（16个权重），总有效MAC=2×16×27=864。有效权重432 B，搬运包含参数块对齐。各位置的激活复用16次，各权重当拍复用2次并跨空间块驻留。累加器只属于本块的对应输出。

首个DW以16通道为一组，每个空间位置接收9个tap；ROI每银行对应一个通道，B各tap含16个对应权重，16路独立和共完成144次MAC。整个输出行沿x扫描后再换Co块；本例只有一个Co块。DW不经A展开，相邻窗口复用ROI数据，权重在整行反复读出。

首层输入每通道行宽320 B，ROI滚动3行，步长2时复用1行；DW每行160 B，步长1复用2行。边界不存在的行通过有效位返回0，不搬入虚构数据。两例整张输入都不满足ROI驻留条件。

两例O均为16通道、U8、宽160。每银行1024个32位字，4个通道组，满足`ceil(160*rows/4)*4<=1024`，所以一次存6行，即15360 B；160行最后剩4行。O按通道/字偏移旋转分银行，双端口接收量化组，行写回器恢复连续NCHW，再由256-bit块服务和AXI128适配器搬出。这不是把M=2空间计算块当成整层写回Tile。

## 本次测试与证据

本次统一证据根目录：
`build/npu/document_review_p0_4_p1_2_20261102T160058_451164Z/`。
所有新运行目录唯一，没有覆盖历史日志或波形。

| 命令/入口 | 结果 | 原始证据与边界 |
| --- | --- | --- |
| `$env:PYTHONDONTWRITEBYTECODE='1'; python -B scripts/npu/run_scalar.py` | exit 0，18项PASS | `build/npu/scalar-20261102T155822_679923Z/result.json`，及同目录各用例日志。独立Fraction oracle、标量RTL；不是并行B03全图证明。`frozen_conv0`使用真实首层参数和7×5裁剪输入 |
| `& D:/FPGA/npu_zgtc/.venv/Scripts/python.exe -B scripts/npu/run_b03_input_compact.py --output build/npu/document_review_p0_4_p1_2_20261102T160058_451164Z/input_scoreboard` | exit 0，`PASS_INPUT_SCOREBOARD_AND_LOCKSTEP` | `input_scoreboard/result.json`、`input_scoreboard/simulation/console.log`。34项：22有效、12非法；46个公开输出逐拍比较；A检查2092，B检查1784，DW检查121130；滚动行15、读字节72960；供数/存储服务代理测试，不是完整卷积输出回归 |
| 冻结`ptq_integer.arithmetic_checks()`，通过上述既有venv的`python -B -`执行 | exit 0，8组检查PASS | `host_arithmetic.json`。含RNE/Fraction、Dense/DW与标量比对、signed/unsigned极值、饱和、Add、池化/Resize及数学分块等价；其中数学分块检查不证明RTL支持跨K回装 |
| 源码结构核查（括号、环境、空白及新label引用），并复核源文件SHA | PASS | `document_source_checks.json`，2个LaTeX文件无结构异常，label 1定义/2引用，`source_changed=[]`；不替代LaTeX编译 |

`source_hashes.json`保存核查输入身份；`document_changes.diff`保存相对编辑前快照的差异（两章在原工作区为未跟踪文件，不能只看普通`git diff`）；原章快照亦仅存本次build目录。

主机检查的stdin主体如下，工作目录为仓库根：

```python
import sys
from pathlib import Path
p = Path('build/npu/b03_assets_20261030/frozen_upstream/yunet/python').resolve()
sys.path.insert(0, str(p))
from ptq_integer import arithmetic_checks
checks = arithmetic_checks()
```

实际调用还把返回的8组名称、解释器版本和源码SHA写入`host_arithmetic.json`。

## 给父任务的最小图修订建议

仅检查了draw.io XML，没有查看或渲染PDF，也没有修改图文件。

1. `figure/rv32-soc.drawio`的`TriHaRiscv SoC`页，节点`9YNyzM4rnTg54BFL_skZ-15`的`Systolic Array`改为`Configurable PE Array`（可配置并行MAC阵列）；`Development Flow`页的`veXQFo8XIVMpp28n9AnA-151`同步改名。不要把APM数量直接标成MAC数量。
2. `figure/TriHa_NPU_Microarchitecture_Flow_v1.drawio`的`NPU Microarchitecture`页，保留`M42z8NjHoIGwK-7sokjJ-107`的`Configurable PE Array`名称；在其内部或旁注区分`Dense/PW: M×16, broadcast/local accumulate`和`DW: 16 channels`。若保留4×4 MAC小格，注明仅为结构示意，不代表实例规模。板级M=2；参数默认M=16。
3. 节点`...-54`的`Multi-banked Scratchpad`最少标清`ROI 64 KiB; A/B/O 16 KiB each`，可在图注补`ROW_STAGE 4 KiB; parameters separate`。不画独立32 KiB部分和RAM，也不添加乒乓搬运箭头。
4. 数据流应为`DDR→DMA→ROI/B/参数`；`ROI→Gather→A→Dense`，`ROI→DW`，`B→Dense/DW`；两条计算通路的部分和`→Bias/Requant→O→DMA→DDR`。节点`...-61`的`Bias / Scale Input`可改`Bias / Multiplier / Shift`，直接连接`...-68`的后处理节点，不进入PE乘法输入。后处理顺序写为Bias→Requant/RNE→Saturation（U8编码包含ReLU）。
5. 节点`...-52` DMA与`...-53`外存之间标`256-bit block service → AXI128 adapter → AXI4 128-bit`；读写数据方向相反，状态/完成独立返回。AXI突发最多16×16 B；内部块最多16×32 B，不把两种“16拍”混写。
6. `CPU→Host CSRs`为AXI-Lite/MMIO配置，`IRQ / Status→CPU`为反馈；`Host CSRs→Graph/Layer control`。现有`CSR 0/CSR 1`及两个`CSR Manager`是功能抽象，RTL没有两套可独立寻址的此类控制接口，建议改为“算子/供数参数锁存”，避免误导为CPU每块写两套CSR。内部控制箭头连到供数和计算单元，不能与张量数据箭头混用。

当前微架构图许多连线使用自由端点，没有完整source/target绑定。上述为根据RTL应有的方向，父任务调整几何时应核对箭头端点，不依靠节点ID自动重连。

## 父任务需统一的相邻口径

- 若其他章节或图仍写CPU逐算子启动、64/128 MAC、每类32 KiB、输入按8通道存储，应与本片段所列正式实例核对。本次没有越界修改这些文件。
- 概率Sigmoid由NPU向量通路执行，导出输出是U16；CPU处理候选与框解码/NMS，不能把这条路径再写为CPU从S8 logits重复做Sigmoid。
- 本次使用的冻结B03资产是`bbox16`，只列cls/obj/bbox共9个头，不能为五关键点输出提供证据。原有模型/应用正文中的五点设计描述未在本次P0-4/P1-2任务中扩展或删除；父任务若要宣称该路径已实现，需另核对实际导出资产。此项是资产/设计覆盖边界，不是本次发现并修复的量化RTL错误。
- 父任务统一编译并检查日志；本片段不宣称PDF已编译或版式已验证。
