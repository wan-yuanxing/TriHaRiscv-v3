# NPU真实单算子闭环 Implementation Plan

**Goal:** 交付可运行的CPU→MMIO→卷积→AXI结果回读闭环。

**Architecture:** 同钟控制端点、单通路Dense/DW与单拍AXI128 DMA分离，接口遵循同日设计文档。先独立组件，再真实固定CPU固件和独立字节DDR模型联测。

**Tech Stack:** Verilog、SystemVerilog TB、Python标准库、ModelSim2020.4、GCC15.2、PDS2022.2。

按subagent-driven-development技能分工实现独立组件，root负责数值引擎/系统整合，阶段审查规格后再审代码质量；继续执行已获用户授权。

- [x] 隔离工作树、Video配置及cpu_axil基线验证。
- [x] DMA：先自校验TB失败，再实现npu_axi128_single；边界/错误/背压验证。
- [x] MMIO：统一JSON/生成器/头文件；先TB，再实现npu_operator_mmio。
- [x] 数值：独立整数oracle、向量与TB；实现npu_scalar_conv及顶层。
- [x] CPU：参数化既有native适配前缀，固定dc00f80源/工具身份，RV32I固件poll/irq/DMA错误回读。
- [x] 回归：组件与CPU闭环、注错反例、复位恢复；输入/产物哈希绑定。
- [x] 组件PDS：显式目标、100MHz约束，综合/映射/布局布线与时序分层记录。
- [x] 规格及质量审查，修复真实问题后复测。
- [x] 检查主工程同名文件未变后迁入本批小范围交付，更新验证证据与两端台账；不连带Video/CPU实验变更。

文件：rtl/npu/{npu_axi128_single.v,npu_operator_mmio.v,npu_scalar_conv.v,npu_operator_top.v,include/npu_regs.vh}；config/npu_regs.json；scripts/npu/{gen_regs.py,run_operator.py}；tb/npu/组件/系统TB和oracle；sw/include/npu_regs.h、npu_operator.h、sw/drivers/npu_operator.c、sw/tests/npu_operator/{start.S,link.ld,main.c}；rtl/soc/cpu_native_axil.v参数化；板级显式组件目标/约束及docs/verification/npu记录。

实际入口按责任分为run_scalar.py、test_dma_runner.py、test_mmio_runner.py、run_cpu_operator.py、build_operator.py。先保留真实失败，再以分级尺寸计算、分级RNE收敛100MHz；驱动完成快照竞态和runner源绑定/优化模式问题也有先失败后通过记录。最终证据与限制见docs/verification/npu/2026-10-21-operator-loop.md及evidence/operator_loop.json。
