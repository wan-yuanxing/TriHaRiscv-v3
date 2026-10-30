# NPU拉取、验证与主工程合拢评估

日期：2026-10-20。主工程为 `D:/FPGA/TriHaRiscv-main`，读取基线 `869a028bc0d6b4cda9ba5422c929263b77656837` 及当前工作区；外部NPU已克隆至 `D:/FPGA/npu_zgtc`，固定提交 `178c3ad1ba515d43725dd80ab19e20b50d471413`。主工程已有CPU说明与技术报告的未提交修改，评估采用实际工作区内容，未将它们误标为HEAD内文件。

**结论：具备开展契约对齐、参考比对和系统仿真集成的基础，尚不具备直接合成为完整SoC或上板运行真实YuNet的条件。** NPU数值资产和局部平台实现可复现；正式算子阵列、完整DMA、任务控制器仍未交付。当前主工程也尚未合入CPU/NPU RTL及生产SoC fabric。

本轮只新增评估与证据、运行隔离验证；没有迁入产品RTL、修改公共契约或执行板卡下载。机器摘要为 [integration_readiness.json](evidence/integration_readiness.json)。原始输出、补充验证脚本和独立主工程审查保存在外部仓库忽略的 `build/integration_audit/`。

## 本轮实际验证

环境：Windows原生PowerShell/Python；PDS `D:/pango/PDS_2022.2-SP6.4`，ModelSim SE-64 **2020.4**。模型依赖安装在NPU目录独立 `.venv`：Python3.13.13、NumPy2.5.4、ONNX1.23.2、ORT1.31.0、OpenCV4.11.0。上游原语摘要生成器中的日期及ModelSim10.4字段为硬编码历史元信息，本轮运行时间、实际工具及哈希以本摘要和原始日志为准。

| 验证层级 | 本轮结果 | 证明范围 |
|---|---|---|
| 模型与参数身份 | 原始/派生ONNX、处理/整数契约、NPZ、校准范围及清单7项SHA256匹配；241个参数数组重建一致 | 已提交数值基线身份及可加载性 |
| FP32图与处理链 | 320派生图检查/原图裁剪输出比较通过；处理链12组边界检查和blank输入各profile的ORT/OpenCV核对通过 | 软件图、预处理、解码边界；未重跑天然图像AP |
| 整数数值 | 8组算术检查通过；zero/full255/pattern三组各79个张量与直接INT64路径逐元素一致；27个检测头二进制SHA256匹配历史golden | 完整图的合成输入主机数值；尚非硬件推理 |
| 程序与参数包 | 重建20160B程序及108288B参数镜像，SHA256均匹配上游manifest；三组各79张量从序列化程序回放一致 | 编码、回读和软件执行一致；与整数参考共享算术核 |
| 任务ABI | 6组正例及27个非法案例拒绝通过，包含frame64、epoch、重定位和窗口边界 | 主机草案检查；不证明RTL寄存器或驱动存在 |
| DDR与系统预算模型 | DDR契约模型通过；4组RAM、8组带宽及4组抽象完成反例通过 | 条件模型检查；不是实际DDR排序或吞吐 |
| Video→NPU输入 | 6幅800×600 RGB图经主工程参考和NPU OpenCV4.11路径比较，1843200字节完全一致；三输入槽容量/边界检查通过 | 当前软件参考的字节等价；本轮未重跑Video RTL或板测 |
| 平台RTL | RAM/APM/PLL 3项、TDP0/TDP1/LUT 3项、FIFO/TX 7项、BIST 1项，共14个ModelSim仿真任务通过 | 使用厂商原语模型的局部实现；BIST含3次健康运行、2次注错及复位恢复 |
| PDS实现 | primitive、memory、fifo、board_bist四个独立顶层完成综合/映射/布线；各声明的内部setup/hold检查通过 | 局部平台实现，不是完整NPU或系统签核 |

四个顶层映射资源分别为：

| 顶层 | LUT | FF | DRM36K等效 | APM | GPLL |
|---|---:|---:|---:|---:|---:|
| platform_primitive_top | 111 | 109 | 0.5 | 1 | 1 |
| platform_memory_top | 198 | 154 | 6 | 0 | 1 |
| platform_fifo_top | 639 | 1572 | 8 | 0 | 0 |
| board_bringup_top | 211 | 144 | 0.5 | 1 | 1 |

