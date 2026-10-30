# Video链路高价值系统仿真

本批用四个短场景补充可读的 Windows ModelSim 原生波形；完整通过日志、WLF/VCD 和输入哈希由机器证据索引绑定，见 `evidence/video_high_value_waveforms_20261030.json`。测试台和生产 RTL 均未修改。

| 证据 | ModelSim 顶层 | 关键结果 | 截图时间窗 |
|---|---|---|---|
| 采集重武装 | `tb_video_capture_rearm` | 7 次采集成功、7 次重武装、18522 B 写入 | 0--120000 ns |
| 显示槽所有权 | `tb_display_slot_owner` | 128 位状态检查 155 项通过 | 0--900 ns |
| 共享 DDR 背压 | `tb_video_memory_scheduler` | 12 次读、12 次写，读写最大等待均为 0，配额 4 | 0--2000000 ps |
| 采显联合 | `tb_video_shared_memory` | 7 个任务、7800 像素、13 次光栅、重叠 11690 拍，欠载 0 | 0--2000000000 ps |

采集波形显示请求接纳、三路写入计数、响应排空、完成事件和错误保持。槽所有权波形显示提交、实际生效、帧代次、`RETIRING`、释放确认和空槽位图的顺序。背压波形显示读写握手、仲裁计数、等待期间的 `busy` 与排空；联合波形把帧身份、槽复用、提交/释放、共享端口读写和像素输出放在同一时间轴上，并直接观察 `underflows=0`。

四个场景的完整原始波形仍保存在 `build/video-key-simulations-20261030/{capture,slots,backpressure,shared}/`，原生截图与 SHA-256 记录在机器证据中。截图来自 ModelSim Wave 窗口，未重绘，鼠标指针位于截图区域外。

这些结果证明数字测试台中的握手、所有权和背压行为。它们不替代完整回归、PDS 综合/布局布线、外部 HDMI 电气时序、板级吞吐或真实 NPU 推理验收。