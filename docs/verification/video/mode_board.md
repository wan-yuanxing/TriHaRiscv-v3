# F3c 独立静态全屏三模式

状态：2026-10-20，数字联测、独立审查及板级综合已完成；当前正在布局布线，尚未下载或进行实体 KEY1 验收。机器摘要见 [mode_board.json](evidence/mode_board.json)（在本批检查点生成）。

## 行为与边界

独立目标 `video_mode_board` 从冻结 F2 顶层派生，F2 源码、管脚、时钟、DDR IP 及四份原有约束保持原字节。默认原分辨率 800×600 RAW；KEY1/C23 低有效，经两级同步和 20ms 去抖，依次切 RAW → BOX → AVATAR → RAW。长按只产生一次请求。KEY0/C22 保留协调复位、DDR 重校准和单帧重采，MODE 与素材回到初始状态；沿用 F2 的 HDMI 初始化保持方式。

BOX 使用人工常量：主人脸红框 `[200,600)×[150,450)`，次框绿色 `[100,400)×[100,300)`；主人脸五点黄色。AVATAR 在主框区域显示本地算术生成的 256×256 RGBA 测试纹理，按非预乘 Alpha 混合。框、点及纹理均是诊断素材，不是 NPU 检测或真实人脸头像。缓存完整写入 65536 字后封存；无 DDR 素材 DMA、CPU 上传或运行中替换。

每次协调复位只锁存一份合法 raw 帧/槽/代际；身份变化为 sticky fault。raw_display 的 RGB/控制先注册两级，新坐标与 SOF 同样注册两级后接 F3b；叠加 13 级加 pad 1 级，因此扫描边沿 n 到 pad 边沿 n+15，共 16 级寄存。模式仅在 raw 对齐 SOF 生效，首像素使用新记录；实际首像素到 pad 后才允许 core 得到提交反馈。

纯 MODE 不向 raw_display 重发记录，不增加 raw commits，不改变 frame_id、采集 CRC 或 arm toggle，不重启 HDMI/DDR。这个独立单帧诊断没有通用多帧所有者、槽释放 ABI 或正式显示 MMIO；F4 仍须实现它们。

## 数字证据

- `--suite mode_output`：三场景，独立数学逐像素及 14 级 helper 对齐；长按、快速合并请求、复位后不同源图。
- `--suite mode_board`：6 个原有健康/故障/复位场景、三模式完整光栅及四种 UART 包；349 光栅、34900 个有效像素。明确断言 MODE 期间三路身份/CRC、arm、raw 提交和 HDMI/DDR 状态不变。板级测试使用标记的数字 DDR/PLL 模型及强制接收前端，不能替代实际采集。
- Python：99 项，98 通过、1 项 Windows 符号链接权限跳过。新增 type10 解码、状态/完整轮次/目标切换及 KEY1 管脚校验。独立审查发现旧 MODE 成功可被后来的 raw-only 包沿用；RED 复现后，现要求最新两个完整有序 `6/9/8/10` 轮次，仅接受下一轮最多三包的有序前缀。
- 独立组合及板级审查各有单独来源/产物哈希。板级审查另外核对 42894 个像素，并用 raw 坐标/SOF 错一拍的替身确认测试失败。最终结论以对应 JSON 及父核验为准。

首轮 PDS compile 揭示顶层 net 在使用后声明；仅调整新顶层的声明位置。第一次完整综合拒绝了一条无实际路径的 free_clk→新逻辑 reset 例外。新逻辑复位来自本地 core_release/display_pixel_release，删除多余例外后保持本地 recovery/removal 计时；没有放宽 8ns core 或 6ns bundle 约束。

## 构建、约束及物理检查

实际合格综合：17522 LUT、18738 FF、73.5 DRM36K、16 APM，含完整 HDMI/DDR、三分支、扫描和新素材缓存。网表结构审计检查 140 个管脚无缺失/碰撞、64 个素材双钟 RAM、原 68 条加新 9 条同步链、全部存活跨域束及原约束来源；无未覆盖跨域数据或内部组合环。ASYNC_REG 属性被本版 PDS 忽略，因此以实际网表及后续物理路径审计为依据。

布局布线继续使用六个确定性种子及原 core8ns/pixel25ns/束6ns；尚未形成最终时序或位流结论。外部 HDMI AC、连续视频、共享 fabric/三槽所有权及真实 NPU 不在本次签核内。

```powershell
python scripts/video/run.py --suite mode_output
python scripts/video/run.py --suite mode_board
python scripts/video/build_pds.py --target video_mode_board --stage bitstream
python scripts/video/package_board.py --target video_mode_board
python scripts/video/program_board.py --target video_mode_board --start-server
python scripts/video/read_board.py --port COM12 --seconds 60
```

下载入口保留成功构建/当前来源哈希、同会话芯片 ID、匹配 `.sbit/.smsk` 与 Program/Verify 检查，仅做易失配置。现场 RAW/BOX/AVATAR、60 秒稳定性及 KEY0 后重采仍待真实操作与观察，不以组件测试关闭。

## 串口

仍是 37 字节 `TRV1` 包，type6/9/8/10 四包轮转，同一 896bit 冻结 core 快照。type10 的六个 uint32 为 mode_state、request_seq、committed_seq、request_count、commit_count、coalesced_count，末 uint32 是 heartbeat。

mode_state 位0..1 请求模式、2..3 实际模式、4 active_valid、5 pending、6 unavailable、7 core素材就绪、8 pixel素材就绪反馈、9控制协议错、10缓存错、11叠加错、12按键按下、13无有效上下文、14上下文错、15跨域协议错；高16位为0。健康静止 RAW/BOX/AVATAR 通常为 0x190/0x195/0x19a，按下期间另有 bit12。

`physical_mode_fullscreen_readback_verified` 同时要求四种包的最新完整健康 epoch、素材/模式/seq 一致、三路读回相符及扫描推进无欠载。这是 UART 数据资格；实际屏幕和按键仍单独记录。
