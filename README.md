# TriHaRiscv

TriHaRiscv 的 CPU、NPU、Video 总工程，目标平台为 PG2L100H-6IFBG676。当前分支 `soc/face-box-integration` 集成 HDMI 800×600 采集、B03 YuNet 整图推理、CPU 解码/NMS及同帧显示。

2026-11-03 用户确定第一优先级为真实人脸检测功能跑通，先完成构建、仿真和布线后时序，再连接板卡验收。帧率只记录，不作为本轮门槛。首版显式使用 `--face-profile box`，自动显示主脸检测框；保留头像配置供后续推进，五点关键点不阻塞首版。CPU/NPU 为50MHz，Video/DDR为125MHz，像素为40MHz。

## 当前状态与文档入口

已验收版本的位流、模型、固件、冻结数据库与恢复说明随仓库保存于 [2026-11-03 BOX 发布包](releases/face-box-20261103/README.md)。新克隆先运行 `python scripts/video/restore_face_release.py --install`，即可恢复上板与复现所需的生成文件。

当前50MHz版本已通过有脸／无脸整机回归、双角内部后布线时序及全部Gray跨域检查，并生成BOX交付包 `build/video/releases/triha_face_board_3939c52f4d94`（`.sbit`/`.smsk`及证据）。setup最差+0.183ns，hold最差+0.108ns。实板Program/Verify和六段模型封存通过；用户确认正脸出框、位置变化后框更新、无脸清框及后续画面继续更新，第一优先级功能验收完成。FPS未测，外部I/O AC尚未正式签核。构建、模型恢复、六段上传命令见 [应用入口](docs/video/FINAL_APPLICATION.md)，逐项证据和后续事项见 [Video 工作台账](docs/video/STATUS.md)。实板关联记录为 `build/video/face_box_board_acceptance_20261103.json`。

