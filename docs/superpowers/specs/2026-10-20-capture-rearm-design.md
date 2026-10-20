# F4c2a 受控多帧采集

本批延续用户已授权的 Video 实施和三槽集成工作，先完成可独立验证的采集核重武装；
不操作硬件，不改变既有采集 ABI1、CPU 全局帧所有者或静态全屏板级默认行为。

## 方案与边界

采用 `video_capture_ingress`、`video_three_branch_capture` 的 `ENABLE_REARM=0` 参数。
显式开启的集成实例可以在一次协调 reset 内顺序采集多帧。默认实例仍只能采一帧。
相比每帧复位 FIFO/DDR/显示，这个方案保留跨域指针和其他消费者的引用；相比另建
采集核，它复用已经验证的三路算法、DMA 和仲裁器。

仅成功完成可以重武装。`req_ready` 在上一帧 good EOF、三路数量/CRC 与写响应核验
完成、accepted 已消费、completion 握手后才重新开放；还必须所有 writer 可接描述符、
端口排空、没有输入残留或健康错误。请求方必须先复制完整记录，再拉高 completion_ready。
这里的消费是采集核握手，**不是**旧 MMIO ABI1 的 ACK；MMIO 不因此变成多帧接口。
CPU 负责选取无显示/计算引用的 FREE 槽，RTL 只使用锁定的请求身份和权威槽地址。

## 数据和跨域顺序

成功 EOF 是入口该帧最后一个 FIFO 字，源端发送后停在 STOPPED，不继续发送视频。
核在新请求握手边沿清理 packer、两个 scaler、计数、CRC、EOF 与结果记账，再发新
DMA 描述符。入口与 FIFO 不接局部 reset。上填充写完才切换 arm_toggle。

入口仅在无 fault/overflow/cancel 的 STOPPED 接收下一次 arm，重置源端坐标、CRC、
数量和峰值，然后等待完整 frame_start。重武装到达同一拍的源帧主动跳过，避免旧
坐标参与第一像素；首次 arm 仍保留原有首拍采集语义。arm 两次切换之间至少有
完整帧和完成握手，不能发生未消费 toggle 覆盖。像素时钟停止时不会伪造已采帧。

## 错误和保留

abort、坏帧、超时、错误响应、离线和未知元数据沿用粘滞错误和 AXI 排空策略。
失败完成被消费也不能重启；需要外部可信协调恢复。新请求不能清除任何 fault。
已发布的完成记录及其统计在背压下保持，到下一次合法请求才更新。晚到错误可
锁止下一请求，但不撤回已经发布的成功记录。禁止以重武装复位已发布 AW/W/B。

## 验证

新的 `capture_rearm` 套件接真实 ingress/FIFO/stream register/三分支核与延迟 AXI
模型，逐字节独立验证 raw、2×2 preview、5:2 bilinear BGR NCHW 和 padding。
每帧换图、换槽，循环复用槽；保持 accepted/completion/final B 背压，核验身份和
记录不被下一请求覆盖。覆盖不同时钟比、停止后恢复像素时钟、FIFO 多轮回绕、
三种 AXI 阶段 abort、接收错误、超时、晚到错误及失败后锁止。
旧默认 ingress、three_capture、capture_mmio 和 frame_pool 套件回归。
新开关开启实例做 PDS 组件综合，单独报告估计时序；不宣称布线、板测、CPU执行、
跨 master 可见性或连续视频验收。CPU/fabric/MMIO扩展与真实退休证明仍在下一批。
