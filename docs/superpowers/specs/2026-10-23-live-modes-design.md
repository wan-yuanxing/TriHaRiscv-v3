# 连续 RAW / BOX / AVATAR 上板

用户已确认三模式全屏与功能键方向，并在连续 RAW 验收后要求继续下一阶段。本阶段交付可见的连续三模式诊断，沿用 800×600、40 MHz 输出、125 MHz 核心及三分支采集。

选择像素流水内叠加，复用已验证的 `display_overlay` 和只读测试素材缓存，不新增处理后整帧写回。完整 CPU/MMIO 记录链仍按正式 SoC 集成任务推进，当前板级演示不接该路径。

- `video_live_engine` 导出扫描器已有的像素域 valid/frame_id/generation/slot/x/y/sof，与 RGB 同拍；既有 A/B 释放规则保持。
- 新 `video_live_mode_output` 复用按键去抖、MODE 请求/反馈 CDC、13 级叠加及 pad 寄存。模式配置命令使用固定诊断配置身份（frame=1/generation=1/slot=0），它不是图像身份。逐像素图像身份直接来自扫描器，人工框/点/贴图参数在该像素域以同一真实 frame_id 生成；不从 core frame_id 直接跨域拼图像记录。
- KEY1 按 RAW→BOX→AVATAR→RAW 循环，仅在有有效图像的 SOF 应用，实际 pad 首像素退休才反馈模式已生效。图像持续更新不重新请求模式；模式更新不重启采集、DDR 或 HDMI。
- BOX 使用既有两框及五点，AVATAR 使用已封存 256×256 RGBA 算术测试纹理。素材不可在线替换，不借用真实 NPU 名义。RAW 全屏几何及三分支格式保持。
- 叠加读取已寄存的 RGB 和同拍元数据，不持有 DDR 地址或旧槽引用，因此无需延长 raw_display 的槽保护期；模式反馈与槽 release 各自独立。
- 新增独立 `video_live_mode_board`，保留 RAW 和旧静态模式目标。沿用官方 KEY1/C23 电气约束，保留所有本地时序及精确 CDC 束约束。
- UART11/12/9 保留连续进度，增加 UART10 模式状态；四种包均能使旧的健康历史失效。模式稳定时序号相等，模式切换期间允许 pending，同时采帧和扫描仍前进。

验收：变化源多帧逐像素 oracle、全帧身份一致、三模式循环/合并/长按/复位、DDR 等待、模式命令到达首像素的相位测试。实际板级布局布线通过后 Program/Verify，现场确认三个模式底图均持续更新且无裁切；单次 KEY0 后回到 RAW 并持续更新，至少60秒无欠载/溢出/错误。真实 NPU 与正式 CPU 接管仍另行验收。
