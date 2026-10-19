# CPU FIFO载荷与flush分离计划

目标：第11轮真实data_ack→flush→FIFO宽PC/指令寄存器CE路径；保持六级、零新增周期和原100MHz边界。

复用原双word FIFO控制，满队列不写宽数据；有空位时仅向wr_ptr指向的空槽采样PC/指令，不要求push有效，不由flush门控。计数、指针、valid、fault/分类元数据仍按原flush/push逻辑。

原六级配置的decoder会在valid=0时仍输出原始CSR类别，IRQ inhibit会读取该残留值。因此额外保留每槽/word一位原始CSR历史（深度2共4位），只在原实际入队时更新，flush保持旧值；原fault元数据继续flush清零。原生decoder在有效数据上照旧工作，无效数据的CSR输出由历史位/fault重建，避免推测数据改变中断行为。复用原decoder做CSR静态分类，不手抄指令表。

- [x] 原FIFO必须因空槽不预采样而RED；候选GREEN必须在2000随机周期比较原全部控制/metadata、所有有效PC/数据、满队列、部分pop、flush以及残留CSR分类。
- [x] 只维护decode/FIFO派生及前端连接，原始vendor保持不变。
- [x] 三种种子×两模式旧时序逐周期/新时序按序异常、IRQ、已有部件和实际错误负例通过。
- [x] 同ELF CoreMark/startup/retire/validation/冒烟；保留实测周期。
- [x] 原10ns/IO/hold/multicorner/区域完整新PDS，全部实际时序无违例才认100MHz通过；保存冻结证据，不合并或编程板卡。

本批功能/性能验证及实际物理核验完成，Slow/Fast setup为-6.770/-1.270ns，时序目标尚未完成。依据实际WB旁路tag的stall反馈路径继续诊断，不降低约束。