这些是互相重叠的验证探针，不能相加当作NPU总资源。BIST位流已生成，SHA256为 `e12be6f24b38ea42fdbf150580fbf11c10fea8558f32e4a218561e050e7a2646`，没有下载。FIFO本轮内部STA及Gray最大延迟通过，Gray偏斜/MTBF/完整CDC签核仍开放；本轮未复跑上游SDF条件包络分析，也未关闭P24/P25。

### 交付可复现性问题

干净克隆直接运行 `program_abi.py` 返回1：缺少 `yunet/reports/ptq_320_v0_1/calibration_ranges.json`。进一步读取发现，完整入口还依赖未提交的integer_plan、逐层golden和WIDER天然图像。初始失败保存在 `build/integration_audit/20261020/program_abi_initial.log`，没有将该入口报告为通过。

补充脚本仅用已提交的 `baseline/ptq_calibration_ranges_v1.json` 和冻结NPZ恢复可重建的主机中间文件，核对每个数组后重建程序、复算三个合成输入。未伪造天然图像或回填缺失golden。完整WIDER3226图AP、天然校准图golden及上游完整程序ABI审计（含全部54负例）均未复现。上游AP降幅和fps报告继续保持历史/条件证据身份。

## 已消除的旧差异

10月18日 [旧交接审查](../video/npu_handoff_audit.md) 中的160×128、C8和256KiB槽不足已被后续Video工作消除。当前公共配置 `config/video_cfg.json` 是800×600→320×240双线性、上下40行零、UINT8 BGR NCHW、scale1/zero-point0，输入307200B；A/B/C槽分别为 `0x82800000/0x82850000/0x828A0000`，每槽327680B。

最新NPU提交的处理契约与数值资产哈希仍与旧冻结版本相同，本轮已复核并完成软件字节比对。可以让NPU直接绑定Video写好的最终输入，CPU只交控制信息；无需另加像素复制。真实跨主端可见性和生命周期仍须后续验证。

Video最新状态已包括局部采写/显示读共享DDR、RAW显示MMIO与真实commit/release闭环，以及CPU三槽C库。应以 [STATUS](../../video/STATUS.md) 和各批证据描述这些组件，不能沿用旧报告“完全没有共享端口/三槽库”的状态；它们尚未组合成生产CPU＋NPU的完整闭环。

## 合拢前必须处理的问题

| 项目 | 当前证据与影响 | 准入条件 |
|---|---|---|
| 正式NPU硬件 | 外部 `rtl/platform/` 只有原语/平台探针。硬件profile仍为未实现；controller、卷积/辅助算子、完整DMA均缺席 | 交付正式模块/filelist、代表层golden和DMA错误路径，再逐层到整网 |
| CPU和SoC | 主 `rtl/cpu/`、`rtl/npu/` 仅.gitkeep，`rtl/soc/`只有Video控制适配。独立CPU100MHz布线记录setup失败，最差−15.557ns，核内反例−8.827ns | 合入正式CPU/ROM/SRAM/IRQ/MMIO/DDR互连；分别验功能和100MHz物理时序 |
| 调度职责冲突 | 主规格11.1规定CPU逐算子MMIO、无硬件图级取指；NPU文档31/32规定一次提交79算子顺序程序，由RTL解析执行 | 先统一任务粒度、寄存器和驱动职责；现有operator ticket不能直接等同CMD_ID |
| 输出语义冲突 | 主规格要求五点；当前bbox16包已裁去kps，仅cls/obj/bbox九头。逻辑25200B，现有分配合计26368B | 明确首版bbox范围或补齐关键点模型/量化/硬件；同步CPU解码与显示有效标志 |
| 时钟、位宽与唯一DDR所有者 | NPU/CPU100MHz、本地256bit；主桥125MHz、AXI128→HMIC256。现cpu_native_axil为同钟，且只接受0x2001xxxx | 复用唯一物理HMIC；确定全局仲裁、100↔125 CDC及位宽转换位置 |
| 地址与身份 | NPU DDR/MMIO基址仍null、窗口示例1GiB；主逻辑只映射128MiB。任务有u64 frame/epoch，主C池为u32 frame/generation | 同源配置分配描述符/程序/工作区/九头输出，做范围检查并冻结身份映射和回绕规则 |
| 完成、可见性与恢复 | 主桥B表示独占同端口读回匹配；NPU要求RAW_SAFE及DEVICE_HANDOFF_SAFE，命令/完成CDC、RX预留等未完成 | 验证Video→NPU→CPU→Display沿唯一通路的写后读、不可缓存共享区、排空/协调复位及旧epoch隔离 |
| 全系统RAM预算 | 最新NPU候选100 DRM；独立三模式Video已实现73.5 DRM，其中64为素材缓存。直接叠加173.5＞器件155，超18.5，尚未CPU存储/新fabric | 重新按共享/替换项拆账，缩减素材缓存或改DDR读取，再以合并网表验证；不能据旧部分预算签核 |
| 完整采显与推理并发 | RAW闭环、ABI2采集、共享DDR、C池尚待组合。当前闭环拒绝BOX/AVATAR，真实显示水位和全系统带宽未验 | 在800×600采显并发下加入NPU/CPU流量，记录行截止时间、最大等待、欠载和实际有效fps |

