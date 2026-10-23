# 连续 RAW / BOX / AVATAR 板级交付记录

2026-10-23，基于 `62d1ade`。目标 `video_live_mode_board`；连续三模式实体验收通过，真实 NPU 和正式 CPU 集成仍另行验收。

## 行为与边界

保留 800×600、40 MHz（约60.32 Hz）输入输出、125 MHz 核心及 RAW/preview/320×320 BGR NCHW 三分支。原有 A/B 两槽在旧图 release 后才复用，逐像素叠加不增加整帧 DDR 写回。

KEY1 按 RAW→BOX→AVATAR→RAW 循环；有效图像 SOF 才应用模式，pad 首像素退休后才反馈完成。三个模式的底图均应连续更新。KEY0 协调复位，回到 RAW 后继续自动采集。BOX 是人工生成的两框和五个黄色点，AVATAR 是不可在线替换的256×256 RGBA算术测试纹理，均不代表真实 NPU 推理。

扫描器导出与 RGB 同拍的像素域 frame_id/generation/slot/x/y/sof。模式配置使用独立的固定诊断身份，与实际图像身份分离；新图不触发新 MODE 命令。叠加流水只保留像素和元数据值，不持有旧 DDR 槽引用，不改变 release 生命周期。

UART 按12/9/11/10轮换：捕获、扫描、生命周期、模式。健康判定要求四类包属于同一心跳时间段，近期模式请求已提交，且捕获/提交/释放/扫描持续前进。采集中的计数与CRC可随下一帧开始归零；不宣称每帧全量DDR读回。正式 CPU 帧池、系统可见性栅栏和真实 NPU 结果仍另行集成。

## 验证

```powershell
python scripts/video/run.py --suite live_modes
python scripts/video/run.py --suite live_board
python scripts/video/run.py --suite axi_bridge
python scripts/video/run.py --suite shared_video
python scripts/video/run.py --suite mode_output
python scripts/video/run.py --suite nchw_dma
python scripts/video/build_pds.py --target video_live_mode_board --stage bitstream --seed-start 5 --seed-count 1 --pnr-mode performance
python scripts/video/package_board.py --target video_live_mode_board
python scripts/video/program_board.py --target video_live_mode_board --start-server
python scripts/video/read_board.py --port COM12 --seconds 60
```

- RED：旧静态模式输出在变化图像身份测试中失败，`build/video/live_modes/20261023T040209_069391Z`。
- GREEN：组件和板级数字仿真使用真实入口、三分支采集、共享DDR及最终pad，独立RGB/几何/最近邻/Alpha oracle验证变化帧、三模式和两次复位。额外检查全光栅同步/元数据流水、按键长按与合并、无有效图像SOF等待，以及命令在SOF前/同拍/后到达。
- 每条模式命令的反馈不得先于实际pad首像素；将退休标记从第13级改为第1级的变异必须以 `LIVE_MODE_ACK_BEFORE_VISIBLE_RETIREMENT` 失败。
- 包解析回归覆盖四包轮换、MODE心跳回退、历史包失效、模式未提交、缺失模式包和静止帧计数拒绝。
- 桥接器故障测试覆盖上/下半起始地址、四个收集位置（含最后一W拍）、初始化丢失、意外/X RVALID：W所有权排空、首错保持、错误B，无native命令或缓存复用。

本批最终回归定位（相对于仓库根目录，输入和日志/仿真产物哈希均已核对）：

| 套件 | 运行目录 `build/video/regression/` 下 | 结果 |
|---|---|---|
| live_modes | `20261023T042858_508821Z` | 组件、板壳、过早反馈变异、包检查通过 |
| live_board | `20261023T042858_537303Z` | 原连续RAW回归通过 |
| axi_bridge | `20261023T042858_487167Z` | 215个桥接器用例通过 |
| shared_video | `20261023T043041_552873Z` | 共享DDR调度与故障回归通过 |
| mode_output | `20261023T043041_543266Z` | 原静态模式输出回归通过 |
| nchw_dma | `20261023T042208_002523Z` | 完整张量、参数、故障与独立golden比对通过 |

## 物理实现与定向修正

首轮 `build/video/pds/20261023T040831_208377Z` 实际布线失败，slow core setup −0.895ns；NCHW的非定宽padding mask表达式产生32位减法链。改为合法计数范围内等价的4/5位移位计数，保持beat、WSTRB及张量ABI，完整尺寸及参数/故障回归通过。

第二轮 `build/video/pds/20261023T041746_656404Z` 仍失败。完整报告slow core setup −1.263ns，最差为DDR align_error经native_ready和故障判断到私有expected缓存CE，近2000扇出；另外实际像素上下文导出使generation位存活，未被原有record数据束约束覆盖，出现core→pixel setup失败。

针对性修正：COLLECT故障期间允许已拥有的AXI W拍继续写私有scratch；错误退休和WPRE发布前检查、即时native写掩码保护、首错和QUARANTINE保持，因此错误内容不会发布。移除故障组合信号对宽scratch CE的扇出。generation与base/frame/slot共用toggle握手并保持至commit消费，补入相同6ns datapath约束，未增加跨时钟的宽泛false path。

定向只读审查未发现槽引用、像素身份、模式反馈或上述故障排空的正确性阻塞。

最终 `build/video/pds/20261023T042858_495450Z` 的完整实际报告为 All Constraints Met：slow setup/hold +0.063/+0.129ns，fast +2.911/+0.097ns，两角 recovery/removal 均通过。综合16770LUT /18150FF /73.5DRM，140个板级IO；其中64DRM为256×256 RGBA测试纹理缓存，未增加整帧视频缓冲。位流 `50ea2b124300` 与匹配Verify掩码已打包到 `build/video/releases/video_live_mode_board_50ea2b124300`。

专项CDC采用只读项目副本和实际PNR网表逐端点报告，均为6ns数据束约束：release34端点（slow/fast最小余量+4.431/+5.044ns）、generation1端点（+5.123/+5.484ns）、MODE3个存活端点（+4.638/+5.177ns）、素材2端点（+5.063/+5.452ns）。常量字段由综合裁剪；报告前后原PNR数据库、网表、项目和完整时序报告哈希一致。证据目录 `build/video/live_modes_delivery/cdc/20261023T042858_495450Z`。

## 实体检查

PG2L100H/00602899易失Program/Verify通过，`build/video/board_program/20261023T043841_272916Z`，未写Flash。持续接收记录 `build/video/live_mode_board_trace/20261023T043913_669627Z`。

用户确认RAW为完整全屏动态源图，按键前78.98秒串口基线通过。三次单独KEY1后分别确认BOX框和五点、AVATAR测试纹理、返回RAW均正常，底图始终自动更新且无裁切；串口模式序号0→1→2→3均已提交，生命周期持续前进，欠载/溢出/错误为0。

用户只短按一次KEY0，确认完整全屏RAW恢复并继续自动更新。记录共514包，明确1次复位，模式回到RAW、请求序号归零。复位后连续健康87.000秒，生命周期采样窗口84秒，实际新图30.1548fps；欠载、溢出和错误均为0。串口已正常关闭，开发板保持本轮新镜像运行。

机器证据：[live_modes.json](evidence/live_modes.json)。本阶段连续三模式诊断交付关闭；真实检测框/头像、CPU统一帧池及共享总线可见性仍须单独验收。
