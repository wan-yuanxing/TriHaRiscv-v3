# 头像应用文档证据

固定来源：`wan-yuanxing/TriHaRiscv-v3` 的 `soc/face-box-integration`，提交 `edfa1992f604e5887e04f7cad2d81aeff122dd4b`，发布包 `face-photo-20261104`。

本目录归档技术文档引用的小型发布记录、完整系统仿真日志和只读核查结果。没有在本轮重跑RTL仿真、综合、布线或板卡操作。

| 位置 | 内容 |
| --- | --- |
| `release/acceptance.json` | 最终板级画面验收、配套位流、UART及配置重放记录 |
| `release/manifest.json` | 发布包文件及归档成员SHA256、340项源码身份 |
| `release/evidence/` | 扫描、下载、串口、离线素材及重放原始记录 |
| `evidence/build/soc/face_system-20261104T011551_456009Z/` | 自然人脸完整系统仿真，预期1脸 |
| `evidence/build/soc/face_system-20261104T011551_453685Z/` | 零RGB完整系统仿真，预期0脸 |
| `evidence/build/video/ringbit6d/result.json` | 最终位流资格记录，含资源及时序数据 |
| `evidence/build/video/ringrev6d/result.json` | 最终布线复核摘要 |
| `evidence/build/video/ringclk6d/result.json` | Gray数据及源、目的时钟保守界 |
| `evidence/build/video/face_photo_ring_performance_20261104.json` | 两组相邻结果间隔及50 MHz换算 |
| `source-notes/` | 固定提交的应用说明和头像身份、格式参数 |
| `analysis/` | 本轮设计、资源、时序核查，含原文件行号和哈希 |
| `manifest.json`、`source-identity.json`、`analysis-index.json` | 本地原始归档索引、源码比对及派生分析索引 |

340项源码与固定提交核对，其中338项直接匹配发布SHA256；两个审核脚本的Git文件为LF，转换为Windows CRLF后的SHA256精确匹配发布清单。`source-identity.json`分别记录原始Git字节与发布字节的哈希，不改写源码以掩盖差异。

ZIP01、ZIP13整体SHA256及所用成员SHA256已核验。综合SNR通过范围读取提取并核验成员SHA256，未宣称核验其ZIP07整包哈希。大型原始RTR保存在忽略目录 `build/technical-report-avatar-edfa199/evidence/`，本目录的分析保存其哈希、关键路径原文和行号；未重新构建或读取原生布线数据库进行签核。

最终画面结论以 `release/acceptance.json` 的后续人工验收为准；较早的 `release/evidence/board.json` 单独记录下载及串口阶段，保留其原始 `visual_confirmed=false` 字段。整机仿真约2.77次/s是存储代理环境中的结果完成率，每场景只有一个相邻间隔；板级验收确认三模式、头像跟随、透明背景和无脸清除与恢复，没有板级FPS测量。外部DDR/HDMI板级AC检查与内部STA分开记录。
