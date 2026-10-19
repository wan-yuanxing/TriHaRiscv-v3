# F3c 独立静态全屏三模式

状态：2026-10-20，数字联测、独立审查及综合通过；最新布线setup为-0.225ns/18端点，三模式镜像尚未下载。下一步拆分core错误控制流水，见[流水计划](../../superpowers/plans/2026-10-20-mode-capture-pipeline.md)。机器摘要见[mode_board.json](evidence/mode_board.json)。

## 行为与边界

独立目标 `video_mode_board` 从冻结 F2 顶层派生，F2 顶层、管脚、时钟、DDR IP 及四份原有约束保持原字节；公共CRC reader、writer及其测试的等价优化作为有记录例外，详见下文。默认原分辨率 800×600 RAW；KEY1/C23 低有效，经两级同步和 20ms 去抖，依次切 RAW → BOX → AVATAR → RAW。长按只产生一次请求。KEY0/C22 保留协调复位、DDR 重校准和单帧重采，MODE 与素材回到初始状态；沿用 F2 的 HDMI 初始化保持方式。

BOX 使用人工常量：主人脸红框 `[200,600)×[150,450)`，次框绿色 `[100,400)×[100,300)`；主人脸五点黄色。AVATAR 在主框区域显示本地算术生成的 256×256 RGBA 测试纹理，按非预乘 Alpha 混合。框、点及纹理均是诊断素材，不是 NPU 检测或真实人脸头像。缓存完整写入 65536 字后封存；无 DDR 素材 DMA、CPU 上传或运行中替换。

每次协调复位只锁存一份合法 raw 帧/槽/代际；身份变化为 sticky fault。raw_display 的 RGB/控制先注册两级，新坐标与 SOF 同样注册两级后接 F3b；叠加 13 级加 pad 1 级，因此扫描边沿 n 到 pad 边沿 n+15，共 16 级寄存。模式仅在 raw 对齐 SOF 生效，首像素使用新记录；实际首像素到 pad 后才允许 core 得到提交反馈。

纯 MODE 不向 raw_display 重发记录，不增加 raw commits，不改变 frame_id、采集 CRC 或 arm toggle，不重启 HDMI/DDR。这个独立单帧诊断没有通用多帧所有者、槽释放 ABI 或正式显示 MMIO；F4 仍须实现它们。

## 数字证据

- `--suite mode_output`：三场景，独立数学逐像素及 14 级 helper 对齐；长按、快速合并请求、复位后不同源图。
- `--suite mode_board`：6 个原有健康/故障/复位场景、三模式完整光栅及四种 UART 包；349 光栅、34900 个有效像素。明确断言 MODE 期间三路身份/CRC、arm、raw 提交和 HDMI/DDR 状态不变。板级测试使用标记的数字 DDR/PLL 模型及强制接收前端，不能替代实际采集。
- 实际800×600组合定向检查通过1920021个有效像素；BOX/AVATAR各完整480000像素，返回RAW后序号/反馈仍一致。复用独立数学oracle和14级监视器，仅缩短命令流程。此前完整通用场景在全尺寸下超过600秒计算时限，已另存未完成记录，不计为通过。
- Python：102 项，101 通过、1 项 Windows 符号链接权限跳过。新增 type10 解码、状态/完整轮次/目标切换及 KEY1 管脚校验。独立审查发现旧 MODE 成功可被后来的 raw-only 包沿用；RED 复现后，现要求最新两个完整有序 `6/9/8/10` 轮次，仅接受下一轮最多三包的有序前缀。
- 独立组合及板级审查各有单独来源/产物哈希。板级审查另外核对 42894 个像素，并用 raw 坐标/SOF 错一拍的替身确认测试失败。最终结论以对应 JSON 及父核验为准。

首轮 PDS compile 揭示顶层 net 在使用后声明；仅调整新顶层的声明位置。第一次完整综合拒绝了一条无实际路径的 free_clk→新逻辑 reset 例外。新逻辑复位来自本地 core_release/display_pixel_release，删除多余例外后保持本地 recovery/removal 计时；没有放宽 8ns core 或 6ns bundle 约束。

