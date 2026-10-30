# NPU 真实层尺寸 RTL 对照设计

用户在明确“复用 NPU 已有数值成果，补齐 RTL 逐层对照，再做整网联测”后授权开始。本批沿用该方向，验证既有 Dense/DW RTL，不重新校准或改写权重/golden。复用隔离工作树 `D:/FPGA/TriHaRiscv-npu-operator`，交付后按白名单迁回主工程。

## 范围和选择

冻结程序含 79 算子：30 DenseConv、17 DWConv、2 Add、4 MaxPool、2 NearestResize、9 Transpose、9 Reshape、6 Sigmoid。当前硬件只支持前两类，47 层全部真实几何落在 W/H≤320、Ci/Co≤64 内；最大输入/输出 409600B，单输入卷积总 84523000 MAC。其余 32 算子登记 RTL_UNSUPPORTED，不能被主机执行的结果替代为硬件通过。

比较过三种路线：沿用原 32KiB 小场景只能测裁剪数据；扩展真实层内存与完整输出校验能复用现有 RTL；另写完整网络引擎会引入本批无须验证的新行为。采用第二种，ModelSim 用于独立对照，若已有或独立原生工具包提供 Verilator，则用同源编译加速并先做交叉核验。不得使用内部 force、跳过 MAC、取样输出或替换 DUT 算法来加速。

## 资产与独立性

`layer_assets.prepare(output, npu_root)` 从固定 program.bin/parameter_image.bin、量化 NPZ、校准范围及上游 wire 整数参考产生 zero/full255/pattern 三组完整 80 张量。先核对冻结资产 SHA，复用上一批程序重放与整数参考三组各79输出一致的证据，本批逐项核194个NPZ数组及最终27头历史SHA。参数从冻结镜像按既有 Co16_K_lane 切片，不重新量化。

输出 manifest 记录 79 算子库存、每层几何/格式、完整输入/expected/参数 bytes/SHA、全部源与模型的冻结副本身份。每个卷积目录提供 config.json、config.hex 以及 input.bin/weight.bin/bias.bin/requant.bin/expected.bin。固定地址分别为 0x82800000、0x82B00000、0x82C00000、0x82D00000、0x83300000，用于隔离数字层验证，不修改正式 SoC 地址分配。

config.hex 是 32 个 little-value hex word：0..4 基址；5..10 为 iw/ih/ci/co/ow/oh；11..16 为 kernel/stride/pad/dw/input_signed/output_format；17..21 为五段字节数；其余 0。三输入每层均完整 320 模型的实际中间张量，不裁剪、缩通道或调整形状。

## RTL 对照

`tb_npu_layer` 只实例化现有 npu_scalar_conv；客户端存储模型按 16B 行响应真实请求，独立输出区包含哨兵/覆盖检查。所有输出字节逐项与独立 expected 对照，拒绝越界、非法选通、重复或遗漏写，最后响应成功后才能完成。保留实际输出转储。超时根据完整 MAC 与输出量保守计算，失败退出非零。

`run_layer_rtl.py` 读取 manifest，显式选择 case/op 和有界 jobs。编译冻结 DUT/TB，启动前后核验源、工具、资产及生成输入；每层保存命令/日志/周期/全量字节/结果与 hash。默认目标为三输入×47层。只选择子集时结果明确 PARTIAL，不允许生成全47层通过结论。一次层错误不能被其余层成功覆盖。

使用编译仿真时，同一原件还需 ModelSim 对照代表 Dense/DW、U8/S8/I16 及故障路径；编译器仅改变仿真执行方式，RTL 字节不变。两种工具的结果及适用范围分别记录。

## 交付门槛

单元测试先 RED 后 GREEN，真实反例包括参数/资产损坏、输出破坏、源副本变化和非法选择。只有完整执行并逐字节一致的层可记 PASS。最终报告分别给出主机 golden 准备、47 卷积 RTL 验证、32 算子缺口；本批不是端到端图执行、CPU/MMIO/AXI 再签核、物理 DDR/CDC、关键点 INT8、整机资源或板测证据。没有 RTL 变更时不重复 PDS。

外部 NPU 产品文件只读，两端台账仅追加；不提交、推送、JTAG、串口或 Flash。保护其他 Video/技术报告文件，保留原始失败和上一批证据。
