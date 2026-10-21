# F4c4c 共享读仲裁与完整记录叠加链

2026-10-21，基线`3f34cce`，Windows原生。新增`video_read_arbiter`和显式组合
`video_record_renderer`，旧生产RTL、ABI与C库保持。机器绑定见
[record_renderer.json](evidence/record_renderer.json)。无本批COM/JTAG、Flash或板测。

## 组合和生命周期

一个AXI128出口由外部RAW读取客户端与`avatar_ddr_cache`共享，再接旧唯一
`video_shared_ddr`读口。原写读scheduler及原生DDR桥保持不变，不增加物理DDR通路。
RAW紧急时最多连续授权4个burst后服务等待素材；非紧急轮转，可配置额度1..16。
只有一个请求方时直接服务。额度限制burst数量，不保证实际时间或显示截止期。

最多一个总在途事务。源AR锁存后才公开到下游，payload保持到实际握手；R只按
锁存owner路由，不能依据RID改owner，即使两客户端ID相同。owner独占RREADY，
其背压期间另一客户端不能抢走数据。接口限16B对齐、INCR、1..16拍、不跨4KiB
及0x80000000..0x87ffffff；非法/未知描述符不公开到下游并粘滞fault。

online/外部memory_fault、错RID/RESP/LAST/未知响应及意外R分别检查。错误响应仍
路由给原owner，按公布拍数排空；故障停止新授权，不能撤回已公开AR，也不能用
早到LAST缩短排空。意外R、错RID/LAST或未知响应使排空可信性丢失直到协调reset，
已有故障不屏蔽后来stray。下游AR真正握手同拍允许零等待R，未接纳AR时提前R报错。

素材从真实DDR地址读入原封存cache，CRC通过最后texel才就绪。pixel-local cache
ready之后再捕获稳定id/generation，接到原`display_record_pixels`与真实固定拍
provider。每请求素材key、RGBA、13周期输出对齐、实际首像素commit及保持的本地
退休贡献沿用既有组件。素材仅一份，直到全部域协调reset；退休贡献不允许覆盖cache。

`faults[0/1/2]`分别为记录像素、素材装载、读仲裁，三个错误码独立交平台协调
恢复。它们不是统一的软件事件或自动回滚协议。已经证明的本地历史完成不因后来
独立端口故障撤销；平台须按各组件故障状态控制全局调度，不能仅凭某个commit或
`port_drained`将CPU槽改为FREE。

外部RAW像素、坐标/同步及slot/frame/generation由调用者提供。本批没有从core
延迟反馈冒充像素身份，也没有联接实际`raw_display`标签、scanner/owner退休或
显示MMIO。已有`video_pipeline`继续RAW-only；本组合不公布正式系统三模式能力。

## 可复验入口与测试依据

```powershell
python scripts/video/run.py --suite record_renderer
python scripts/video/run.py --suite avatar_ddr
python scripts/video/run.py --suite shared_video
python -m unittest discover -s tb/video -p test_*.py
python scripts/video/build_pds.py --target video_record_renderer --stage synth
```

显式JSON列8个生产源及7个测试源；测试源包含旧共享端点、桥、guard、数字内存和
两个TB。生产组合逐端口连接，未递归搜集RTL；guard用于实际提交夹具的前置校验。
Python按记录解码调用独立整数数学参考，预先生成RAW/BOX/AVATAR逐像素RGB/标记。
素材RGBA、CRC及RAW内存页均来自独立字节夹具，不根据DUT输出身份制造返回数据。

仲裁14个定向场景覆盖紧急额度、非紧急轮转、相同ID、AR/R停顿、掉线和外部故障、
错RID/RESP/早LAST、提前R、未知描述符/响应/VALID、非法size及已故障后的意外R。
集成6场景为80×64探针、异钟比、素材未就绪时先提交AVATAR、错误CRC、在途协调
reset重装，以及完整800×600。光栅W+8/H+4用于数字像素验证，未验证1056×628
VESA物理时序。完整尺寸和小探针分别记录，后者不冒充正式帧。
最终14个协议与6个集成场景全部通过。完整场景核对480018个RAW有效像素、
480000个BOX有效像素和480000个AVATAR有效像素，实际commit4次、素材退休1次。

