# Video链路高价值仿真验证方案

## 目标

用少量系统级场景证明视频链路的四个关键属性：帧数据完整、帧所有权不冲突、显示提交与像素输出一致、背压和错误能够恢复。已有模块级回归和板级RAW/BOX/AVATAR结果只作为支撑，不在本批重复运行。

## 选择的验证入口

| 证据链 | 现有入口 | 文档用途 |
|---|---|---|
| 采集/三路写入/失败重武装 | `capture_rearm` | 证明完整帧、CRC、stride、EOF、rearm和故障锁止 |
| 三槽所有权/模式提交 | `display_slots` | 证明FREE、ACTIVE、RETIRING、release ACK、generation和过期反馈处理 |
| 共享DDR背压 | `shared_video` | 证明RAW读、采集写、urgent配额、AXI响应背压和错误排空 |
| 端到端数字链路 | `video_pipeline` | 证明采集、显示、槽复用、失败帧和显示像素oracle可以串起来 |

CPU控制路径直接复用已完成的 `cpu_record` 证据；不重复运行CPU固件仿真。真实NPU未接入时，端到端场景只声明接口和空检测结果前提，不宣称完整推理。

## 输出组织

正文放四类结果：

1. 一张采集到三路写入的帧身份/CRC/字节统计表；
2. 一张三槽状态和mode/commit/release时序图；
3. 一张共享DDR读写竞争及无欠载波形；
4. 一张端到端正常、坏EOF和数据损坏的结果表。

全部套件日志、输入哈希、变异结果和工具版本进入 `docs/verification/video/evidence/` 及 `build/video/`，不把完整回归日志直接嵌入正文。

## 边界

本批不运行PDS、不下载板卡、不改变生产RTL；不把可背压数字源当作不可背压HDMI物理吞吐，不把空检测结果当作真实NPU推理，不把组件综合估算当作整机时序结论。
