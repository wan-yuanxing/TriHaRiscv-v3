# CPU PC常量增量与重定向选择分离

第13轮实际最差为load旁路→分支比较→issue PC carry，setup -3.486ns。实际ADS网表将CSR/branch重定向mux合进30位加法的每级GTP_LUT6CARRY，branch request直接进入高位carry。

仅调整PC常量增量的组合边界：提前计算pc+4、pc+8，用ADS明确支持的syn_keep保留这两个有实际用途的网络，原重定向/单发射/双发射/hold优先级不变。原ADS手册5.11说明该属性保留net；不全局关闭资源共享、不改变寄存器或分支解析周期。此方案仍需实际综合验证，不能假定属性一定阻止carry融合。

- [x] 父版实际ADS网表结构RED：PC数据输入组合锥中28个carry输出依赖branch/CSR request。
- [x] 独立oracle完成4101周期，含4096组随机更新、reset、hold、CSR/两个branch并发、单/双步长、低位保留和32位回绕；真实PC损坏被拒绝。
- [x] 仅保留有用PC增量边界，单发射不生成PC+8；实际新网表同一结构检查为0处依赖。检查显式列出未展开的子模块输出边界，不宣称跨层组合/CE控制证明，也不等同STA。
- [x] 原整核三种种子、两模式按序与旧时序逐周期、IRQ、fault及组件契约；CoreMark和启动/计数/validation/冒烟通过，23项正例和6项预期拒绝。
- [x] 原100MHz/IO/hold/multicorner及同区域完整后布线，实际六项余量和输入输出核验后记录。

结果：CPU-only6713 LUT/5209 FF/32分布式RAM/0 DRM/4 APM，224 IO另计，较第13轮+28 LUT、FF不变。原生PDS返回0、宿主return2，159次主详细迭代达到0未布通，完整252.369秒。实际setup Slow/Fast -3.247/+1.018ns，hold +0.107/+0.099ns，脉宽 +4.346/+4.345ns；100MHz仍未通过。较父版最差setup改善0.239ns，但比第9轮最优-3.064ns差0.183ns，不能把局部carry分离称为全局收敛。

CoreMark实际加载TCM镜像、单1682259/双1390197周期及WB/CRC完全相同。证据`docs/verification/cpu/pc_increment_timing.json`，31项实现输入/402项输出及只读复核一致。

新最差LSU请求FIFO rd_ptr→response half选择→load旁路→下一次store地址/数据lane，终止mem_data_wr_q[27]；9级逻辑、逻辑1.590ns/布线11.297ns。下一步检查原请求队列能否在push/pop边界预计算完整队首寄存输出，消除读指针mux而不增加load返回延迟，保留全部有效和无效残留载荷、深度/接纳/溢出/异常行为；先用原FIFO逐周期模型验证，不能仅比较valid数据。