集成中RAW字节读取与素材装载同时经过实际旧scheduler/原生桥和唯一数字内存模型。
每场完整素材读取262144B、1025个asset burst，另一客户端核对65616个128bit拍
（1049856B），共5126个native命令。素材封存后再核对三模式像素；源RAW像素模型
与RAW AXI流量模型分开，不能据此宣称实际扫描器读取与显示截止期已联合验证。

像素期望按测试侧pending记录、实际SOF及素材就绪选择，再与13级历史输入对应，
不以DUT输出mode选择期望。逐拍核对RGB、框/点/头像/故障标记、同步、坐标和
slot/frame/generation/mode/seq；commit背压20 core拍，同帧AVATAR转RAW只给素材
退休贡献，保持至消费。等待素材场景额外完成一次AVATAR到RAW切换；CRC失败保持
AVATAR pending、无commit及素材ready。最终逐场计数和全部SHA256见机器摘要。

旧avatar_ddr组件24场景及shared_video的24份仿真日志通过；Python109项通过、
1项Windows符号链接权限跳过。只重跑这两套受影响旧回归，未声称全量all通过。

## RED、变异和审查

新增模块前两个TB分别因模块缺失编译RED，保存原文件和日志，不描述为已有行为
失败。实现首次Icarus编译暴露二进制常量紧邻问号的词法问题，添加空格修正。
PDS首次不接受生产实例的`.*`，后改为逐端口显式连接；独立审查核对171个端口
与原连接语义完全一致。FDC输出glob收窄为明确result输出，避免包含result_ready输入。

素材等待场景曾停在退休应答：测试在pixel上升沿+#1拉高ready，到下一个core
下降沿立即清零，可能完全没有经过core上升沿。原激励保留实际4.180432ms
`TEST_RETIRE_ACK_MISSED`复现，独立最小RED/GREEN确认0次/1次握手。测试改为先等
core下降沿再拉高，覆盖下一个完整采样边沿；未为此改生产RTL。

独立审查另发现集成TB只检查commit身份与保持，提前commit变异曾存活；既有独立
record_pixels测试的首输出约束没有失效。新TB在实际out_de/out_sof出现并核对像素
后记录其seq，core禁止在该证明之前发布commit。保留原存活变异与新增监视器检出
`RENDER_UNPROVEN_COMMIT`的RED，随后原实现完整重跑。

八项隔离变异分别破坏按owner路由、紧急额度、已公开AR保持、按拍数排空、provider
身份、源generation、像素域素材generation及真实输出前commit，均由指定断言检出。
独立协议探针另覆盖1/16拍、零等待
响应、未知/意外R、故障排空和边界，额度1/16的紧急与轮转均检查；报告与哈希由
机器摘要绑定。审查发现及修复与父任务回归分别记录，不冒称独立重跑全部系统。

## 综合、文件保护及下一步

PDS组件综合13998 LUT、16295 FF、64 DRM、6 APM、0锁存器。core8ns最差setup
估计-3.630ns，路径从素材burst计数寄存器经过合法性/授权逻辑到组件d_arready
输出pad；pixel25ns+12.607ns，稳定CDC束6ns+5.172ns，最小hold-2.470ns。
综合报告明确Some Constraints Violated；工具执行成功不表示125MHz闭合。

14项约束适用，0 error/critical，118项警告包含宽cmd_data对象集合和未指定物理
I/O；5755组件端口位超过器件300物理I/O。采用零同钟端口预算，当前输出pad和
高扇出时钟估计影响边界路径；实际内部互连接入后仍须按真实路径收敛并布线。
ASYNC_REG忽略等诊断保留，不宣称物理CDC签核或系统时序完成。

起始466项保护中465项保持；`rtl/soc/cpu_native_axil.v`在本批期间出现独立CPU
路线修改，另存只读快照并保持未暂存，未由Video恢复或纳入提交。57项其他路径
现状保持，STATUS既有NPU追加保留；旧入口除本批hook外原始字节一致。交付18文件。

下一步以实际RAW扫描器身份和owner联合退休接入为目标，优先处理真实内部互连下
的core时序，再扩展正式MMIO/采显闭环。CPU/NPU全局fabric、物理可见性、不可背压
HDMI、系统资源与带宽、运行中素材替换、布局布线和板测仍须独立验收。