## 构建、约束及物理检查

当前综合为17365 LUT、18737 FF、73.5 DRM36K、16 APM，包含完整HDMI/DDR、三分支和素材缓存。实际网表检查140个管脚无缺失/碰撞、64素材双钟RAM、77同步链及13组存活束，未发现未覆盖跨域或内部组合环。ASYNC_REG属性被本版PDS忽略，以实际网表/物理路径为依据。

所有构建保留core8ns、pixel25ns和原跨域约束。完成的布线结果如下；表中多种子列出最佳结果，全部hold通过。

| 源码阶段 | 布局 | 最差setup/ns | 失败端点 |
|---|---|---:|---:|
| 原数字检查点 | normal4..9，最佳8 | -0.060 | 2 |
| 原数字检查点 | performance8 | -0.060 | 2 |
| CRC BYTES停止条件拆分 | normal8 | -0.247 | 14 |
| 同上 | normal4..7，最佳6 | -0.140 | 10 |
| CRC接收私有暂存优化 | normal6 | -0.205 | 4 |
| writer先饱和再低位取整 | normal6 | -0.225 | 18 |

CRC两个改动均已逐拍比较公共输出并独立检查四态；停止首因、公开事务排空和结果保持不变。writer只改burst算术，函数之外原字节保持，2499200组数值/四态及19动态场景公开输出一致；另有228872组独立检查及3个错误替身通过。最新write_dma/raw_board/mode_board回归通过。历史全量37套件的198项输入中190项相同，8项差异由当前定向证据覆盖，不冒称完整all重跑。

最新slow/fast hold为+0.124/+0.089ns，但setup仍失败，最差路径是preview DMA的结果字节数校验到缩放器使能。6次完成的构建均未打包/下载。三轮局部等价优化之后转向[控制流水计划](../../superpowers/plans/2026-10-20-mode-capture-pipeline.md)，允许内部故障响应增加一个core周期，同时保护第一错误、AXI排空和成功发布边界。等价检查点与失败来源见[时序记录](../../superpowers/plans/2026-10-20-mode-board-timing.md)。

构建器新增seed/mode参数，默认保持4..9/normal；非法值先于构建退出。现场验收器修复了未观察复位沿用、旧Program日志沿用及物理产物绑定三类问题，18项独立检查通过。当前仍未产生三模式实体验收记录。外部HDMI AC、连续视频、共享fabric/三槽所有权及真实NPU不在本次签核内。

```powershell
python scripts/video/run.py --suite mode_output
python scripts/video/run.py --suite mode_board
python scripts/video/build_pds.py --target video_mode_board --stage bitstream --seed-start 6 --seed-count 1 --pnr-mode normal
python scripts/video/package_board.py --target video_mode_board
python scripts/video/program_board.py --target video_mode_board --start-server
python scripts/video/read_board.py --port COM12 --seconds 60
```

下载入口保留成功构建/当前来源哈希、同会话芯片 ID、匹配 `.sbit/.smsk` 与 Program/Verify 检查，仅做易失配置。现场 RAW/BOX/AVATAR、60 秒稳定性及 KEY0 后重采仍待真实操作与观察，不以组件测试关闭。

## 串口

仍是 37 字节 `TRV1` 包，type6/9/8/10 四包轮转，同一 896bit 冻结 core 快照。type10 的六个 uint32 为 mode_state、request_seq、committed_seq、request_count、commit_count、coalesced_count，末 uint32 是 heartbeat。

mode_state 位0..1 请求模式、2..3 实际模式、4 active_valid、5 pending、6 unavailable、7 core素材就绪、8 pixel素材就绪反馈、9控制协议错、10缓存错、11叠加错、12按键按下、13无有效上下文、14上下文错、15跨域协议错；高16位为0。健康静止 RAW/BOX/AVATAR 通常为 0x190/0x195/0x19a，按下期间另有 bit12。

`physical_mode_fullscreen_readback_verified` 同时要求四种包的最新完整健康 epoch、素材/模式/seq 一致、三路读回相符及扫描推进无欠载。这是 UART 数据资格；实际屏幕和按键仍单独记录。
