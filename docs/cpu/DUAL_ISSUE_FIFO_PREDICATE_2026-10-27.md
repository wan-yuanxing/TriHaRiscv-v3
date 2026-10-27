# FIFO出队后判定提前 v79

基线v78物理包（v77 CPU＋v78 SRAM）。v78最差-0.175ns，SRAM零标量→fetch1_accept→remaining_r→head1 D。实际byte-zero网络1.729ns，fetch1_accept扇出182；本轮只切断FIFO后半段的晚到减法/比较，不改变LSU、发射、配对或宽payload。

## 实现与边界

对count减0/1/2分别以原count位宽截断，预先计算==0、==1、>0、>1四个标量；以原remove_a/remove_b选择标量，用于原head0/head1更新的过程式IF。原remaining_r仍保留给计数更新。未知选择fallback原式；count减0不能直接替为count比较，否则partial-X计数在原算术中全X的行为会改变。无新增状态或周期，无宽payload复制。

替代方案为寄存pop/延后配对，会改变周期，暂不采用；仅添加fanout约束也不能证明晚到算术已退出。当前方案复用既有标量预比较组织，保留原有FIFO协议。

## 验证门槛

- 先旧版污染remaining红测。3/4位count覆盖全四态表示及全部pop/push/two四态组合，共81920；包含非合法/下溢计数。
- 新版普通/污染均等价，实际next1数据破坏负例检出；独立20821步序列oracle覆盖106合法组合、B-only、push/pop、flush元数据、wrap和后端只在入队写。
- 单/双ordered及IRQ/mret；完整CoreMark/measurement/profile/WB/store对父版比较。原-O2，SRAM/TCM无Cache/DDR。
- 原生映射检查三个预判定锥仅依赖count，且实际head D/CE不再穿越remaining算术输出；保留原其它结构门槛。无未知/歧义才准入独立评审。
- 仅门槛全过才跑单次fresh原100MHz/IO/hold/multicorner/seed1 PNR，按实际六项STA与哈希验收。

## 当前证据

组件`build/cpu/fifo-predicate-red-v79`旧版语义通过、污染remaining拒绝、真实破坏检出；有效候选`fifo-predicate-validation-v79`全通过。完整序列20821步。ordered与IRQ单/双均通过。完整CPU运行`coremark-20261027T081931724362Z`尚在进行。本轮未PNR，100MHz尚未通过。

## 原生准入

完整CoreMark通过，122输出哈希核验；1221907周期/1448448 observed WB，IPC1.185400、短测4.091964/MHz，measurement/profile/WB/store与v78相同。非官方分数或板测。

native compile/synthesize/dev_map通过，68输出已核；CPU-only9619LUT/4972FF/752已含RAM-LUT/4APM/0DRM，较v78 -237LUT/-3FF（不含memory夹具）。RTL无新增状态，但综合合并会改变实际FF计数。

工具合并两个等价判定，12逻辑flags对应10实际节点、head实际消费9个。231个实际head FF、231D/135CE全部检查；predicates锥仅count，head在预判定/原出队及flush边界外没有count/remaining运算或未知节点。不能仅以remaining名称被优化宣称无路径。

工具将部分出队/flush逻辑跨层共享。检查器读取实际LUT/CARRY INIT，按已安装厂商carry选择规则及literal cofactors证明Z/COUT等价，再逐一验证实际pop1的四因子16组合、实际flush三因子8组合，才允许对应控制边界。late_remaining接回实际headD、flags注入pop两个负例均HOLD。完整检查仅为位连接结构诊断，不是STA。

实际SRAM16CE、BTB256WE/624地址/80延迟边界、branch比较及64目标FF/60sum carry仍PASS。独立评审支持单次原约束fresh物理运行：`build/cpu/dual-fifo-predicate-io-physical-v79`，10ns/原IO/hold/multicorner、seed1、PNR600秒/外层900秒。已启动；尚无100MHz通过结论。

## 最终物理结果

完整运行318.435秒，主详细布线118次迭代到0。PDS退出0、验收器记录退出2，TIMING_FAIL。冻结输入、328实际输出、五阶段成功标记及performance一致性核验。

| 检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| Setup | -0.431 | +2.677 |
| Hold | +0.111 | +0.099 |
| 最小脉宽 | +3.655 | +4.202 |

22个Slow违例，TNS-3.990ns。相比v78同10ns的-0.175ns回退；本轮新网表/新布局，不把资源减少或局部结构通过当频率收益。v79不提升默认RTL，不作为优于v78的物理基线，不重跑同候选。历史最佳v57 -0.009ns仍FAIL，100MHz目标未达成。

最差物理寄存器名opcode_e1_q[18]实际逻辑网为pipe0_opcode_e1_w[17]（rs1索引）：rs1==x0译码→branch_taken→resolved0_next[0]→对齐异常→resolved_fault→mispredicted→fetch PC CE，-0.431ns，10级、logic1.735ns/route8.244ns；最后N88网33扇出/2.090ns。不能按物理寄存器名误报opcode bit18或JALR立即数加法。

22违例分布：8条分支方向到fetch branch-PC CE、3条同源到FIFO head0 D、9条SRAM到B ALU、1条SRAM到A ALU、1条SRAM到FIFO head1 D。实际route包FIFO全部231D/135CE、flags纯count及消费、SRAM16CE、BTB/branch/sum均重查PASS，局部预判定结构保留，但全核时序回退。

独立终态评审确认全部哈希/分类一致。下一最小诊断从v78独立派生，方向前预比较目标对齐；taken=1使用目标低两位预判定、taken=0不报错、taken=X/Z保留原taken && (next_pc[1:0]!=0)。保留resolve/stall/异常优先级和next-PC/mtval数据；pipe_ctrl中的同类对齐检查属于另一个消费者，不应误称一并消失。必须覆盖JALR bit0清零、非taken但目标未对齐、未知方向且目标/顺序低位不同，并检查实际fault/misprediction锥绕过方向后低位mux。SRAM→B ALU路径仍需独立处理。本轮未实现该下一候选。
