# F4c1 CPU统一三槽生命周期

基线`9f39ee0`，2026-10-20。依据已批准全屏设计F4、主规格9.2–9.5和用户
“继续执行”，落实CPU唯一所有者；不建立与CPU竞争的RTL全局分配器。

## 选型与本批边界

直接接整个SoC还缺生产fabric、采集重武装、NPU硬件ABI及真实退休生产者；只扩展
显示owner不能汇总计算引用。本批实现可移植C三槽状态库，复用显示ABI/驱动，并以
实际C事务回放到现有显示RTL。统一策略在`sw/drivers/video_frame_pool.c`，不迁移
CPU或修改已验收板级RTL。F4c2再接受控rearm与共享总线；本批不签核DDR可见性。

## 身份、分配与计算锁

所有调用由同一个CPU主循环串行拥有，IRQ只排队，不重入库。帧身份为32bit
slot/frame/generation。初始化显式给generation；每次分配使用全局递增、非零
frame_id和当前generation，轮询选择FREE槽，同时返回公共配置中的raw/preview/
320KiB input地址及预处理版本。至多一个采集任务；没有FREE槽返回NO_FREE，输出
参数不变，记录计数，不覆盖任何引用。frame_id到UINT32_MAX后不得静默回绕；
下一次分配返回EXHAUSTED并进入恢复。新epoch仅在协调清空后换generation。

每槽正常阶段：FREE→CAPTURING→READY→PROCESSING→READY_DISPLAY→DISPLAY_PENDING
→DISPLAYING→RETIRING→FREE。CAPTURE_DONE调用者保证三分支、good EOF及全部写响应
已合格且相关采集写已排空；本库不把普通写结果、ACK或NPU单算子IDLE解释为此证明。

graph_begin选择最早READY且要求NPU IDLE、graph_active=0，锁定唯一frame_owner。
operator_begin/done保持当前frame_owner和软件32bit OP_TAG，未完成算子不允许下一算子。
首tag任意，同图后续tag必须前一个加一（模32bit），允许UINT32_MAX→0；issued计数在
UINT32_MAX时停止新算子并进入恢复，禁止同图完整标签循环。重复/跳号的begin不改
租约且返回INVALID，迟到旧done不能匹配后续算子。这是CPU内部ticket规则，实际NPU
寄存器tag位宽/映射由后续适配层冻结，不能当成已发布的NPU硬件ABI；
算子间IDLE不释放整图锁。最后算子成功后仍保留锁，直到后处理完成、结果发布及
共享工作区全部消费者退休的result_ready调用。只有此时进入READY_DISPLAY并清
graph_active；无脸也是实际完成后的结果，库不制造推理成功。

READY/READY_DISPLAY且尚未持有消费者的帧可显式丢弃；记录计数、身份和非零原因。
其余阶段禁止丢弃。新显示frame_id必须晚于已实际commit的frame，过期帧可丢弃。

## 显示发布与ACK顺序

present先核对640B记录中的身份属于READY_DISPLAY，预留显示引用并冻结待反馈
mode/seq，再调用已有video_display_submit。一次只保留一个在途显示事务。
同帧MODE只允许当前active身份，保持显示引用、完整context仍由现有RTL验证。
任何发布I/O失败都保守进入恢复并保留引用；返回值不能证明SUBMIT没有到达设备。

poll_display使用已有驱动读取保持事件，先验证所有身份/seq/mode/mode_only及阶段，
再调用显式ACK。ACK成功前不改库内active、pending或FREE；ACK失败保持全部引用并
进入恢复。合格commit才使旧active进入RETIRING、新帧DISPLAYING；MODE commit只
更新mode/seq，不增加新帧提交计数。release须匹配RETIRING，允许同一个事件快照
中先commit新帧再release旧active；只有ACK成功后才FREE。拒绝须匹配当前seq、
不能与同一在途commit并存；新帧拒绝回READY_DISPLAY，MODE拒绝保持active。

硬件fault不可ACK清除；合法commit/release/reject仍可在恢复期间排空。未知、旧代、
错OP_TAG、重复/提前完成事件置首错，不推进别的任务。库不自动重试发布，不以计数
或相同seq推断commit。驱动回调的不可缓存映射、已完成写语义和真实fence由平台负责。

## 错误与协调恢复

首错阻止新分配、计算和显示提交，但保持既有引用及当前租约阶段；受影响槽可标记
invalid，对外显示INVALID，不能借此丢弃仍在途的capture/graph/display引用。
合格晚到反馈可排空，不清首错。全局可分配mask在恢复期间为零。
recover要求显式capture/compute/display/mailbox四类已协调清空的完整证明mask，
且generation必须改变，然后重新初始化。证明由真实平台所有者提供；单独复位库、
只看DMA busy=0或NPU IDLE均不构成证明。本组件测试只能验证证明消费规则。

## 验证与文件

先独立字面期望C测试RED，再实现；用现有MinGW实际执行，xPack交叉编译RV32I。
覆盖三槽重叠/耗尽/轮询、共享工作区算子间隙、最后算子至后处理延迟、旧身份/错tag、
MODE无释放、拒绝、同拍commit/release及每个I/O回调失败、ACK前后不复用。
C测试产生实际read/write及消费者反馈事务，SystemVerilog按记录回放到现有显示
端点，逐字核对命令与读值。关键策略变异须在指定断言失败。测试输入的采集和NPU
完成证明为合成事件，不声明真实采集、多主DDR、CPU执行或真实NPU推理。

生产仅新增C头/实现；`tb/video/test_video_frame_pool.c`和`tb_video_frame_pool.sv`
分别验证状态策略和实际RTL回放；`scripts/video/test_frame_pool.py`保存来源/工具/
产物hash，`run.py --suite frame_pool`纳入显式入口。旧显示/采帧ABI、RTL、PDS
约束和物理镜像保持字节。文档/证据、独立审查及小范围本地提交完成本批交付。
