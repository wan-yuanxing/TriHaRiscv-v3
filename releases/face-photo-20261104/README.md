# 盘古开发板人脸检测与照片叠加

此版本适用于 MES2L676-100HP 开发板上的 PG2L100H-6IFBG676。接入 800×600、标称 60 Hz 的 HDMI 输入，CPU 按 B03 YuNet 的主脸检测框定位和缩放照片。有脸时按原图 alpha 混合，无脸时显示原画面。开机为 RAW，按 KEY1 依次切换 BOX、AVATAR 和 RAW。换脸使用二维矩形对齐。[指定照片与对齐参数](../../assets/avatars/triha/source.json)

## 从干净克隆恢复

在仓库根目录运行以下 PowerShell 命令。Windows 主机需要 Python 3.11 或更新版本，串口上传需要 pyserial。13 个 ZIP 分包共含 2,328 个归档成员，包括固件、模型、原生布局布线数据库和验证记录。恢复工具按 SHA256 核对 340 个源码文件和每个归档成员。[文件清单](manifest.json)

```powershell
git checkout face-photo-20261104
python scripts/video/restore_face_release.py --release releases/face-photo-20261104 --install
python scripts/soc/upload_face_model.py
```

最后一条命令离线校验七段素材。连接开发板电源、JTAG、USB 串口和 HDMI 后，运行下面两条命令。将 COM12 替换为本机对应的 CP210x 端口。JTAG 配置易失，KEY0 复位后需要重新上传七段模型及素材。

```powershell
python scripts/video/program_board.py --target triha_face_board --start-server
python scripts/soc/upload_face_model.py --port COM12
```

下载时使用本目录的配套文件。模型及照片共 2,032,640 字节，7,940 包，最后应收到游标 `(7, 0)`。

| 文件 | SHA256 |
| --- | --- |
| `triha_face_board_top.sbit` | `c7875faa32568d9b8e1d16d4b450c78e4cec6586dff94e411d4c875d1d61c0fd` |
| `triha_face_board_top.smsk` | `057fe58b112658bbf9994782b306c5e245a8f1daeed07cc6a36c84d4d35e86d2` |
| `assets/avatars/triha/avatar.rgba` | `4e4f435800f7b0e0dc5e7ac1ccef57db36ac286df7203556c7820b69f5479537` |

## 重放位流与核对画面

在另一个干净克隆中使用 PDS 2022.2-SP6.4 运行原生重放。脚本从归档的布线数据库和匹配的 ROM、SRAM、ELF 重新生成位流与掩码，逐字节比较配置，只允许已解析的文件头日期和时间变化。

```powershell
python scripts/video/restore_face_release.py --release releases/face-photo-20261104 --install --replay-bitstream --pds D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe
```

计算、视频/DDR 和像素时钟分别为 50、125 和 40 MHz。布线后两角最差建立余量为 +0.100 ns，最差保持余量为 +0.131 ns，23 组 Gray 跨域通道的 116 位均有双角时钟观测。时序验收覆盖 FPGA 内部。正脸和无脸整机仿真各检测两次并逐像素核对 RAW、BOX 和 AVATAR。相邻结果间隔为 361.58 ms 和 361.21 ms，约每秒 2.77 次仿真检测结果。实板显示更新率可通过带帧号的 HDMI 输入和连续输出采集测量。[输入页、测量和源码构建方法](../../docs/video/FACE_AVATAR_BRINGUP.md)
