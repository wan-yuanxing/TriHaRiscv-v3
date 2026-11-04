# 新 CPU 单发射配置：完整头像三模式位流

本包使用新版双发射内核，应用配置 `DUAL_ISSUE=0`。保留真实 CPU/NPU 检测、RAW/BOX/AVATAR 三模式、KEY1 切换、七段模型/头像加载与完整校验。

- 器件：PG2L100H-6IFBG676 / MES2L676-100HP。
- 时钟：CPU/NPU 50 MHz；DDR UI/视频/UART/loader/采集 125 MHz；像素 40 MHz。
- 保留额外 0.2 ns setup 余量；未放宽时序或新增宽泛 false path。
- 有脸/无脸两帧真实整机及三模式逐像素仿真通过。
- 零未布线；慢快角 setup/hold/recovery/removal/pulse width 全部通过。
- 最差 setup +0.168 ns；最差 hold +0.117 ns。
- 23 组 / 116 位 Gray CDC，928 项时钟观测通过数值时钟+数据偏斜上界检查。
- 独立恢复后重新生成配置，位流与掩码仅允许已解析的文件头时间戳不同；配置字节一致。

`triha_face_board_top.sbit` 是配置位流，`triha_face_board_top.smsk` 是对应校验掩码，保持同目录配套使用。
`manifest.json` 与四个 `reproduction-*.zip` 包含源码身份、模型、冻结数据库和原始验收证据。
`acceptance.json` 与 `evidence/` 保存本次离线验收摘要。

在主工程目录可运行：

```powershell
D:/miniconda3/python.exe scripts/video/restore_face_release.py --release releases/face-dual-single-avatar-20261104
```

上述命令只做离线校验，不连接开发板。需要恢复构建输入时使用 `--install`，需要重新生成并比较位流时再加 `--replay-bitstream`。不同的现存文件会被拒绝覆盖。

本轮未扫描、下载或烧录开发板；当前 CPU 版本的实际板测、外部 HDMI AC 时序和板上帧率仍待验证。上板后仍需通过 `scripts/soc/upload_face_model.py --port COMx` 加载七段模型/头像，COMx 应替换为实际串口。没有实现脱离电脑后的 Flash 模型自动加载。
