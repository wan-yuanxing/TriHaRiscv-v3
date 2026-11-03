# 真实检测驱动的照片头像

当前素材是用户于 2026-11-03 提供的透明 PNG，原图保存在
`assets/avatars/triha/source.png`。`source.json` 绑定原始 SHA256、转换方式和对齐参数；
`gen_fixed_avatar.py` 仅把原图转换为 256×256、RGBA8888、非预乘 alpha 的固定加载格式。
没有生成或修饰人物。`avatar.png` 是加载副本的预览；`avatar.rgba` 是 FPGA 实际使用的字节。

运行时沿用真实 B03 人脸检测和 CPU 主脸选择，由矩形框定位、缩放透明头像。
锚点为图片坐标 (128,160)，覆盖边长为检测框长边的 1.5 倍，保留头发上方空间。
这是固定二维近似对齐，不提供五点配准或随头部姿态旋转。

## 构建与加载契约

- 目标 `triha_face_board`，profile `avatar`：`ENABLE_AVATAR=1`、
  `ENABLE_MINIMAL_BOX=0`、`DEMO_BOX_ONLY=0`。
- CPU/NPU 50MHz，Video/DDR 125MHz，像素 40MHz。HDMI 输入为 800×600 标称 60Hz。
- 七段上传包含模型 1,770,496 字节和头像 262,144 字节，共 2,032,640 字节、7,940 包。
  最后 ACK 游标必须为 `(7,0)`；不能使用 BOX 版本的 `--model-only`。
- 初始 RAW；KEY1（C23）依次切换 RAW → BOX → AVATAR。按两次可到达头像模式。
  模式经 CPU 按帧提交，需等待下一次结果更新，不保证按键后立即切换。
- KEY0 会复位并使模型/素材封存失效，需重新加载全部七段。易失 JTAG 配置断电后需重新下载。
- 确认素材字节、CRC、代数及 C/RTL 常量完全匹配后才允许叠加；换图需重建对应固件和位流。

片上缓存使用无损行区间压缩：只省去每行两侧 RGBA 四字节均为零的像素，
其余 34,331 个像素全部保留，读取时补零。原始 256×256 图像、上传字节、CRC、
一个时钟的采样延迟均不变。生成的 `avatar_span_table.vh` 与指定素材身份、CRC 绑定，
身份不符或被省略位置出现非零数据时拒绝封存。RAM 写使能/地址/数据经过一级寄存器；
仅在最后一次物理写入完成后封存，像素读取仍为一个时钟。换图时必须重新生成表并重建硬件。

输入 PNG、原始 RGBA、生成的 C/RTL 常量及行区间表均由源码和验收记录绑定。
运行 `python scripts/video/gen_fixed_avatar.py --check` 检查生成结果；Python 依赖见
`config/avatar_python_requirements.txt`。PNG 压缩字节可不同，解码像素必须相同；
硬件加载的 RGBA、元数据和常量要求逐字节一致。

## 当前验收与后续执行

实时状态见 `docs/verification/npu/2026-11-03-face-avatar-bringup.json` 和 `STATUS.md`。
照片替换之前的卡通仿真记录保留为历史，不能代替当前素材的验收。
必须先完成新的正脸/无脸七段加载与三模式整帧像素仿真，然后完成布线、双角 STA、
全部 Gray 路径和物理管脚验收，才生成下载包。

正式下载命令在新包通过验收后使用：

```powershell
python scripts/video/program_board.py --target triha_face_board --start-server
# Program/Verify 通过并完成 DDR 初始化后；COM12 是本验收机 CP210x 的端口。
python scripts/soc/upload_face_model.py --port COM12
```

板测需分别观察 RAW 原画面、BOX 真实人脸框、AVATAR 指定照片；头像应随人脸位置/大小变化，
无脸时消失，透明区域显示背景，画面持续更新。UART ACK 和 Program/Verify 单独不能证明画面正确。
外部 HDMI I/O AC 正式签核和实板帧率测量是独立事项，本功能验收没有帧率门槛。

## 从源码重建

工具沿用 BOX 发布所冻结的 PDS 2022.2-SP6.4、ModelSim 10.5、xPack RISC-V GCC 15.2.0-1。
模型及自然人脸 fixture 沿用已验收来源。Windows 环境先设置工具位置，再运行新素材的两组回归：

```powershell
$env:TRIHA_VSIM='D:/modeltech64_10.5/win64/vsim.exe'
$env:TRIHA_RISCV_GCC='D:/xpack-riscv-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe'
$env:TRIHA_PDS_SHELL='D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe'
python -m pip install --target build/python-deps --only-binary=:all: -r config/face_python_requirements.txt -r config/avatar_python_requirements.txt
$env:PYTHONPATH="$PWD/build/python-deps"
python scripts/video/gen_fixed_avatar.py --check
python scripts/video/test_avatar_ddr.py --asset assets/avatars/triha/avatar.rgba --compact
python scripts/soc/run_face_system.py --board-profile --boot-load --avatar-boot --fixture build/npu/face_fixture_20261103
python scripts/soc/run_face_system.py --board-profile --boot-load --avatar-boot
```

两组运行必须分别为 PASS。将各次实际输出目录记为 `$positive`、`$negative`，不要混用旧卡通
或 BOX 结果。下面每个输出目录必须是新目录；`$synthesis` 是综合命令报告的实际目录：

```powershell
python scripts/video/build_pds.py --target triha_face_board --face-profile avatar --stage synth --firmware-elf "$positive/firmware.elf"
python scripts/video/map_face_synthesis.py --synthesis $synthesis --output $mapped
python scripts/video/reroute_face.py --base $mapped --output $route --seed 4 --mode normal --decongestion 3 --hold-iterations 30 --hold-margin-ps 200
python scripts/video/review_face_route.py --base $mapped --route $route --output $review
python scripts/video/check_face_gray_clocks.py --review "$review/result.json" --output $clocks
python scripts/video/test_face_route_audit.py --base $mapped --review $review --clock-review $clocks --output build/video/new_photo_controls.json
python scripts/video/qualify_face_bitstream.py --base $mapped --placement $route --route $route --review $review --clock-review $clocks --positive $positive --negative $negative --output $qualified --generate
python scripts/video/package_board.py --target triha_face_board
```

每一步失败都必须先处理并生成新的验收记录。保留原失败日志，不把旧记录改成通过。
不同工具或布局布线结果不承诺逐字节相同，必须重新通过时序和功能资格检查。
官方管脚/KEY1 手册来源约束见 `fpga/pg2l100h/ip/video_mode_key_manifest.json`；换机时核对
其实际路径与 SHA256。仅恢复已验收包或回放冻结布线数据库，无需重新执行完整源码构建。

## SD 卡后备方案

用户允许在收敛困难时把头像放在 SD 卡。当前方案把头像从 UART 加载到 DDR，
再装入无损压缩的片上缓存，显示期间不变。SD 可以替换加载来源，但只有缓存结构改变
才能减少显示所占片上 RAM。当前优先验证不改变照片像素的行区间压缩；
没有将未经验证的 SD 控制器接入正式构建。

已验收 BOX 版本始终保留在 Git 标签 `face-box-20261103`。
