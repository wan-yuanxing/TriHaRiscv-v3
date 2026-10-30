# NPU 真实单算子 CPU 闭环验证

2026-10-21。用户授权执行 CPU→MMIO→真实卷积→AXI DMA→结果回读。本批实现位于隔离分支 `npu/operator-loop`，并按文件白名单迁回 `D:/FPGA/TriHaRiscv-main`；保留外部 NPU 基线 `178c3ad` 和独立 CPU 实验源码。

本阶段交付单通路 Dense/DW 的数字闭环与 100MHz 组件实现。完整网络、五点关键点和整机上板功能尚未交付。最终五点要求保留，bbox 为中间阶段。

## 实现与复现

新增四个 Verilog 模块：同钟 AXI-Lite 控制端点、标量卷积、AXI128 单拍 DMA 和组合顶层；公共 JSON 单源生成 RTL/C 寄存器；提供真实 RV32I 固件及 poll/IRQ 驱动。既有 `cpu_native_axil` 仅增加 MMIO_PREFIX 参数，默认仍为 0x2001，NPU 实例指定 0x2000。[接口](../../interfaces/npu.md)、[设计](../../superpowers/specs/2026-10-21-npu-operator-loop-design.md)、[执行计划](../../superpowers/plans/2026-10-21-npu-operator-loop.md)列出数值、错误、身份、完成与复位契约。

在主工程运行：

```powershell
python scripts/npu/gen_regs.py --check
python scripts/npu/test_dma_runner.py
python scripts/npu/test_mmio_runner.py
python scripts/npu/run_scalar.py
python scripts/npu/run_cpu_operator.py --scenario all --cases dense_u8 dw_s8 dense_s8 dense_i16 dw_u8 tail17 stride2 no_pad positive_tie negative_tie shift0 shift63 frozen_conv0 --modes poll irq
python scripts/npu/build_operator.py
python -m unittest discover -s scripts/npu -p test_runner_freeze.py -v
python -m unittest discover -s scripts/npu -p test_operator_reports.py -v
python scripts/video/run.py --suite cpu_axil
```

CPU 固定从 Git 提交 `dc00f801d0b3cf1e40faf32bd799c14b9d6b330e` 导出 33 个普通 blob。测试不会读取 CPU 工作树的未提交实验文件，也未把该 CPU 正式迁入主工程。Boot ROM 8KiB、SRAM 32KiB；TB 将 CPU 和 NPU DMA 接到同一字节 DDR 模型，CPU 通过本地读端口逐字节读取实际输出。

## 验证结果

| 层级 | 已验证范围 |
|---|---|
| DMA | 72 场景；AW/W 先后、背压、非法本地命令、ID/RESP/LAST、故障锁存/复位 |
| MMIO | 785 checks、20 项生成器检查；W1C 事件优先、身份锁存、busy/待 ACK 拒绝、地址/字节写 |
| 算子 | 18 组，每组连续两任务；Dense/DW、U8/S8/I16、尾通道、padding/stride、正负 tie、shift0/63、溢出/非法配置/DMA 错误 |
| CPU | 13 数值场景×poll/IRQ=26 组、52 个真实任务、6308 字节实际回读；末 B 延迟 31 拍；断开控制及破坏输出两反例拒绝 |
| 独立规格审查 | 最终 RTL 15 个数值任务及 57 个配置探针通过；最终源 SHA 见机器摘要 |
| 实现 | 100MHz 显式组件目标完成综合、映射、布局布线、setup/hold；约束未放宽 |

真实 Conv_0 场景从冻结 program.bin/parameter_image.bin 解出 16 通道真实权重、bias、逐通道重定标，采用 7×5 裁剪输入；没有运行完整 320×320 层。数值 oracle 使用 Python 整数、Fraction 和独立的 ties-to-even 定义。

组件物理结果为 3339 LUT、2807 FF、16 APM、0 DRM、0 GPLL，包含诊断用 542 个扫描边界 FF。100MHz slow/fast setup 为 +0.424/+2.480ns，hold 为 +0.118/+0.101ns；最终复跑的具体报告及哈希见 [机器摘要](evidence/operator_loop.json)。这不是整机资源或板级总线时序结论。

迁回主工程后，完整 26 组 CPU 复测为 `build/npu/cpu_operator_20261021_162422_cbf813e0/`；18 组算子为 `build/npu/scalar-20261021T082422_067187Z/`；DMA、MMIO 和既有 Video cpu_axil 也重新通过。上批准备阶段 33 项测试、报告解析 4 项保持通过。最终 PDS 使用收紧后的 runner，原始路径为隔离工作树 `build/npu/pds-20261021T081726_056120Z/`，全部硬件/约束/构建入口哈希与迁回主工程的文件一致。

## 保留的失败与修复

首次组合尺寸乘法造成 slow setup −5.794ns；尺寸改为先校验再分级预计算后仍为 −0.576ns；合法 stride 改移位、RNE 拆绝对值/舍入/符号/饱和阶段后在相同 10ns、IO 和 uncertainty 约束下通过。旧失败目录保留，未改写为成功。另修正宿主对 `dev_map -detail successfully.` 的识别，并以报告解析测试覆盖。

CPU 的 tail17 暴露驱动先 STATUS 后 IRQ 的完成边界混合快照；改为先 sticky IRQ 后冻结状态，再通过全量回归。最小 tie 场景通过确定首两笔 AW先/W先并保留后续随机化，维持覆盖门槛。

质量审查复现了仿真后才记录源哈希的竞态。现 scalar/MMIO/DMA 编译独立冻结副本，逐命令前后检查原件、副本、工具及生成输入；scalar 的真实模型三资产也冻结。6 个真实仿真注改测试覆盖三个 runner 的原件/副本，旧版三项原件注改测试先失败、修复后全部通过。PDS 同样验证原件与冻结副本。优化模式会移除 oracle/generator 的 assert，因此 scalar/MMIO/CPU 入口明确拒绝 `python -O` 给出 PASS，PDS 的签核门槛改为显式异常。

具体结果目录、源文件/工具/产物 SHA、审查关闭记录和迁移保护检查统一在机器摘要定位。构建输出均位于忽略的 build 目录，源码迁移不复制这些临时产物；历史证据继续保存在隔离工作树。

迁移复制瞬间 46 个既有文件保持哈希；早期快照后的 Video 头像计划变化、主工程复测期间 `tb/video/tb_video_record_renderer.sv` 的并行变化分别记录，不恢复其他路线内容。首次收尾保护检查因后者变化拒绝继续，核实不属本批写入后单独列入并行变化，再完成最终审计。

## 尚未关闭的门槛

正式 CPU/fabric 互连与跨 master DDR 可见性、物理 DDR、100↔125MHz CDC、完整算子调度和 YuNet 网络、关键点 INT8 校准/精度、全系统资源/时序/帧率及整机板测仍开放。单通路组件的 0 DRM/16 APM 不能替代完整 NPU 预算。

本轮没有 JTAG、串口、Flash、提交或推送操作，也未探测板卡当前镜像。历史 BIST 初始灯态和实体 KEY0 五次已由用户确认；10 分钟稳定性仍没有明确反馈。后续优先逐层整数验证及五点量化，同时落实共享 fabric/DDR/CDC 契约。
