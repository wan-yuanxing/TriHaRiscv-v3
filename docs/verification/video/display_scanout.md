# F4c3b 显示MMIO至RAW扫描闭环验证

基线`bf6effc`，日期2026-10-20。Windows原生开发，本批无COM/JTAG/板卡操作。

## 实现

新增`display_scanout_link`及`video_display_scanout`，显式连接原显示MMIO/owner、
raw_display和display_mode_cdc。旧ABI、记录校验器、所有者、raw、CDC及生产C库
保持原字节。新目标只公开MODES=001，BOX/AVATAR由原校验器拒绝；当前板级三模式
诊断镜像不受影响，不能把它的人工叠加能力当作本新目标已接入整记录。

命令握手锁存身份，不发布commit；匹配真实raw commit后才反馈原slot/frame/
generation/seq。每槽保存代际，真实raw release必须匹配已持有的非active引用。
该次替换的旧active引用等待对应新反馈被消费；更早非active的延迟release在下一
命令OFFER/WAIT_RAW期间也可排空。owner继续把release保持到软件ACK；link消费
raw release及owner退休证明均不代表CPU全局FREE。
raw事件本身没有generation字段；回填依赖唯一在途命令和有序按槽生命周期。
它不能识别未协调reset或任意重复同slot/frame的旧事件，不能代替协调恢复。

同帧RAW命令不再次发布raw记录；既有CDC接纳后等raw两周期对齐的pixel光栅帧
边界确认，再反馈原身份。RAW→RAW是幂等模式命令，不重采、重算、释放槽；本批
没有首次像素精确时间戳。完整640B上下文的同帧一致性继续由原owner检查。

无主/错身份/未知事件、raw拒绝/错误或CDC错误保持fault，停止新命令。已公开raw
记录及已证明的反馈/退休继续保持直到消费，不能靠局部reset清账本。fault是独立
平台输出，irq_o仍是原MMIO事件IRQ；没有向旧ABI伪造故障位，正式平台还须接收
fault并协调处理。core/pixel/owner/raw/AXI必须协调reset。

## 可复验入口

```powershell
python scripts/video/run.py --suite display_scanout
python scripts/video/run.py --suite display_mmio
python scripts/video/run.py --suite frame_pool
python scripts/video/run.py --suite raw_display
python scripts/video/run.py --suite mode_resources
python -m unittest discover -s tb/video -p test_*.py
python scripts/video/build_pds.py --target video_display_scanout --stage synth
```

显式filelist为`fpga/pg2l100h/project/video_display_scanout.json`。新套件保存源、
工具、编译物、运行日志及C回放的哈希，期间源变更会失败。组件目标无板级管脚，
只支持synth。

11项link场景覆盖命令/反馈/退休背压、逐槽代际、同RAW等待SOF、错误保守保留、
已公开记录故障后保持、无主/未知commit及两种延迟release互等回归。

| 真实wrapper场景 | 扫描范围 | 记录 / 反馈 / 退休 | 完整像素 / 光栅 |
|---|---|---|---|
| normal | 16×4 | 4 / 5 / 3 | 576 / 9 |
| minimum | 1×1 | 4 / 5 / 3 | 12 / 12 |
| ratio，pixel周期34ns | 16×4 | 4 / 5 / 3 | 576 / 9 |
| raw RID故障 | 16×4 | 1 / 1 / 0 | 0 / 0，保留引用 |
| full，默认25ns pixel | 800×600 | 2 / 2 / 1 | 1440000 / 3 |
| C库实际事务回放 | 16×4 | 6 / 8 / 5 | 512 / 8 |

合计21条raw记录、26条反馈、15条退休、1441676个像素、41个完整光栅，欠载0。
独立地址字节BFM检查AR地址/4KiB/长度/租约，整光栅oracle检查有效像素、同步和
blanking；第一不完整启动光栅不纳入像素计数。缩小参数仅扫描同一固定800×600/
stride2400 ABI记录的左上子区，没有发布可变几何ABI。

普通场景保持commit和release跨多个光栅，分开ACK，并在第一旧release未ACK时
提交第三槽；旧事件和代际不能被覆盖。RAW同帧命令不增加raw提交/退休，BOX请求
明确拒绝；slot/frame在不同generation复用后，反馈仍关联原命令。

本机C测试执行未改动的frame_pool及显示驱动，共1502检查；分配/图完成的前提由
测试模型提供，不是真实采集或NPU推理。实际回调生成103读/1312写/16个fence标记，
8个A标记只等待真实RTL事件；禁止Q/T等反馈注入。RTL独立从真实raw反馈生成MMIO
事件，并逐笔比较C期望值。该工作是离线C I/O回放，没有执行RISC-V CPU，也不把
本机fence标记视为物理内存屏障证明。

旧显示MMIO10项、frame_pool1份、raw46项、mode_resources16项均通过，共90份
仿真PASS日志；Python110项中109通过、1项Windows符号链接权限跳过。没有声称
重跑完整all或本批采显共享DDR联合验证。

## RED与审查

实现前的test-only unsafe join把命令接纳当作commit，行为测试触发
`LINK_COMMIT_PRECEDES_RAW`；它不是已有生产实现，RED快照见
`build/video/display_link_red/20261020T085612_653706Z`。

独立审查复现两种延迟旧release互等：下一命令已OFFER，或record已接纳处于
WAIT_RAW，而raw等待旧事件ACK才继续。按非active账本匹配排空修复后，原独立
108/109测试不改刺激即可GREEN，正式case9/10保留。故障变异还发现只在negedge
检查READY会漏过单次错误接纳，增加posedge故障接纳断言后准确检出。

9项父变异分别破坏seq、generation、退休代际、反馈前退休、延迟release进展、
MODE重发raw、SOF条件、接纳当commit及fault锁止，均被指定断言检出。独立审查
的来源、额外协议/像素/租约检查与关闭发现由[机器摘要](evidence/display_scanout.json)
绑定。初期C严格编译警告、Icarus动态string case崩溃和TB delta采样竞态保留为
工具/测试失败；packed ASCII token及稳定采样修正不改变生产协议。

## 综合与未完成边界

PDS 2022.2-SP6.4综合12174LUT、18123FF、4DRM、4APM、0锁存器。core8ns寄存器
路径估计setup +0.373ns，pixel25ns估计+19.809ns，最小hold估计+0.619ns。
14项约束均适用，0 error/critical；仅scalar同步首级例外，束路径6ns，未整域切除。
首轮PDS拒绝前向声明与`.*`，已明确声明并改49个命名MMIO连接后重跑通过。

组件I/O无端口预算；保留ASYNC_REG属性忽略、常量/悬空清理及constant-probe loop
诊断，未声称全网表无组合环或物理CDC签核。没有布线、外部I/O时序或新板测。
439项其他已跟踪文件与31项其他路线现状保持，本地精确交付18文件。

下一批把本RAW闭环与ABI2采集、Video局部共享DDR及CPU三槽控制组合联测，然后
接BOX/AVATAR整记录/素材退休。CPU/NPU全局fabric、物理跨master可见性、实际
不可背压HDMI连续输入和全尺寸采显并发带宽继续独立验收。
