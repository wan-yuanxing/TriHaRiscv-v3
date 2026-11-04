# 2026-11-03 人脸检测实板版本

适用：盘古 PG2L100H-6IFBG676 / MES2L676-100HP，HDMI 800×600，标称60Hz。
真实 B03 推理、CPU 解码/NMS、同帧主脸框；没有五点或头像叠加。
CPU/NPU 50MHz，Video/DDR 125MHz，像素40MHz。实板正脸出框、移动更新、无脸清框和画面继续更新已由用户确认。
内部后布线最差 setup +0.183ns、hold +0.108ns，CDC检查通过。外部HDMI I/O AC未正式签核。
仿真结果速率约2.76FPS，实板FPS尚未测量。

本目录随 Git 一起保存，无需 Git LFS 或易失的外部下载链接：

- `triha_face_board_top.sbit`：已下载验收的配置位流。
- `triha_face_board_top.smsk`：必须与位流放在一起的校验掩码。
- `reproduction-*.zip`：模型、固件、仿真输入/输出、厂商参考文件、生成IP、冻结的编译/布局/布线数据库及验收证据；分包控制单文件大小，需全部保留。
- `manifest.json`：每个归档成员、发布文件和相关源码的SHA256。

位流SHA256：`3939c52f4d94cd50476905a206f50ae82347f864604f4b8bb8c98a6fefd51e65`。
掩码SHA256：`d3ca5bbce1a9e90e4ee1ca568df24fd1d10d78505e96ecaff1da8bad5a8997fd`。
Git属性保留已验收源码的原始换行；请勿对冻结输入进行格式化或换行转换。

## 从干净克隆恢复并上板

在Windows PowerShell中执行。先安装Python 3.11及以上；烧录另需PDS 2022.2-SP6.4、JTAG驱动和CP210x串口驱动。
下面的校验、解包和模型审计不会访问开发板。

```powershell
git clone --branch soc/face-box-integration https://github.com/wan-yuanxing/TriHaRiscv-v3.git
cd TriHaRiscv-v3
# 长期复现本版时，检出 face-box-20261103 标签。
git checkout face-box-20261103
python scripts/video/restore_face_release.py --install
python scripts/soc/upload_face_model.py --model-only
```

应看到 `FACE_RELEASE_VERIFY_PASS`、`FACE_RELEASE_INSTALL_PASS`、`PASS_ASSET_AUDIT`。
恢复脚本只将已校验的归档文件写入 `build/`；若该目录存在不同内容，会拒绝覆盖，使用新的克隆即可。
它会为本版设置 `build/video/latest_package_triha_face_board.json`，供现有下载脚本检查源码和位流。

接通板卡、JTAG、USB串口、HDMI输入和输出。输入必须为800×600标称60Hz；不接受任意HDMI分辨率。
把下面PDS路径和COM端口改为本机实际值；验收机使用COM12，但其他机器可能不同。

```powershell
python -m pip install --target build/python-deps pyserial==3.5
$env:PYTHONPATH="$PWD/build/python-deps"
$env:TRIHA_PDS_SHELL='D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe'
python scripts/video/program_board.py --target triha_face_board --start-server
# Program/Verify成功后，等待DDR初始化指示灯亮，再加载模型。
python scripts/soc/upload_face_model.py --model-only --port COM12
```

模型共六段，1,770,496字节、6,916包；应收到 `PASS_UART_LOADER_ACK` 与最终游标 `(6,0)`。
这是易失JTAG配置，未写Flash；断电后需重复下载和模型加载。模型封存后不要再次复位。

## 从冻结布线数据库重新生成相同配置

恢复脚本可调用验收时的PDS，生成新输出并与已验收 `.sbit` / `.smsk` 比较：

```powershell
python scripts/video/restore_face_release.py --install --replay-bitstream --pds D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe
```

必须得到 `NATIVE_REPLAY PASS_CONFIGURATION_IDENTICAL`。PDS会把当前日期和时间写入文件头，
所以新生成文件的整体SHA256会不同。脚本只允许已解析且格式合法的 `c` / `d` 日期时间字段变化，
其余每一个字节（包括器件/设计标识、配置和掩码）都必须与原件一致；原始发布文件不改写。
校验记录同时保存原文件、新文件哈希和时间字段。脚本检查PDS可执行文件哈希，不更新下载目标，不访问板卡。
这是从已验收物理数据库复现配置，和重新综合、布局、布线是两个独立过程。

## 从源码重新构建和验证

归档包含当前可用模型及自然人脸fixture；不需要再次访问上游仓库才能仿真或上板。
模型来源固定于 https://github.com/keep-s/npu_zgtc 的
`558280b30219acdcf9f962acd6e907e0f680ab52`，恢复记录也在归档中。
部分历史测试场景未恢复，不将其列为本版验收证据。

