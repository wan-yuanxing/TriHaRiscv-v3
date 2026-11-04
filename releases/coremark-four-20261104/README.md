# 四组 CoreMark 原始实测位流

2026-11-04：用户已确认，只准备并烧录四组原始实测位流，切换时使用电脑。本包不含人脸应用、模型、模型加载工具或 Golden 引导镜像，也未采用研究中的压缩位流。不新增按键切换逻辑，不重新综合或布局布线。

| 原记录编号 | 配置 | CPU 时钟 | 历史 CoreMark/MHz |
|---|---|---:|---:|
| 02_coremark_single_sram | 单发射，片内 SRAM，无 Cache | 100 MHz | 3.055366 |
| 03_coremark_single_cache | 单发射，I/D Cache + DDR | 100 MHz | 2.497435 |
| 04_coremark_dual_sram | 双发射，片内 SRAM，无 Cache | 100 MHz | 4.092790 |
| 05_coremark_dual_cache | 双发射，I/D Cache + DDR | 100 MHz | 3.152167 |

编号保持与原验收包一致。四份 SBIT 及其 SMSK 全部与已实板验证的原件相同，完整 SHA256、来源和原始板测证据保存在 `manifest.json`、`evidence/`。所有固件已内嵌，无需电脑加载模型；Cache/DDR 版本需要等待 DDR 校准并由嵌入式启动程序复制/校验基准程序。上述成绩是历史实测结果，本次没有重新上板测速。

## 离线校验

```powershell
python demo.py verify
python demo.py list
```

使用 Python 3.11+。本机可用 `D:/miniconda3/python.exe`。校验不访问开发板。

## 烧录文件

- `images/<编号>/*.sbit`：原 FPGA 配置；相邻 `.smsk` 必须匹配，供 JTAG Program + Verify。
- `flash/EF4018_W25Q128Q_x1/<编号>.sfc`：PDS 原生生成、对应 JEDEC EF4018 的单镜像 Flash 文件。
- `flash/EF7018_W25Q128M_x1/<编号>.sfc`：对应 JEDEC EF7018 的单镜像 Flash 文件。

**这些单镜像 SFC 均从地址 0 开始，互为替代。不能依次写到地址 0 来保存四个版本。** 接板后先确认 FPGA ID 00602899、实际 Flash 型号/容量/JEDEC ID，并备份现有 Flash。实际器件若为其他型号（例如板卡资料提及的 XTX 0B4018），须按实际器件准备对应配置，不能使用 Winbond 名称替代。

接板前未执行任何 JTAG/串口操作或 Flash 写入。烧录后必须分别记录 Program、Verify、断电冷启动和完整 CoreMark 输出；目前没有本包的 Flash 冷启动验收记录。

## 已确认的演示方式：电脑切换

先将用户选定的一份原始镜像固化到 Flash 地址 0，作为断电后的默认版本。演示时在电脑上选择四个 `images/<编号>/` 中的原始 SBIT，通过 FPGA 的 JTAG Program + Verify 切换。临时切换不覆盖 Flash，重新上电会恢复已固化的默认版本。

如需更换断电默认版本，可在电脑选择对应原始 SFC，按相同备份、Program、Verify 和冷启动检查流程重新固化。完整四版文件都已保留；本方案不声称四镜像联合驻留并可任意选址启动。

此前的容量研究仅作记录：四份原文件共 15,164,448 字节；PDS SPI Upgrade 格式合成试验含头部和对齐为 15,196,160 字节（14.49 MiB），可容纳于单颗 16 MiB Flash。该试验并未验证切换或冷启动，不在交付烧录文件中，也不继续扩展为按键切换功能。

接板后依次保存：实际 FPGA/Flash 身份、旧 Flash 备份及 SHA256、选择的默认镜像 ID、Program/Verify 日志、断电冷启动结果、四版各自完整 UART 输出。KEY0 只重跑当前版本，不负责跨版本切换。当前尚未收到已连接开发板的确认，未访问硬件。

## 观察结果

串口：115200、8N1、无流控，端口在接板后确认，不沿用历史 COM12。所有版本 5000 次迭代，完整结果应出现 `CPU_COREMARK_BOARD_PASS`，errors/short 为 0；CRC 为 e9f5/e714/1fd7/8e3a。KEY0 重跑前开始串口接收，保存完整记录。

现有四版 LED 原始定义见各自板测资料，不声称已有统一四版本指示。单发射 SRAM 调试版的 CPU 实际 LUT 数与其旧 UART 分母不同，不用该分母进行资源效率排名。

`ram_tcl/` 中脚本只有在显式执行时才操作硬件；要求现有 PDS JTAG server，先运行离线哈希校验并检查 FPGA ID，再进行易失 Program + Verify，不写 Flash。它们不自动连接/启动 server，本次没有运行。

`vendor/` 提供原始 pyserial 3.5 wheel，可供已有终端使用；串口操作只在连接开发板后执行。历史证据中的绝对路径和 Tcl 仅用于溯源。
