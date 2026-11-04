# 人脸检测上板版本的文档证据

来源为仓库 `https://github.com/wan-yuanxing/TriHaRiscv-v3` 的提交 `ab8ebb3db671ff4eab02d7b87a344567b7b60a6e`，发布包为 `face-box-20261103`。
此目录归档技术文档使用的既有证据，未重新运行仿真、综合、布局布线或板测。

## 文件

- `manifest.json`：来源、归档路径、文件大小及SHA256。
- `release/README.md`：上游发布说明。
- `release/manifest.json`：上游完整发布清单，包含归档、位流和源码校验值。
- `release/verification.json`：干净目录恢复、编译与物理数据库回放记录。
- `release/2026-11-03-face-box-bringup.json`：集成验证和最终板测汇总。
- `evidence/video/face_box_board_acceptance_20261103.json`：Program/Verify、六段模型装载和人工视觉验收。
- `evidence/video/face_box_performance_20261103.json`：从两个结果完成标记计算的仿真结果间隔。
- `evidence/video/face_box_50_bridge_priority_qualified_20261103/result.json`：最终内部后布线时序、CDC及构建输入绑定。
- `evidence/video/face_box_50_bridge_priority_review_20261103/result.json`：时序、物理路径及Gray数据路径检查。
- `evidence/video/face_box_50_bridge_priority_clocks_20261103/result.json`：Gray数据及源、目的时钟核对。
- `evidence/video/pds/20261103T070558_933114Z/synthesize/triha_face_board_top.snr`：整机及模块层级综合资源原始报告。
- `evidence/soc/face_system-20261103T070341_048946Z/`：自然人脸联合仿真的结果与日志。
- `evidence/soc/face_system-20261103T070341_033768Z/`：零RGB空场景联合仿真的结果与日志。

## 统计范围

整机计算、Video/DDR用户及输出像素时钟分别为50、125和40 MHz。CPU采用单发射精简控制配置，NPU采用两空间行Dense阵列和单量化通路，硬件执行模型图，CPU完成检测后处理，像素端显示主人脸框。

资源为综合阶段结果：42,531 LUT、43,408 FF、77.5个DRM36K等效块和58个APM。LUT含分布式RAM。CPU应用层级包含本地存储和路由，与独立CoreMark的CPU核范围不同；主要模块层级是顶层总数的子集，不能与顶层再次求和。

最终内部后布线建立/保持最差裕量为+0.183/+0.108 ns。离线资格记录的`physical_board=false`和`timing_closed=false`保持原值；内部时序由`internal_timing_met`、`routed_internal_timing_closed`及`cdc_timing_met`记录，实际下载及功能验收由后续板测记录给出。外部HDMI I/O AC不在该内部时序结论范围内。

自然人脸和零RGB仿真各完成两个结果，间隔分别为18,087,225和18,061,818个计算周期，即361.74450和361.23636 ms。每场景只有一个间隔样本；这些数值不是持续帧率、纯NPU延迟或采集到显示延迟。完整画面核对以不同帧号计数，日志中的同帧重复扫描不增加完成帧数。

板测包含用户人工确认的人脸出框、位置更新、无脸清框及后续画面持续更新；没有额外推定实板FPS。全部原始记录保留其日期、绝对路径与阶段状态，不把历史状态字段倒改为最终结论。

归档前已核对四个上游ZIP的SHA256，以上文件逐一与发布清单比对。完整位流、模型及物理数据库由上游发布包保存，此目录仅保留文档所需记录。