项目远端仓库为 [wan-yuanxing/TriHaRiscv-v3](https://github.com/wan-yuanxing/TriHaRiscv-v3)，本地 remote 为 `origin`。当前用户指定工作目录为 `D:/FPGA/TriHaRiscv-v3`；旧文档中的 `TriHaRiscv-main` 是历史目录名。

- [v0.6 设计规格](docs/TriHaRiscv_SoC_Design_Spec_v0.6.md)：功能、接口、地址、时序与验收依据，目录和分工对应第 12.3、15 节。
- [全屏显示设计](docs/superpowers/specs/2026-10-19-fullscreen-display-design.md)：原分辨率显示、功能键、帧边界提交/释放、带宽和分阶段验收。
- [v0.6 审核记录](docs/reviews/2026-10-14-v06-review.md)：两项文档问题已修复；迁移基线、CPU 来源适配和公共接口冻结仍待后续落实。
- [Video 开发入口](docs/video/README.md)：Windows 命令、实际文件树和构建产物；[Video 路线计划](docs/superpowers/plans/2026-10-16-video-route.md)列出后续里程碑。
- [技术报告说明](docs/technical-report/README.md)：LaTeX 正文、插图、参考文献与编译说明。该目录另有局部维护约定。

README 负责工程导航与职责划分，技术细节以当前规格为准。发现冲突时先修订权威定义，再同步相关文档、RTL 和软件；不能用报告中的规划描述作为实测完成证据。

## 文件树安排

以下保留历史目标文件树。标注 `[规划]` 表示最初规划状态，当前已有的应用/驱动及验证入口见上方应用文档；目录存在不代表已通过实板验收。

```text
TriHaRiscv-main/
├── README.md                       总工程导航、目录归属与协作方式
├── .gitignore                      构建、文档编译、缓存与本地环境排除规则
├── .gitattributes                  文本换行与二进制文件规则
├── config/                         已有视频配置；地址、寄存器契约继续建立
├── rtl/
│   ├── cpu/                        六级 CPU、Cache、基础分支预测
│   ├── npu/                        普通/逐点/深度卷积、辅助算子、NPU DMA
│   ├── video/                      采集、缩放、全屏/诊断显示、头像、视频 DMA 与帧握手
│   └── soc/                        SoC 顶层、互连、通用外设、复位与系统连接
├── fpga/
│   └── pg2l100h/
│       ├── rtl/                    板级顶层、DDR/HDMI/时钟封装
│       ├── constraints/            引脚、时钟与时序约束
│       ├── ip/                     厂商 IP 配置、版本与生成说明
│       └── project/                PDS 工程入口与可复现工程配置
├── sw/
│   ├── apps/face_avatar/           [规划] 完整演示入口
│   ├── drivers/                    [规划] NPU、Video、UART、Timer 等驱动
│   ├── include/                    已有生成的 video_cfg.h
│   └── runtime/                    [规划] 启动、帧调度、定点后处理与错误恢复
├── model/
│   └── yunet/                      [规划] 图审计、量化、整数参考、模型包导出
├── assets/
│   └── avatars/                    [规划] 素材清单、来源许可和转换工具
├── tb/
│   ├── cpu/                        CPU、Cache、异常/中断测试
│   ├── npu/                        单算子、完整图与数值一致性测试
│   ├── video/                      像素、缩放、叠加、帧协议与背压测试
│   └── soc/                        两两集成、系统并发与错误恢复测试
├── scripts/                        公共构建、回归、装载和报告汇总入口
├── docs/
│   ├── TriHaRiscv_SoC_Design_Spec_v0.6.md
│   ├── reviews/                    审核发现、修复状态与遗留事项
│   ├── interfaces/                 公共接口契约与冻结状态
│   ├── verification/               测试方法、配置和验证证据索引
│   ├── video/                      Video 开发入口与工作台账
│   └── technical-report/           技术报告，结构见其 README
└── build/                          自动生成的工程、波形、日志和临时结果（忽略）
```

手工维护的 RTL、驱动、测试和脚本放入对应源码目录，不放在 `build/`。模型包以 `model/yunet/` 的清单记录来源、版本和哈希，素材包以 `assets/avatars/` 的清单记录；`config/` 引用这些版本，不另抄一份模型或素材定义。大体积权重、像素与生成 IP 的保存策略在建立版本基线时确定，须保留可复现来源和生成方法。

## 三线分工

分工按职责定义，具体人员或任务可分别认领。每条线维护自己的源码、独立测试、最小验证顶层和证据；共用模块保持一份实现。

| 路线 | 主责范围 | 主要目录 | 对外交付 |
|---|---|---|---|
| CPU | 六级 CPU、Cache/BP、启动与驱动、定点解码/NMS、主人脸与头像参数、整图及帧槽调度；牵头互连与整机集成 | `rtl/cpu/`、`rtl/soc/`、`sw/`、`tb/cpu/`、`tb/soc/` | CPU 回归与 CoreMark、地址/MMIO 契约、后处理参考核对、可运行固件和集成结果 |
| NPU | 固定 YuNet 图、量化与整数语义、模型包；普通/逐点/深度卷积、辅助算子、计算缓冲与 DMA | `rtl/npu/`、`model/yunet/`、`tb/npu/` | 模型哈希与清单、输入/输出布局、算子表、整数参考、逐层一致性和周期/资源报告 |
| Video | DDR/HDMI/像素域封装、板级约束；全帧采集、预处理、全屏/诊断显示、模式/Alpha、帧提交/释放；头像素材制作 | `rtl/video/`、`fpga/pg2l100h/`、`assets/avatars/`、`tb/video/` | 固定模式链路、DDR 自检与封装契约、预处理转储、人工结果全屏及按键切换、像素/边界/释放测试 |

CPU 维护软件中的统一帧状态和 `graph_active/frame_owner`；Video 提供采集、显示提交与释放握手；NPU 提供单算子的完成/错误与帧、算子标识。硬件单算子 IDLE 不等于整图可以换帧。首版按规格保留计算所有权至 RESULT_READY，不由各线另建互相矛盾的帧状态。

## 公共文件与接口协作

共同模块由三线分担维护，不增设第四条开发路线。共享目录内按文件确定主责，主责负责发布一致版本，使用方参与接口检查。

| 公共内容 | 主责 | 配合方与约束 |
|---|---|---|
| SoC 地址、存储属性、互连与全局复位契约 | CPU | NPU、Video 核对 DMA 窗口、访问顺序和错误行为 |
| NPU 寄存器、算子参数与完成语义 | NPU | CPU 核对驱动、START/DONE、W1C、BUSY 写入和 OP_TAG |
| Video 寄存器、视频配置、请求/提交/释放协议 | Video | CPU 核对软件所有权、ACK 和超时恢复；NPU 核对输入就绪条件 |
| DDR native 封装、HDMI/时钟 IP 与物理约束 | Video | CPU 核对 fabric 侧契约；NPU、Video DMA 共用测试向量。明确写成功与后继读可见性 |
| 板级最终顶层与 PDS 工程 | CPU 牵头集成，Video 维护板级封装 | 顶层接线、时钟/复位或约束变更双方核对，禁止各自复制 DDR 实现 |
| 模型清单、预处理与输出数值定义 | NPU | Video 核对缩放/补边/通道排列，CPU 核对定点后处理与输出顺序 |
| 素材清单与像素格式 | Video | CPU 核对 avatar_id、锚点和目标矩形 |
| 公共脚本、filelist、配置生成与回归汇总 | CPU 牵头 | 各线维护各自模块清单、测试入口及工具版本 |

地址和寄存器的详细位定义尚待冻结。后续选择一种共同配置格式，生成 RTL 与 C 定义；生成文件不手工分别修改。公共接口变更应同时记录版本、受影响模块和验证向量，接口两端在同一版本完成更新后再集成。

同一目录并行工作时，先约定各任务修改的文件，避免同时编辑公共顶层、地址表或规格。跨线修改由主责汇总；不得覆盖其他任务的未完成修改。建立 Git 后，可按 CPU、NPU、Video 和集成职责组织分支；需要独立分支时使用独立工作区，不在一个共享目录中轮流切分支。

## 实施与集成顺序

Video 已从工程基线与独立组件开始实施；其余路线和共同节点按各自准入条件推进。参考复用逐项登记并回归，不整目录迁入旧应用。

1. **补齐迁移基线与最小契约。** 在当前文档与目录基线上登记后续源码来源、版本/哈希、许可证和适配差异，冻结首批地址、寄存器、模型及素材清单。旧工程仅作参考和复用来源，不整目录搬入生成产物。
2. **三线独立验证。** CPU 跑六级最小系统、CoreMark 和固定输出后处理；NPU 完成图审计、整数参考与代表层；Video 完成固定模式、DDR 自检及全屏人工框/头像和功能键切换。使用协议正确的测试模型解开依赖。
3. **优先两两集成。** CPU＋Video 验证请求、提交和释放；Video＋NPU 核对预处理张量；CPU＋NPU 验证单算子及完整静态图。再接入完整视频应用。
4. **真实功能演示。** 完整板上推理、全屏原图/检测框/头像同帧切换、错误恢复和至少 10 分钟连续运行；记录实际 fps、延迟与掉帧，不将测试模型作为最终推理结果。
5. **性能优化。** 按瓶颈优化 CPU、NPU、DDR 与视频重叠，保持数值和帧所有权正确；报告 ≥24 fps 目标达成情况、延迟分位数、更新抖动和至少 30 分钟稳定性。

每次交付附上改动范围、接口版本、运行命令、输入/配置、结果与遗留问题。可演示构建须绑定同一源码版本、硬件配置、固件、模型和素材；尚无实测结果的项目标为待验证。有效输出 fps 按首次实际显示的不同采集帧计数，HDMI 扫描、重复旧帧和两个窗口不能重复计数。
