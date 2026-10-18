# 外部 NPU 仓库交接审查

2026-10-18，依据用户提供的私有仓库 [keep-s/npu_zgtc](https://github.com/keep-s/npu_zgtc)，固定审查提交 `4fc0fc882a6e92ec662a4f9b27b105182da444b8`（2026-10-16）。本工程 Video 基线为 `e0244ee`。

结论：需要的模型清单、输入数值规则、整数参考及参数包已找到，但两边输入契约不同，尚不能直接集成。外部仓库自己的冻结状态不自动修改本工程 v0.6 规格。

## 已找到的交付资产

路径均相对于外部仓库；审查快照保存在 `build/video/npu_handoff_audit/20261018T090831_980465Z/snapshot/`。

| 文件 | 可用于集成的内容 | 当前边界 |
|---|---|---|
| `yunet/models/model_manifest.json` | YuNet 原始/320派生模型、身份哈希、数值资产索引 | 已有主机模型基线，非 FPGA 实现 |
| `yunet/models/processing_contract_v1.json` | BGR、320×320、双线性/居中补边、坐标逆变换、输出顺序 | 与本工程 160×128 预处理不一致 |
| `yunet/models/integer_numerics_v1.json` | 输入 UINT8/scale=1/zero-point=0、各层位宽与尺度、RNE/饱和、九头编码 | 当前数值包针对320方案，不能直接批准另一种预处理 |
| `yunet/models/yunet_int8_numeric_v1.npz` | 权重、bias、multiplier/shift、LUT 等真实数值参数 | 不等于最终 FPGA 程序/地址部署包 |
| `yunet/python/yunet_pipeline.py` | 图像预处理、解码/NMS、坐标恢复参考 | FP32主机参考；CPU定点实现另行验证 |
| `yunet/python/ptq_integer.py` | INT32累加、整数重定标/算子参考 | 完整执行需要 ONNX/ORT 等依赖 |
| `yunet/python/export_integer_golden.py`、`yunet/baseline/ptq_integer_golden_summary_v1.json` | golden导出方法、输入/输出哈希及比较摘要 | 完整二进制、天然图像及部分运行依赖位于未提交的 reports/数据目录 |
| `word/16_视频与NPU输入交接草案.md` | 上游直接写最终DDR张量，CPU提交描述符，NPU直接读取 | READY/释放、地址和布局仍须共同定版 |
| `word/20_本地DDR接口契约.md`、`word/31_NPU任务ABI与地址绑定草案.md`、`word/32_NPU算子程序与参数编码草案.md`、`word/33_NPU控制器DMA与平台包装层规格.md` | 任务/帧身份、绑定、错误排空、完成scope、DMA与平台职责 | 草案/主机检查；无对应RTL或已验证跨master fence |

原始 ONNX、派生 ONNX、处理契约、整数契约和 NPZ 五项声明 SHA256 均匹配。保留上游许可证；本轮没有把外部模型或源码导入正式 `model/`、`rtl/npu/`。

## 必须先统一的差异

| 项目 | 当前总工程 | 外部 NPU 冻结版本 | 集成影响 |
|---|---|---|---|
| 输入形状 | 有效160×120，存储160×128；逻辑 `[1,3,128,160]` | `[1,3,320,320]` | 模型图、各层形状、检测头位置数、资源/周期均不同 |
| 缩小与补边 | 800×600按完整5×5块平均，底部补8行 | uint8 OpenCV INTER_LINEAR，等比例缩放并居中黑色补边 | 800×600将成为320×240，上下各40行；更换形状字段不足以等价 |
| DDR布局 | 每像素B/G/R/零×5，C8，163840B | 紧密B/G/R三平面NCHW，307200B | 需要明确选择物理布局及负责适配的一侧，不能直接交付现有C8流 |
| 输入编码 | 总规格优先评估signed INT8；已实现组件只搬运字节，没有冻结真实量化 | UINT8原像素0..255、scale=1、zero-point=0、无 `/255` | 若保留NPU v1，输入不需额外有损量化；128..255必须作为正数，不得重解释为负数 |
| 输入槽容量 | A/B/C各256KiB，基址间隔0x40000 | 每输入300KiB | 每槽差45056B，原地址间隔会重叠；整个1MiB输入区可评估重新划分，须统一配置后再使用 |
| 平台接口 | Video core125MHz、逻辑AXI128、现有HMIC适配 | NPU设计100MHz、本地32B beat、最多16beat | 需要总线/时钟适配和共享仲裁，不能把NPU本地端口直接接到Video AXI128 |
| 地址与完成 | 总规格已有系统分区，正式帧槽/共享fabric集成待做 | DDR/MMIO基址、任务binding仍为null，ready_for_hardware=false | 由集成方绑定统一地址、frame_id/epoch和安全释放；写可见性须有平台证据 |

已有BGR、补行、C8模块仍是经过验证的组件，不因发现另一套契约而失效；是否用于正式输入取决于共同选择。C8模块原样搬运8bit编码，不能仅凭模块名判断它已实现signed量化。

CPU侧还需采用相同输出语义：NPU v1九头中的cls/obj为UINT16概率（scale=2^-16），bbox为各头尺度的INT16，共25200逻辑字节。该概率输出不再额外做一次Sigmoid；解码、候选/NMS与坐标恢复须匹配处理版本。上游现有AP/质量报告是320预处理的历史主机证据，本轮未复现，也不能外推到160方案。

## 本轮实际检查及限制

- 167个快照文件的Git blob SHA1与固定提交的树一致；五项主资产SHA256匹配。
- NPZ在 `allow_pickle=False` 下读取241个数组，数值有限。
- 按上游定义独立重建零图、全255、确定性pattern三份307200B输入，均匹配golden摘要中的SHA256；没有据此宣称检测输出已重算。
- 仅读取并提取两个已审阅的预处理函数，在800×600常量BGR图上验证320×240、上下40行、通道/UINT8值域和NCHW；本机OpenCV4.14.0不同于上游4.11.0，因此不签认一般双线性像素逐位等价。
- 共433项资产/定向检查通过，`integration_ready=false`。没有运行完整ONNX/整数推理、WIDER评价、RTL/PDS或板测。外部 `rtl/` 只有 `.gitkeep`，任务/程序manifest也明确未具备硬件运行条件。

原始结果为 `build/video/npu_handoff_audit/20261018T090831_980465Z/result.json`；脚本、快照、校验清单和下载归档留在同目录，均未包含认证凭据。小型证据见 [npu_handoff_audit.json](evidence/npu_handoff_audit.json)。

## 下一步交接顺序

1. 集成方与NPU负责人共同选择输入形状、真实缩小/补边算法、UINT8/signed编码和物理布局，并给出唯一预处理版本。当前总规格保持有效，本轮不替任何一方修改基线。
2. 若保持总工程160×128/块平均路线，NPU侧需提供对应模型派生、输出形状、同预处理校准/FP32与整数质量验证及golden；不能仅改ONNX输入尺寸。若采用现有320主机基线，则Video需适配双线性/居中补边和NCHW，并调整输入槽、带宽及后处理坐标契约。
3. 取得与最终版本对应的天然图像及完整输入/输出golden。已有三个合成输入哈希可先用于字节布局检查；CPU共同确定正式地址、描述符/版本、帧身份、完成和释放语义。
4. 再接三分支DMA，逐字节比对最终输入，验证共享DDR跨master写后读、错误排空和所有权，最后执行上板验收。等待决策时可继续开发不绑定模型数值的仲裁、完成汇合和错误路径仿真。
