# CPU数据旁路tag与提交控制分离计划

目标：切断第12轮真实data_ack→stall→WB tag→操作数→分支/PC路径，保持六级、原时钟/IO/hold和所有有效行为。

原rd_e2/rd_wb兼作RF提交、冒险控制和宽数据选择；其含当前stall/issue_stall。新增只用于数据选择的tag，由已注册valid、rd-valid和opcode决定；原RF写口、scoreboard和全部有效控制保留原tag。两种tag在任何实际发射周期必须相等，加入仅仿真的运行断言。没有新增寄存器级或数据状态。

- [x] 定向RED/GREEN：issue stall和memory ack变化时WB/E2数据旁路不变，原提交tag仍关闭、没有新issue，释放stall后数据/发射正确，fault仍取消。
- [x] 只改pipe controller输出及issue数据选择；未全局替换提交/scoreboard引用。
- [x] 三种种子×两模式旧时序逐周期、新时序按序异常和IRQ，断言实际启用；原部件/故障注入回归。
- [x] CoreMark实际加载的TCM镜像哈希与父版相同，周期/WB/CRC不变；ELF文件哈希不同，分别记录，未将其称为同一ELF。启动/retire/validation/冒烟通过。
- [x] 原100MHz及完整原约束实际后布线六项核验，保存证据。

结果：原生PDS返回0，完整布通，setup Slow/Fast -3.486/+1.027ns，hold +0.117/+0.109ns，脉宽 +4.346/+4.345ns。100MHz仍未通过。较第12轮改善3.284ns，但比第9轮最优WNS差0.422ns；新网表和新布局，不能把旁路局部变化称为全局收敛。CPU-only6685 LUT/5209 FF/32分布式RAM单元/0 DRM/4 APM，224 IO另计。

证据：`docs/verification/cpu/bypass_tag_timing.json`，22项正例、5项预期拒绝、同测试/runner父版RED，以及31项冻结实现输入/588项输出和独立只读复核。

新的最差：LSU请求FIFO地址低位→load返回格式/旁路→分支比较→issue PC进位，17级逻辑、逻辑3.177ns/布线9.976ns。load旁路一段4.227ns，晚到branch request仍进入PC carry。下一步先查实际映射与PC更新表达式，检验是否能把常量增量与重定向选择并行计算，保持完全相同的PC优先级/溢出/hold和六级时序，不新增分支或load延迟。
