# NPU 单算子控制与数据接口

2026-10-21。当前实现是单通路 Dense/DW 卷积组件，CPU 逐算子配置。端点尚未接入正式 SoC fabric、物理 DDR 或异步桥；本接口不代表完整 YuNet 或五点功能交付。

## 控制面

AXI-Lite 32 位、同钟、4KiB 窗口 `0x20000000`。唯一寄存器源为 [npu_regs.json](../../config/npu_regs.json)，运行 `python scripts/npu/gen_regs.py --check` 核对生成的 Verilog/C 定义。ID 为 `0x4E500001`，CAPS 为 `0x00010003`，表示 Dense/DW、单通路。

| 偏移 | 寄存器 | 含义 |
|---|---|---|
| 0x00 / 0x04 | ID_VERSION / CAPS | 只读身份、能力 |
| 0x08 | CONTROL | 全字写 1 启动 |
| 0x0C | STATUS | bit0 IDLE、1 BUSY、2 DONE、3 ERROR、4 PLATFORM_FAULT |
| 0x10 / 0x14 | IRQ_STATUS / IRQ_ENABLE | bit0 DONE、1 ERROR；状态 W1C |
| 0x18 | ERROR_CODE | 1 配置错误、2 累加溢出、3 shift 非法、4 存储响应错误 |
| 0x1C / 0x20 / 0x30 | OP_TAG / FRAME_ID / GENERATION | CPU 提供的任务身份，START 锁存 |
| 0x24 / 0x28 / 0x2C | TOTAL / COMPUTE / DMA_WAIT_CYCLES | 完成后冻结，饱和至 0xFFFFFFFF |
| 0x100～0x110 | INPUT / WEIGHT / BIAS / REQUANT / OUTPUT_BASE | 5 个 16B 对齐基址 |
| 0x114 / 0x118 / 0x11C | INPUT_WH / CHANNELS / OUTPUT_WH | 宽或 Ci 在 low16，高或 Co 在 high16 |
| 0x120 | KSP | kernel[1:0]、stride[9:8]、padding[17:16]、DW[24] |
| 0x124 | FORMAT | input_signed[0]；output_format[9:8] 为 1 U8、2 S8、3 I16 |

普通参数写支持 WSTRB 合并；未定义位写非零、只读写和非法操作返回 SLVERR；越窗/未对齐地址返回 DECERR。AW/W 独立接收，B/R 背压期间保持稳定。

CPU 由单一软件所有者使用 [驱动](../../sw/drivers/npu_operator.c)：probe → 确认空闲且没有待确认完成 → 写参数和身份 → START → 轮询或中断 → 核对身份/错误/结果 → W1C ACK。存在活跃任务、未 ACK 的完成或平台故障时拒绝新 START；任务活跃或有待 ACK 完成时拒绝参数写入。DONE/ERROR sticky，新事件优先于同拍 W1C。状态读取不清事件。

快照先读 sticky IRQ_STATUS，观察到完成后再取冻结状态、计数与身份，避免完成边界混合快照。ACK 读回端点后才清 CPU pending。驱动不提供多核/多线程互斥、cache 维护或跨 master 写可见性协议；正式 fabric 必须提供这些保证。没有异步 abort；严重 DMA fault 需要 CPU、端点和 AXI 通路协调复位，复位不充当在途事务取消。

## 数值与地址

NCHW，输入 W/H 为 1～320，Ci/Co 为 1～64；kernel 为 1/3、stride 为 1/2、对称 padding 为 0/1。DW 要求 Ci=Co。输出按 `floor((input+2*padding-kernel)/stride)+1` 推导并逐项校验，最大可为 322。

输入 U8/S8、权重 S8，权重顺序为 Co16_K_lane；Dense 的 K=Ci×kernel²，DW 的 K=kernel²。bias 为每通道 little-endian I32；requant 为每通道 I32 multiplier、I32 shift 双字，shift 为 0～63。逐 MAC 检查 I32 溢出，乘积 I64；按绝对值 round-to-nearest-even 后恢复符号并饱和，U8 为 0～255，S8 为 −127～127，I16 为 −32767～32767。无隐式零点偏移。

引擎只访问 `0x82000000..0x87FFFFFF`，在任何 DMA 前扩位检查全部派生长度/尾址与输出重叠；输出不可覆盖输入、权重、bias 或 requant。所有配置在 START 锁存，每任务使缓存失效。部分结果出错时不可作为完整输出消费。

## 数据面与验收边界

AXI128，同钟、单在途、单拍 INCR、SIZE=4、LEN=0、ID=0；16B 对齐，输出按元素设置 WSTRB。AW/W 可任意先后。完成必须等待最后成功 B 响应。DMA 自身检查 `0x80000000..0x87FFFFFF` 和非空写选通；引擎使用上面的更窄范围。

RID/BID、RESP、RLAST 协议错误锁存 fault，阻止复用直至协调复位。RLAST=0 时继续排空到 LAST 再报错；非法本地请求报错而不锁平台故障。合法背压不设固定等待超时。

真实 CPU 联测中的 CPU 与 NPU 使用同一字节 DDR 模型，CPU 读取使用 TB 本地端口，未证明生产 fabric 仲裁、跨 master 可见性或 cache 一致性。100MHz PDS 使用完整可控/可观测的扫描边界，资源含 542 个边界寄存器。物理 DDR、100↔125MHz CDC、整机资源/时序、完整网络及最终五点 INT8 仍需后续验证。见 [验证记录](../verification/npu/2026-10-21-operator-loop.md)。
