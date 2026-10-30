# 系统互联与存储仿真验证（2026-10-30）

本批复用主工程已有的 Windows 原生 ModelSim 联测入口，补齐 CPU 控制面、NPU AXI128 数据面和 Video 共享 DDR 的可复现结果，并保留两份可展开的 WLF 波形。机器证据见 [system_interconnect_storage_20261030.json](system_interconnect_storage_20261030.json)。

| 场景 | 实际覆盖 | 结果 | 证据 |
|---|---|---|---|
| CPU→Video 控制与存储 | 单/双发射固件 6 个正例；采集请求、三路 DMA 写入、响应排空、IRQ 和完成；2 个负例 | PASS；正例 6，负例 2 均按预期拒绝 | [result.json](../../../build/video/cpu_video_firmware/result.json)、[WLF](../../../build/video/cpu_video_firmware/20261030T055556_583756Z/system_cpu_video.wlf) |
| CPU→NPU AXI128 | Dense U8、DW S8 各轮询/中断；MMIO 配置、AW/W 任意先后、读写背压、输出读回和最后 B 响应 | PASS；4 个正例 | [result.json](../../../build/npu/cpu_operator_20261030_135631_6fe3ddaa/result.json)、[WLF](../../../build/npu/cpu_operator_20261030_135631_6fe3ddaa/system_npu.wlf) |
| Video 共享 DDR | 共享调度器全部 40 余项短场景，含读写竞争、配额、释放和错误保持 | PASS | [latest_shared_video.json](../../../build/video/latest_shared_video.json)、[回归目录](../../../build/video/regression/20261030T055700_642058Z/) |
| Video 控制地址译码 | 118 项正常检查；错误目标、过早接受 W、错误读响应归属 3 个变异均按预期失败 | PASS；Icarus/VVP，4 次运行 | [result.json](../../../build/video/control_decode/20261030T061132_214550Z/result.json) |

CPU→Video 日志给出 CPU_VIDEO_FIRMWARE_PASS，CPU→NPU 日志给出 CPU_NPU_OPERATOR_PASS；控制译码回归记录 118 项检查和 3 个故障变异；所有本轮源输入在运行前后哈希一致。

技术文档使用的三张波形图均为直接打开已保存 WLF 后从 ModelSim Wave 窗口截取的原始界面截图，截图中不含鼠标光标，也未进行 Python 或 Matplotlib 重绘；图片及 SHA-256 已登记在 JSON 的 `waveform_figures` 字段中。

当前结果的边界是：主工程还没有正式的 CPU/NPU/Video 共享 fabric 或 Cache 一致性模块，因此跨主端写后读可见性、CPU fence/cache maintenance 对 NPU/Video 的保证以及物理 DDR CDC 尚未验收。下一步应先冻结三主端地址属性、仲裁优先级、完成顺序和可见性协议，再把本批测试台中的本地存储模型替换为生产 fabric，复用同一组正例和负例回归。
