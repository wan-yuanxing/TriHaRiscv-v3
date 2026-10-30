# 真实卷积层 RTL 全尺寸对照

2026-10-21。承接用户“复用 NPU 已有数值成果，补齐 RTL 逐层对照”的授权。当前冻结 bbox16 包的 **47 个卷积层，在三组输入上共 141 次全尺寸 RTL 仿真全部通过**；实际输出 11736000 字节逐字节一致。32 个非卷积算子和整图硬件串联仍未验证。

## 复用资产与覆盖

使用外部 `npu_zgtc` 基线 `178c3ad1ba515d43725dd80ab19e20b50d471413` 的程序、参数镜像、量化 NPZ、整数参考及历史 golden。没有重新校准或训练，也未修改权重、上游 word 或产品 RTL。复用上一批三组各79输出的程序回放/整数参考一致性证据；本批按冻结程序参考导出每组完整80张量，另核194项NPZ参数数组和27个历史检测头SHA。

| 内容 | 实际覆盖 |
|---|---|
| 输入 | zero、full255、pattern，均为完整 1×3×320×320 输入及其真实中间张量 |
| 卷积层 | 30 DenseConv + 17 DWConv，每组47层，共141次 |
| 层尺寸 | 保留全部真实通道/空间尺寸；最大输入/输出409600B；没有裁剪、抽样或缩通道 |
| 输出 | 每层全部字节、重复/遗漏写、范围、选通宽度/对齐和完成响应检查 |
| 计算 | 名义MAC合计253569000；跳过padding后的有效MAC合计252434112，逐层与RTL计数一致 |
| 尚缺RTL | Add2、MaxPool4、NearestResize2、Transpose9、Reshape9、Sigmoid6，共32项 |

每层输入取自主机参考中间张量，独立送入真实 `npu_scalar_conv`；上一层的硬件输出没有串接为下一层输入。故本结果证明各卷积层与冻结数值契约一致，不代表79算子整图或检测后处理已经硬件执行。

## 仿真方式与证据

DUT 始终保持上一批 SHA256 `ea9cf1af7677aa05f6ed84c7d8d6802535b204d843e38cfa144bbf0ca294b6bd`。客户端存储模型只通过公开请求/响应端口提供完整16B行，不使用内部force、跳MAC或软件替换卷积。每层保留实际输出文件，宿主再次与expected全字节核对。

全141采用Windows原生编译仿真。工具来自锁SHA的第三方 `dau-dev/verilator-python` wheel，包版本5.48.0，二进制实际自报 `rev vUNKNOWN-built20260516-4e853d8`；不把包版本视为官方发布证明。只解压到忽略的build目录，复用Vivado2018.3自带g++6.2，不安装全局环境或使用WSL。工具与运行库、生成C++、二进制、DUT、资产均绑定hash。

Verilator为二态，另以ModelSim四态仿真独立复核pattern输入的op24/41/42/48：DW S8→U8、Dense64 U8→S8、Dense3×3 S8→S8、DW S8→I16。两后端7400字节输出完全相同，有效MAC分别50176/6400/784/3136。两者存储响应延迟不同，不要求周期相同，也不由仿真速度推导板上性能。

完整结果为隔离工作树 `build/npu/layers-rtl-20261021T092832_605526Z/result.json`，`status=PASS`、`full_suite_qualified=true`。最终资产为 `build/npu/layer_assets_full_20261021_final/manifest.json`。独立规格审查核对全部141层、2145产物、919跟踪输入及66工具/运行库hash，全部一致。具体结果、审查及主工程复测位置见 [机器摘要](evidence/layer_validation.json)。

规格与代码质量审查最终均通过，无剩余阻塞项。迁回主工程后，26项测试、pattern四代表层原生编译复测和op42的ModelSim入口复测通过，结果为 `D:/FPGA/TriHaRiscv-main/build/npu/layer_handoff_20261021/`。复制瞬间88个既有文件保持哈希，上一批34文件交付保持不变；Video renderer计划、测试及STATUS的并行变化单列保留，本批不恢复其他路线内容。两端台账仅追加。

## 失败、修复和复现

资产准备12项、层仿真入口10项、原生硬件小fixture4项测试通过，保留先失败后通过日志。真实反例覆盖参数/资产破坏、输出注错、超时、原件/副本注改和优化模式拒绝。审查复现并修复了manifest解析后/冻结前、segment校验后/冻结前的身份窗口，现先冻结再解析，并将封存副本与原声明digest逐项核对。主机资产seal前也复核worker预报的全部产物hash。

只运行子集时明确返回 `PARTIAL` 且完整资格为false；单层可通过但不冒充全47层。完整资格要求三输入、47个支持算子和141次运行全部齐全；失败不能被其余层成功覆盖。

在主工程运行，准备输出目录必须为新目录：

```powershell
python scripts/npu/prepare_layer_tool.py
python scripts/npu/layer_assets.py --npu-root D:/FPGA/npu_zgtc --output build/npu/layer_assets_replay
python scripts/npu/run_layer_rtl.py --manifest build/npu/layer_assets_replay/manifest.json --cases zero full255 pattern --simulator compiled --jobs 3
python scripts/npu/run_layer_rtl.py --manifest build/npu/layer_assets_replay/manifest.json --cases pattern --ops 24 41 42 48 --simulator modelsim
python -m unittest discover -s scripts/npu -p test_layer_assets.py -v
python -m unittest discover -s scripts/npu -p test_layer_rtl.py -v
python -m unittest discover -s scripts/npu -p test_compiled_layers.py -v
```

工具目录已存在时保留原件并核对provenance.json；也可用 `TRIHA_VERILATOR_ROOT` 或 `--verilator-root` 指定已封存工具。已有工具wheel可用 `prepare_layer_tool.py --wheel <文件>` 在新输出目录按锁SHA解压。

## 后续门槛

当前47层均由独立主机输入驱动，32个非卷积RTL、全图缓冲生命周期及任务串联仍开放；最终五点关键点INT8与真实图精度也未验证。此次不包含CPU/MMIO/AXI重复签核、生产fabric跨master可见性、物理DDR/CDC、整机资源/时序/fps或板测。

本轮没有修改DUT或FPGA约束，故未重新执行PDS；上一批100MHz组件结果保持原证据身份。没有JTAG、串口、Flash、提交或推送操作。历史BIST初始灯态/KEY0五次通过，以及10分钟稳定性仍待明确反馈的状态保留。
