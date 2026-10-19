# CPU预测表并行选择计划

原100MHz单区域第16轮的前20条存在PC→BTB读选择→RAS CE -1.929ns；第17轮训练→BTB匹配/优先写入→target CE最差-4.776ns。固定32项BTB/512项BHT/8项RAS和原预测/训练周期，不改变预测算法或规模。

读取采用并行匹配、最高编号优先独热mask，再用逐位AND/OR规约选择数据；写入直接用同一最高优先独热命中选择表项，未命中继续原LFSR分配。保留原精确PC优先、仅无精确命中且PC[2]=0时匹配上半word、重复tag最高表项语义及未知比较被if忽略的RTL行为。不新增寄存器级。

独热数据选择参考固定OpenTitan prim_onehot_mux的逐位AND/OR结构，直接适配为扁平端口Verilog；版权/许可证及版本哈希记于适配清单，保留原始28文件。工程无需SystemVerilog生成器或新工具链。

- [x] 原模块/原模块最终fixture通过；候选对固定原模块逐周期对照，32项/普通BHT及4项/GShare配置各4003周期，覆盖全部表状态/输出、重复tag和X输入，并用独立最高索引oracle核验。
- [x] 新增直接维护Verilog及独热AND/OR选择，保留原始28文件及Apache/lowRISC许可；适配清单11项。生产显式清单只连接维护版本，原模块仅作仿真oracle。
- [x] 真实预测输出损坏被拒绝；整核/组件26项唯一正例组、6项预期拒绝，全部输入/外部模型/输出核验；CoreMark周期/WB/CRC和实际TCM镜像不变。
- [x] 原单区域/100MHz全约束完整实现和独立只读复核；未启用IO FF复制，保存实际失败结果。

结果：CPU-only6505 LUT/5207 FF/32分布式RAM单元/0 DRM/4 APM，224 IO另计，比同区域父版少301 LUT（4.423%），FF不变。原生PDS返回0、宿主return2/TIMING_FAIL，74次主详细迭代到0未布通，完整229.631秒。31项冻结输入/232项输出和独立复核一致。

setup Slow/Fast -2.756/-0.054ns，hold +0.109/+0.109ns，脉宽 +4.346/+4.345ns。最差setup比第16轮最佳-2.277ns差0.479ns，不能以面积或优先链结构变化称100MHz通过。新网表和新布局。完整证据`docs/verification/cpu/predictor_select_timing.json`。

全局最差data_ack_i→data_wstrb_o[3]为外部组合控制路径；前20条可见RAS数据路径-2.539ns、BHT计数器CE -2.428ns。BHT源码仍动态读当前计数→饱和判断→动态写表。下一步只把BHT饱和状态转移局部化到各表项，保持512项/2bit计数、reset和taken优先级不变，先用现有完整状态miter核验，再做同样功能与物理检查。
