# NPU合拢准备执行记录

日期：2026-10-21。主工程HEAD为869a028，外部NPU基线178c3ad。用户授权继续执行，并明确“保留五点要求，检测框作为中间阶段”。本轮落实离线算子表、候选地址和资源检查，原10月20日评估/板测记录保留为历史证据。

**本轮已完成主机侧准备，尚未完成CPU→NPU真实算子闭环。** 当前模型包可作为bbox中间验证输入；最终五点模型、真实算子/MMIO/DMA/共享fabric及整机实现仍有开放项。

## 可审查交付

- [设计与边界](../../superpowers/specs/2026-10-21-npu-integration-preparation-design.md)：沿用主规格CPU逐算子控制；不把外部整图CMD_ID装成主工程寄存器。
- [候选配置](../../../config/npu_integration_fixture.json)：主机布局与分阶段预算，未发布为硬件ABI。
- [准备入口](../../../scripts/npu/prepare_integration.py)及[33项测试](../../../scripts/npu/test_prepare_integration.py)。只用Python标准库，不新增环境。
- [机器摘要](evidence/integration_preparation.json)：输入、产物、独立核对及限制。

最终包为`build/npu/integration_preparation_20261021/final_package/`，包含`bindings.json`、21728B的`npu_cpu_table.bin`、对应C头及108288B原始参数镜像。表含80张量、150项参数、79算子与三槽地址；原始程序/参数哈希保持身份。默认C头通过DDR基址指针读取表，显式定义`TRIHA_NPU_EMBED_HOST_TABLE`才嵌入数组，避免误占8KiB Boot ROM。

本表是新CPU离线适配格式；还需要把算子字段映射到OP_PARAMS并交付真实驱动。表和参数的板级装载器尚未实现。外部任务ABI只支持input/head绑定，不能直接使用本表的参数重定位方案。

## 候选地址

| 内容 | 地址/方式 | 本轮检查 |
|---|---|---|
| 输入A/B/C | 0x82800000 / 0x82850000 / 0x828A0000 | 每槽320KiB；307200B UINT8 BGR NCHW，直接消费Video地址，输入复制0B |
| 输出A/B/C | 0x82900000 / 0x82920000 / 0x82940000 | 每槽128KiB；当前九头逻辑25200B、256B对齐分配26368B |
| 参数镜像 | 0x82B00000起 | 原model_offset减参数镜像起点后重定位，留在主规格model区 |
| CPU表 | 0x82B20000起、保留64KiB | 实际21728B，不与参数区重叠 |
| 内部张量 | 0x83300000 + model_offset | 保持原布局，保留原input/head/参数洞；未做生命周期压缩 |

CPU私有区、九个共享大区与所有三槽容量在128MiB窗口内核对。候选地址未写入产品RTL/现有Video公共配置，也没有实际DMA写入这些DDR地址。frame/generation/op_tag的身份约束与回绕规则已写入设计，具体端点和恢复仍待实现。

## 资源方案

采用已记录Video实现73.5DRM、其中头像整幅cache64DRM；NPU使用控制面预算保留100.5DRM，而非旧部分预算的100。NPU数值仍为规划，完整阵列LUT/FF/布线未知。

| 场景 | DRM算术 | 相对155余量 | 含义 |
|---|---|---|---|
| 现Video + NPU候选 | 73.5+100.5=174 | −19 | 直接拼接已超预算，尚未CPU存储 |
| RAW候选 | 73.5−64+100.5+10+8=128 | 27 | 暂去整幅头像cache，CPU ROM/SRAM预算10，fabric/CDC额外预留8 |
| DDR头像缓存候选 | 128+16=144 | 11 | 按需素材读取缓存上限16，尚需实现与行截止时间验证 |

CPU存储10按8KiB ROM+32KiB SRAM、32bit有效载荷4KiB/DRM估算，无I/D cache；不含潜在端口/深度碎片。减掉64和增加16都只是方案，当前没有已实现的RAW合并顶层或DDR素材替代cache。三个场景的hardware_ready均为false；后续关键点、全系统资源和时序必须重测。