安装 ModelSim 10.5、xPack RISC-V GCC 15.2.0-1 和 PDS 2022.2-SP6.4。
工具与许可证须自行安装；包中不包含工具安装程序或许可证。
将下面路径改为本机位置，所有输出目录使用新名称：

```powershell
$env:TRIHA_VSIM='D:/modeltech64_10.5/win64/vsim.exe'
$env:TRIHA_RISCV_GCC='D:/xpack-riscv-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe'
$env:TRIHA_PDS_SHELL='D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe'
python -m pip install --target build/python-deps --only-binary=:all: -r config/face_python_requirements.txt
$env:PYTHONPATH="$PWD/build/python-deps"
python scripts/video/gen_config.py --check
python scripts/soc/run_face_system.py --board-profile --boot-load --fixture build/npu/face_fixture_20261103
python scripts/soc/run_face_system.py --board-profile --boot-load
```

两个运行均须 `PASS`，分别保存各自输出目录，作为后续命令中的 `$positive` / `$negative`。
GCC生成ELF符号表时可能记录随机临时对象名，导致ELF整体SHA变化；应比较加载后的ROM/SRAM内容。
本版干净目录编译验证中ROM/SRAM逐字节一致，交付包仍保留原始已验收ELF供精确恢复。
构建、路由和资格审查会核验源码、厂商库、固件、管脚及两组仿真，不可跳过。
板卡官方手册由 `fpga/pg2l100h/ip/video_mode_key_manifest.json` 的 `manual.path` 与SHA256指定；
从官方板卡资料获得该文件。该历史字段是验收机的绝对路径，换机可改为手册实际路径后做全套新构建；
这会产生新的输入哈希，不能冒充原发布位流的资格记录。原位流恢复和数据库回放不需要该手册路径存在。

```powershell
python scripts/video/build_pds.py --target triha_face_board --face-profile box --stage route --seed-start 4 --seed-count 1 --pnr-mode normal --plc-decongestion 3 --firmware-elf "$positive/firmware.elf"
# $base 为上一步新建的PDS目录。初始路由可能因时序不通过返回非零；
# 必须确认综合、映射和布局完成，不能把该状态当最终验收通过。
$route='build/video/pds/face_box_rebuild_route'
python scripts/video/reroute_face.py --base $base --placement $base --output $route --seed 5 --mode normal --decongestion 3 --priority-constraints build/video/face_box_50_bridge_priority_20261103.rcf --hold-iterations 30 --hold-margin-ps 200 --pds $env:TRIHA_PDS_SHELL
python scripts/video/review_face_route.py --base $base --route $route --output build/video/face_box_rebuild_review --pds $env:TRIHA_PDS_SHELL
python scripts/video/check_face_gray_clocks.py --review build/video/face_box_rebuild_review/result.json --output build/video/face_box_rebuild_clocks --pds $env:TRIHA_PDS_SHELL
python scripts/video/test_face_route_audit.py --base $base --review build/video/face_box_rebuild_review --clock-review build/video/face_box_rebuild_clocks --output build/video/face_box_rebuild_controls.json
python scripts/video/qualify_face_bitstream.py --base $base --placement $base --route $route --review build/video/face_box_rebuild_review --clock-review build/video/face_box_rebuild_clocks --positive $positive --negative $negative --output build/video/face_box_rebuild_qualified --generate --pds $env:TRIHA_PDS_SHELL
python scripts/video/package_board.py --target triha_face_board
```

重新布局布线的结果必须重新满足时序，不能保证不同工具/主机环境产生相同物理数据库或位流。
包中的历史JSON/Tcl保留原始绝对路径和哈希，供溯源；换目录执行请使用上面的生成入口，不直接运行历史Tcl。
这次发布的源码、模型、固件、物理数据库和已验收位流均已冻结；恢复脚本负责验证其字节身份。

## 验收证据

发布前已在新的源码导出目录验证：209项源码哈希、996项归档成员、998个恢复文件、模型审计、
固件和RTL编译通过；ROM/SRAM内容逐字节一致，PDS原生重生成通过
`PASS_CONFIGURATION_IDENTICAL`。结果见本目录 `verification.json`。
本次未重复运行完整整机仿真，原正/负场景完整回归及其源码哈希随包保存。

恢复后主要记录位于：

- `build/video/face_box_board_acceptance_20261103.json`：实板人工确认与硬件操作关联。
- `build/video/face_box_performance_20261103.json`：仿真帧率计算，非实板测速。
- `build/video/face_box_50_bridge_priority_qualified_20261103/result.json`：最终内部时序、CDC与功能资格。
- `build/video/releases/triha_face_board_3939c52f4d94/manifest.json`：原始离线包清单。

原离线清单中的 `physical_board=false`、`board acceptance pending` 是生成当时的状态，后续实板记录单独保存，没有倒改历史证据。
