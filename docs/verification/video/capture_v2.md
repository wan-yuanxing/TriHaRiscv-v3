# F4c2b 多帧采集 ABI2 与 C 驱动验证

基线：`f18a657`，日期2026-10-20。独立组件开发，无板卡/COM/JTAG操作。

## 行为

独立端点`video_capture_mmio_v2`采用`0x20012000/4KiB`、ABI `0x00020000`。
配置和生成定义为`video_capture_v2.json/.vh/.h`；兼容性锁保护寄存器语义，JSON
以LF保存，生成注释绑定原始配置字节。旧ABI1、显示ABI、F4c2a生产RTL保持原字节。

新增generation锁存/事件回显及显式REARM；非零frame、有效槽和预处理版本检查。
两个软件邮箱必须消费，成功记录必须合格且全部写排空，核ready且无事件/故障，
才能REARM后接下一请求。ACK不重启、REARM不arm、不局部reset或全局分配槽。
generation不能证明独立复位后的核事件新鲜，端点/核/源仍必须协调复位。

成功记录必须有accepted、身份/权威地址匹配、精确三路像素和字节、合法FIFO峰值、
真实port_drained；失败同样要排空。晚到故障保持历史成功记录，但锁止新请求。
IRQ清除仅消费通知，不能清除sticky_fault。

`video_capture.h/.c`提供enable/submit/read_events/validate_completion/ack/rearm，
回调按窗口偏移操作且返回0须总线响应成功。完整事件只在全部读取成功时交给调用方；
终态sticky STATUS在读记录后再采样，故障通知被屏蔽也不能把完成资格误报为成功。
I/O失败不自动重试，可能已执行的写需要调用方保留allocation并协调恢复。

## 测试

```powershell
python scripts/video/gen_capture_v2.py --check
python scripts/video/run.py --suite capture_v2
python scripts/video/run.py --suite capture_mmio
python scripts/video/run.py --suite frame_pool
python -m unittest discover -s tb/video -p test_*.py
python scripts/video/build_pds.py --target video_capture_v2 --stage synth
```

新suite12份PASS日志：8个独立控制场景、3种几何的真实采集核及1份实际C事务回放。
控制测试覆盖七帧复用、独立AW/W偏移与B/R背压、字节写、完整地址译码、generation、
单事件未ACK/核未ready/错误/未排空/坏数量/旧身份的REARM拒绝。核联测使用真实
ENABLE_REARM三分支核、DMA及仲裁器，七帧无reset换图/换槽；三种几何分别10×10、
30×20、40×30，共21完整帧、60039有效字节，独立检查数据、stride空隙、护栏、
CRC与实际AXI B响应。入口PIX/EOF由测试源提供；不是新的HDMI/CDC或800×600板测。

本机真实C驱动224检查、50个回调失败点、4个写已执行后报错场景通过。实际事务
回放逐笔核验139次读、30次写、4个采集事件和13个fence回调标记；事件端为受控
测试模型，真实DMA/数据路径另由三份核联测验证。RV32I/ILP32仅对象交叉编译，
`nm -u`确认无未定义符号；没有执行RISC-V CPU。编译器最初为聚合清零引入memset，
保存对象和源码RED后改为volatile字节清零，行为回归通过且无C库依赖。

旧ABI1两份、frame_pool一份仿真及本机三槽库回归通过；Python110项中109通过、
1项Windows符号链接权限跳过。本批未重跑all或F4c2a的全尺寸suite；F4c2a生产输入
均在保护清单中，未将旧全尺寸/板测证据冒称新ABI2实测。

RED先用原ABI1完成请求/accepted/completion/软件ACK，再尝试REARM，实际被拒绝；
记录在`build/video/capture_v2_red_behavior`。C驱动初始stub RED及后续屏蔽故障RED
分别在`build/video/capture_driver_red`、`build/video/capture_muted_fault_red`。
后者证明仅读IRQ_PENDING会漏报保留的sticky STATUS，父复现和独立复现均RED/GREEN。

十项关键变异均被指定断言检出，覆盖未消费邮箱、核未就绪、忽略排空/数量、错误
generation、失败后重用和驱动代际/排空/故障/原子输出。独立审查对竞态、未知值、
背压与已执行后I/O错误做隔离测试；最终审查结果由机器摘要绑定。

## 综合与边界

PDS 2022.2-SP6.4端点组件综合816 LUT、982寄存器、0 DRM/APM/锁存器。
8ns core约束下寄存器路径估计setup +2.708ns、hold +0.701ns；未约束组件I/O，
没有布线、管脚或物理时序签核。隔离构建首轮漏复制新include而失败；补齐JSON/
生成头/生成器的哈希输入后重新综合通过，原失败日志保留。

409项其他已跟踪文件、31项其他路线原状态保持。精确输入、工具、产物、旧ABI、
源/对象RED、变异和审查哈希见[机器摘要](evidence/capture_v2.json)。

正式fabric必须先译码独立ABI2与显示子窗口，再进入旧Video大窗口。本批不安装
CPU fabric、不决定跨master DDR排序、不自动调用frame_pool_capture_done；调用前
仍需平台可信可见性证明。共享DDR仲裁、CPU执行、真实显示/素材退休和连续视频
带宽仍在下一批，本机fence标记不能充当这些物理证明。
