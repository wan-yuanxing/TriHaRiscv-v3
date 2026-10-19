# CPU LSU请求队首寄存边界

第14轮真实最差从两表项请求FIFO的rd_ptr经返回metadata选择、load旁路进入下一次store，setup -3.247ns。目标是保持原队列协议和全部周期，用直接寄存的队首数据替代rd_ptr输出mux；不增加load延迟。

复用原两表项环形FIFO的入队/出队/计数规则，将物理存储坐标从固定bank0/bank1改成head/tail：head=ram[rd_ptr]，tail=ram[~rd_ptr]。实际pop时交换head/tail；入队时按原占用决定写哪个表项。满时push仍拒绝，即使同时pop；空时pop仍忽略。空队列残留输出也保持，不能使用通常只保证valid数据的skid buffer来代替。两份36位数据状态不增加，移除原两指针；其他深度保留原实现。

- [x] 父版实际网表结构RED：36位data_out含组合mux。
- [x] 深度2及4各10001周期，比较全部valid/accept及36位输出（包括无效残留、reset、非法push/pop、满/空同时push/pop、无效X输入）；独立顺序队列oracle核对有效流。同一最终测试在原FIFO也通过。深度2实际3689次入队/3670次出队、606次满时同时push/pop、618次空时同时push/pop。
- [x] 仅改变两表项存储坐标；实际新ADS网表36位输出全部直接来自FF，相同测试GREEN，真实输出损坏被拒绝。
- [x] 整核三种背压×两模式按序/旧逐周期、IRQ及部件/固件回归通过；24项正例和6项预期拒绝，输入/外部模型/输出哈希核验一致。CoreMark周期/WB/CRC保持原值，无load延迟增加。
- [x] 原100MHz全约束后布线六项核验及独立只读复核完成，保留实际失败结果。

结果：CPU-only6806 LUT/5207 FF/32分布式RAM单元/0 DRM/4 APM，224 IO另计，比第14轮+93 LUT/-2 FF。FIFO层次8→58 LUT、76→74 FF；状态位减少不等于面积减少。原生PDS返回0、宿主return2/TIMING_FAIL，230次主详细迭代到0未布通，完整505.554秒，含182秒hold修复。

实际setup Slow/Fast -4.936/-0.103ns，hold +0.116/+0.101ns，脉宽 +4.346/+4.345ns。最差setup较父版恶化1.689ns，100MHz未通过；本轮只证明队首结构和定向功能，不能称时序优化成功。

新最差data_rdata_i[23]→load格式/旁路→下一次地址加法→mem_cacheable_q，15级逻辑、逻辑2.891ns/布线12.610ns。操作数相关两段连接2.665/3.466ns，物理局部性仍是主要待检问题。下一步冻结同一RTL，只改变物理区域至单个完整时钟区域，原时序/IO/hold不变，另存对照，不继续叠加RTL。证据`docs/verification/cpu/lsu_head_timing.json`。
