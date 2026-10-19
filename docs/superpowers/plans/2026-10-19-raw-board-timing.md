# F2 写请求时序修订计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 在8ns core、6ns显示束约束下关闭新raw板级时序，并保留所有公开事务和采集顺序。

**Architecture:** 基于已提交ed8a779，复用video_stream_register，在新video_raw_engine的capture AW与bridge AW之间加入49bit保持寄存。W/B及读owner不改，寄存仅由协调reset清除，错误不撤销已接纳AW。旧双窗RTL和共享桥不改。

**Tech Stack:** Windows Python/Icarus/PDS，既有显式video_raw_board目标。

两轮12个种子均未达最终setup；最佳−0.178ns。两轮最接近通过的关键路径均为
capture.g_dma[0].u_dma.burst_beats → bridge.base_q/CE，故先切写请求控制/数据路径。
PDS原始报告和所有种子已保存，不把失败位流用于下载。

## Task 1: RED

- [x] tb/video/tb_video_raw_engine.sv增加case25/26：force bridge.awready=0，要求上游AW可先接纳进独立项；桥端49bit字段及valid在源故障/DDR失去就绪后保持。
- [x] case25释放桥后等待全部事务排空；case26仅协调复位后恢复全部源/从端，并重新采帧通过CRC。
- [x] 用ed8a779实现运行case25，必须以“No isolated write request entry”失败。

## Task 2: GREEN

- [x] rtl/video/video_raw_engine.sv复用DATA_WIDTH=49的video_stream_register，s_data={awid,awaddr,awlen,awsize,awburst}，m_data依次[48:45]/[44:13]/[12:5]/[4:2]/[1:0]接bridge，独立bridge_awvalid/ready。
- [x] scripts/video/run.py仅将raw_engine用例数从25改为27。
- [x] 运行raw_board定向套件，27引擎场景和板级六场景必须全部通过。
- [x] 独立审查新请求所有权/错误/复位和变化范围，修复实质问题。

## Task 3: 时序及验收

- [x] 原8ns/6ns不变，实际PDS布局布线与全CDC审计通过后才打包/下载。
- [x] 保留完整回归基线ed8a779的36套件/190输入/311日志与85通过/1跳过；明确报告本修订的定向结果，不能称作修改后完整重跑。
- [x] 父审计仅允许raw_engine、对应TB及run.py的raw用例数三项与完整回归基线不同，其余187项保持哈希；run.py其余字节与基线一致。
- [x] 完成四角图、KEY0、普通桌面、持续扫描无欠载的物理验收，更新文档和来源证据并精确本地提交。
