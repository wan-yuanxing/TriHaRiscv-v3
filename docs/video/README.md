# Video 开发入口

本路线使用 Windows 原生 Python、Icarus、ModelSim、PDS。总范围见 [路线计划](../superpowers/plans/2026-10-16-video-route.md)，实际完成情况以 [STATUS](STATUS.md) 为准。

## 目前可以运行

从仓库根目录的 PowerShell 执行：

```powershell
python scripts/video/doctor.py
python scripts/video/gen_config.py --check
python scripts/video/prepare_reference.py --reference hdmi
python scripts/video/prepare_reference.py --reference ddr
python scripts/video/run.py --suite all
python scripts/video/build_pds.py --target video_timing --stage synth
```

配置更改后先执行 `python scripts/video/gen_config.py`，再执行 `--check`。当前只接受 v0.6 固定模式，修改规格后才扩展模式校验。`--suite all` 仅运行已经实现的套件；当前为配置/参考提取测试和固定时序彩条，不能解读为整条 Video 路线全部通过。

工具覆盖、版本与运行证据见 [Windows 工具链](../verification/video/toolchain.md)。`prepare_reference` 默认只提取清单中的已验证文件，并不生成完整可综合 DDR IP；完整依赖 staging 属于后续板级任务。

## 当前文件树

```text
config/video_cfg.json                    固定模式与图像布局权威配置
rtl/video/
  include/video_cfg.vh                    生成的 RTL 常量
  video_timing.sv                         800×600 扫描计数与同步
  video_test_pattern.sv                   RGB888 八色条
  video_pattern_core.sv                   便携综合边界，外部提供 40 MHz
sw/include/video_cfg.h                    同源生成的 C 常量
tb/video/
  tb_timing.sv                           完整光栅/像素/复位自检
  test_config.py                         固定模式、生成一致性、漂移拒绝
  test_references.py                     提取字节、哈希失败、目录越界检查
scripts/video/
  common.py                             原生命令/工具/哈希/结果辅助
  doctor.py                             本机工具发现与版本探测
  gen_config.py                         生成 RTL/C 定义
  prepare_reference.py                  只提取哈希匹配的参考文件
  run.py                                已实现的回归入口
  build_pds.py                          组件综合入口
fpga/pg2l100h/
  project/video_timing.json              显式源文件与测试清单
  constraints/video_timing.fdc           组件 25 ns 时钟约束
  ip/video_reference_manifest.json       HDMI/DDR 来源和选中文件哈希
docs/interfaces/                        Video 与 DDR 契约状态
docs/verification/video/                 工具、参考差异、验证证据
docs/video/STATUS.md                     任务、依赖和完成状态
build/video/                            被忽略的运行结果、参考副本和 PDS 工程
```

后续 HDMI/DDR/CDC wrapper 放在 `fpga/pg2l100h/rtl/`；跨板可复用像素和 DMA 模块放在 `rtl/video/`。板级约束不与组件约束混用；最终 SoC 顶层由 CPU 牵头集成。已经存在的空目录不表示功能已实现。

## 结果定位

- `build/video/doctor.json`：工具版本发现。
- `build/video/latest_all.json`：最新完整已实现套件的状态及日志目录。
- `build/video/latest_pds.json`：最新组件综合状态、资源与输入哈希。
- `build/video/vendor/{hdmi,ddr}/provenance.json`：参考包与成员哈希。
- 回归和 PDS 使用独立时间戳目录；时间戳目录用 UTC，报告日期按北京时间记录。

当前入口不会下载硬件或写 Flash。后续板测目标必须明确 FPGA/板卡版本、40 MHz PLL、HDMI 初始化、实际管脚、电气与时序约束后才生成可下载镜像。