输出容量需要按实际模型计算：主规格“64KiB不足”的67200B是假定包含kps的16值/位置，不能套用为当前bbox九头的事实。现有2MiB输出区及64MiB工作区在总量上可容纳当前包，但实际三槽、参数区和描述符仍未绑定，容量充足不等于地址ABI已冻结。

资源超额是对“现有Video与候选NPU原样拼接”的预算否决，并非完整NPU已综合后的实测结论。NPU全阵列资源/布线仍未知。建议先以RAW路径开展集成验证，随后重做头像存储策略；完整演示仍须支持框和头像。

## 建议的最小合拢顺序

1. 先冻结整图/逐算子控制选择、bbox/五点范围、128MiB窗口内的地址和任务身份；重新核算含CPU、显示、素材及NPU的片上RAM预算。保留当前主规格，决策完成后再同步修改两端。
2. 组合ABI2采集、现共享DDR、真实RAW scanout与三槽C回放；接入会产生真实DDR请求的NPU任务代理，覆盖旧epoch、长ACK、随机延迟和失败排空。该阶段可先用总线模型推进。
3. 完成唯一DDR通路的全局仲裁、100↔125 CDC、宽度转换与可见性验证，先取得INPUT_READY和结果发布的可靠平台依据。
4. CPU接正式SoC；NPU交付controller/DMA/算子并通过逐层golden，先跑静态输入整网和九头读回，再替换任务代理。
5. CPU定点后处理、同帧BOX/AVATAR和素材DDR路径加入后，执行全系统综合/布局布线及板测，分别报告10分钟功能稳定性、实际fps/延迟和后续性能优化。

当前主工程优先真实功能演示，≥24fps是优化目标，30fps不是首轮合拢硬门槛。上游30fps条件模型不能代替本系统的实际结果。

## 复现与原始证据

工作目录 `D:/FPGA/npu_zgtc`。上游平台脚本每次要求新的输出目录；将下面的输出目录改为未使用路径再运行，保留旧证据。原始本轮目录为 `build/integration_audit/20261020`。

```powershell
.\.venv\Scripts\python.exe yunet/python/profile_yunet.py --sizes 320
.\.venv\Scripts\python.exe yunet/python/verify_processing_contract.py --output build/integration_audit/20261020/processing.json
python yunet/python/task_abi.py --output-dir build/integration_audit/20261020/task_abi
python yunet/python/audit_ddr_contract.py --output-dir build/integration_audit/20261020/ddr_contract
.\.venv\Scripts\python.exe yunet/python/audit_system_budget.py --output-dir build/integration_audit/20261020/system_budget
python yunet/python/run_platform_primitives.py --pds-root D:/pango/PDS_2022.2-SP6.4 --modelsim-root D:/modeltech64_2020.4/win64 --output-dir build/integration_audit/20261020/primitives
python yunet/python/run_platform_memory.py --pds-root D:/pango/PDS_2022.2-SP6.4 --modelsim-root D:/modeltech64_2020.4/win64 --output-dir build/integration_audit/20261020/memory
python yunet/python/run_platform_fifo.py --pds-root D:/pango/PDS_2022.2-SP6.4 --modelsim-root D:/modeltech64_2020.4/win64 --output-dir build/integration_audit/20261020/fifo
python yunet/python/run_board_bringup.py --pds-root D:/pango/PDS_2022.2-SP6.4 --modelsim-root D:/modeltech64_2020.4/win64 --output-dir build/integration_audit/20261020/board_bist
```

补充脚本 `verify_numeric.py`、`verify_video_handoff.py` 位于本轮目录，前者恢复主机中间文件并生成三组合成golden，后者比较两个仓库的软件预处理。输入/产物SHA256、实际工具版本、运行结果和独立审查定位均由机器摘要登记。本轮没有完整主工程回归、全系统PDS、板测或性能达标结论。