核对独立CPU工作树后，发现原评估中“CPU100MHz尚未通过”已由后续CPU工作推进：`docs/verification/cpu/operand_hazard.json`记录dc00f80版100MHz板级setup+0.113ns、CPU-only5933LUT/3528FF/0DRM/4APM。该证据本轮按SHA引用，未重新运行CPU STA；CPU工作区有未完成load-return实验，不能从当前脏源码直接迁入。主工程尚未合入CPU，因此仍保留稳定版本接入门槛。

## 实际验证

1. 33项unittest通过，含独立构造的2张量/1算子/无参数MaxPool程序、真实冻结包及非法配置拒绝。覆盖程序/参数损坏、reserved/ID/依赖/owner错误、地址重叠/越界、输入格式、输出/表容量，以及失败输出不能覆盖旧结果。
2. 准备入口实际退出0；独立`--require-hardware-ready`运行由Python返回2，保留主机准备PASS和hardware_ready=false。PowerShell命令末尾使用`exit $LASTEXITCODE`记录原始退出码。
3. 独立脚本不导入生产工具，以struct重读原程序，复算240个张量地址、150个参数地址，并逐字节核对80张量/150参数元数据、79算子及参数镜像；C数组和二进制表逐字节一致。
4. 实际GCC15.2以`-march=rv32i -mabi=ilp32 -std=c11 -Wall -Wextra -Werror`编译DDR指针和嵌入两种模式，均返回0，目标文件均为ELF32 RISC-V。这是编译检查，未链接/启动CPU固件。
5. 独立审查复核32项当时测试、全部地址、表与两种C编译，未发现本批固定bbox包/默认fixture阻塞问题。随后补齐计划中的独立小程序测试，父任务最终33项通过；生产工具在审查后未改动。
6. 初始保护清单中49项其他既有文件保持哈希；Video流水线计划在检查期间发生并行变化，按前后哈希单独记录，本轮未写入/恢复。main STATUS和NPU台账仅追加本批记录。首次保护核对拒绝该变化的结果也保留，未把它归因于本批RTL修改。

开发阶段保留了工具缺失时RED、首次numeric heads dict/list比较失败、ROM防误嵌入RED及后续GREEN，未修改历史结果。所有波形/临时模型/日志/表均在忽略的build目录。

## 五点扩展的额外核查

从固定原始ONNX保留全部分支，重新推断320输入形状，生成仅位于build的FP32候选图。ONNX checker/Runtime通过，zero/full255/pattern三输入保留的九头与当前bbox图在声明容差内一致，新增kps_8/16/32形状分别为[1,1600,10]/[1,400,10]/[1,100,10]且均有限。

卷积MAC从84523000增至86056000，增加1533000（约1.8137%），增加12个原图节点。INT16全12头逻辑数据的条件下限为67200B，比当前bbox九头多42000B，128KiB候选槽在纯容量上有空间。这不证明实际dtype/对齐、额外缓冲或片上资源满足；候选未做INT8校准、关键点精度或天然图像/WIDER AP验证，也没有成为正式模型清单。

## 复现与后续准入

在`D:/FPGA/TriHaRiscv-main`运行：

```powershell
python -m unittest discover -s scripts/npu -p test_prepare_integration.py -v
python scripts/npu/prepare_integration.py --npu-root ../npu_zgtc --program ../npu_zgtc/build/integration_audit/20261020/program.bin --parameters ../npu_zgtc/build/integration_audit/20261020/parameter_image.bin
```

程序和参数bin是上一轮本地数值复核重建产物，不在Git内；本批入口显式要求提供，缺失则失败。测试也依赖此固定本地资产，不能宣称干净克隆无需准备即可测试。默认每次创建新的build目录；显式`--output-dir`必须不存在。加`--require-hardware-ready`预期退出2。

下一批先定义逐算子OP_PARAMS和错误/完成语义，建立CPU下发→真实算子→DMA回读比对的仿真闭环，再做组件实现与板测。随后逐层扩展、补齐关键点INT8包，并验证唯一DDR通路、100↔125MHz CDC、三槽所有权及显示/素材并发。

本批没有RTL仿真、PDS或板卡编程；原BIST初始自检与5次KEY0通过记录保留，10分钟稳定性仍等待明确用户反馈，当前板卡镜像未重新探测。完整NPU推理、实际fps与工程合拢验收均保持开放。
