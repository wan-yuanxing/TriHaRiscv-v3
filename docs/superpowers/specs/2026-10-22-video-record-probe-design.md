# Video 采显组合可布线边界

用户已同意在原频率和接口契约下继续布局布线验证。本批建立独立
`video_record_probe`，沿用本仓库 NPU probe 的寄存器扫描边界思路，不迁入
NPU 产品代码。相比等待 CPU/fabric 合并或直接把 2227 位接口当 FPGA 引脚，
扫描边界能独立测量当前完整采显组件的内部布线。

core/pixel 分别使用各自时钟和复位、串行输入、shift、capture、串行输出。
core 输入/输出为 708/1148 位，pixel 为 26/341 位；四个时钟/复位端口直连。
输入 shift 寄存器只驱动所属时钟域；输出在 capture 时锁存，否则 shift 时
右移，capture 优先。输入 shift 与输出 capture 可以同拍，捕获当拍旧输入
所决定的输出。不为减少规模绑死在线状态、MMIO、DDR 回复或模式控制。

生成器严格读取当前显式 pipeline manifest、ANSI 接口和 FDC 域划分，生成
wrapper、显式 manifest（含逐信号 offset/width/domain）及派生 FDC；缺失、重复、
未知约束或不一致的 max/min 域声明须拒绝。原 FDC 不改；产品 RTL 只作下述
依据布局证据的 shadow 字节写使能调整。
两时钟仍为 8/25 ns，原四条标量同步器例外、12 条稳定束 6 ns 约束只加实例
前缀。原 8 条 0 ns 组件 I/O budget 由每域真实扫描端口的 max2/min0.5ns
预算替代，组件本体边界变成完整时钟周期的寄存器路径；不是原 I/O 模型的
等价变换。每域增加 setup0.1/hold0.05ns uncertainty，不设置异步 clock group。

该顶层只准 synth/route，不准 bitstream/板测。扫描加载可能产生无效协议
输入，因此不是可运行 SoC、协议适配器或吞吐测试。仿真证明边界映射、移位、
capture 优先级、异步复位和双域隔离，另以真实 DUT 进行 reset/idle 对照；
原采显功能结论仍来自原有协议回归。

首轮布局诊断 core setup 为 −2.841 ns，关键路径经过显示 MMIO 的动态旧
shadow 读取、字节合并和写入，共 15 级逻辑。将该写入改为原寄存器阵列逐字节
使能，未选中字节保持；控制寄存器仍使用原合并逻辑。地址校验、错误拒绝、
AW/W 独立接收、B/R 保持、健康门控、owner、ABI 和响应拍数均不改，没有新增
内部周期。全部 160 项 ×16 种 WSTRB 及拆分 AW/W、背压、错误和复位测试必须
在旧版、新版均通过；布局/布线收益另测，不能用资源下降替代时序结果。

PDS 必须绑定源/快照/生成器/工具/报告，约束全部适用。route 仅在完整双角
报告所有约束均满足时记录组件内部布线通过；全系统 timing_closed、外部
I/O/DDR/CDC 电气验证及板测标志仍为 false。若实际路径失败，保存基线并按
证据处理；允许的 1～2 拍内部流水不改变 ABI 和所有权规则。
