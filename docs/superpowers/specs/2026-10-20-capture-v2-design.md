# F4c2b 多帧采集控制 ABI2 与驱动

本批延续已授权的独立 Video 开发，不等待 CPU 性能优化。采用独立 ABI2 子窗口
`0x20012000/4KiB`，保留采集 ABI1 和显示 ABI。最终 fabric 必须优先译码独立
子窗口，再进入旧 Video 大窗口；本批不替 CPU 安装正式译码或决定 DDR 排序。

相比修改旧 ABI1 的 ACK 隐式重启，显式 REARM 能让软件确定事件已消费且核就绪；
相比每帧协调复位，它保留 DDR/FIFO/显示引用。新端点复用 ABI1 的寄存器布局，
单独JSON和生成头锁定版本2；不改变原文件或原板级实例。

## 生命周期

单一 CPU 所有者先从全局三槽库预留FREE槽，再写slot/frame/version/generation，
fence后SUBMIT。非零frame及有效槽/预处理版本校验，shadow和请求在job期间冻结。
generation允许任意32bit值，由端点锁存并随accepted/completion回显；核心仍只
回传slot/frame/version。它不是核端跨reset代际证明，endpoint/core/source必须协调reset。

端点立即将核的事件复制到保持邮箱；软件读取整个记录再ACK。成功完成必须有
accepted、匹配身份/权威地址、精确三分支数量/字节、合法FIFO峰值和port_drained。
失败记录也必须有真实排空证明。完成ACK仅消费邮箱，不授权新采集。

只有两个事件均消费、上一job成功、核req_ready、端口排空、无残留核事件且无错误，
REARM_READY才有效；写独立REARM命令清理job控制状态，之后可写下一请求。
REARM不产生arm、不复位FIFO/DDR/显示、不分配全局槽。held记录保留到后续同类
事件覆盖，pending之外的旧记录不具备事件有效性。失败或协议/健康错误粘滞锁止，
不得靠ACK、CONTROL或REARM清错。已发布成功记录不可被晚到错撤销。

## 软件与可见性

`video_capture.h/.c`提供启动、提交分配记录、完整事件读取/资格核验、ACK及REARM。
回调read32/write32只有完成总线响应才能返回成功；失败写可能已执行，调用方必须
保守保留预留槽。驱动不自动重试SUBMIT/REARM/ACK，也不隐式释放CPU槽。
完整读事件只在全部读成功时更新输出；用allocation核对身份、地址、计数与版本。

MMIO fence只约束控制写序。三路B响应退休不表示跨master DDR数据已对NPU/CPU可见；
调用`video_frame_pool_capture_done`前仍须平台真实可见性证明。本批仿真验证C库的
逻辑调用顺序，不能用虚拟fence冒充物理可见性。全局显示/NPU引用管理不迁入RTL。

## 验证与边界

先保存基于ABI1的第二次提交失败RED，再实现新端点与显式REARM。新suite包含
AXI-Lite独立AW/W、响应背压、字节写/坏地址、事件ACK竞态、成功/失败排空、
错误/旧身份、generation回显和重用规则。接F4c2a真实采集核，连续换槽换图验证
三分支数据和事件；实际本机C驱动的读写事务回放到RTL，RV32I只交叉编译。
驱动逐点I/O失败测试和关键变异均记录，独立审查后精确本地提交。
组件综合、布线、板测分开报告。共享DDR仲裁、正式CPU执行、实际像素退休及连续
视频带宽仍留后续，不以这个接口组件替代系统验收。
