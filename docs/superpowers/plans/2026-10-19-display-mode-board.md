# F3c 模式跨域、素材缓存与独立板级实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 将F3a/F3b接到独立静态全屏诊断目标，KEY1切RAW/BOX/AVATAR，KEY0保留协调重采；组件、物理时序和现场验收分别记录。

**Architecture:** 先实现单在途命令/实际提交反馈CDC和一次装载后不可变的256×256 RGBA素材缓存，再接独立`video_mode_board`。保持F2源码/约束原字节，新板顶层派生自冻结F2结构并保留原层级，MODE不重启采集或DDR。当前诊断每次协调复位只有一帧、一个不可变素材；正式多帧/可替换素材的引用与显示ABI由F4接入，不能冒充已有通用槽管理。

**Tech Stack:** Windows Python/PowerShell、SystemVerilog/Icarus、PDS；保持当前Video分支，显式manifest，运行产物只放build/video。

## 组件契约

- `display_mode_cdc`：core握手后冻结mode/seq/frame/slot/generation/context；request toggle经两级同步，pixel锁存完整bundle并保持valid至ready。pixel接纳与实际提交分开，只有`pixel_commit`才翻转ack。ack回core后保持commit反馈，直至ready；旧反馈未消费不能接新命令。无raw释放端口。协调reset清双域全部事件；禁止只重置一域。非法提前/重复pixel_commit锁存协议故障，不伪造正常完成。
- `avatar_texture_cache`：单bank，默认65536个RGBA8888字、共262144B。core接纳asset_id/generation后从字0依次装载，每字必须已定义，last只能在65535。全部写完才发布asset_ready；装载失败sticky禁止显示，不能用部分RAM。每次协调复位只装载一次，ready后永不改写；替换素材须F4引用/排空协议。RAM内容不清。pixel readiness两级同步后再捕获稳定身份；每个像素请求在该边沿读同步RAM并注册valid/error，返回固定响应槽。地址不对齐/超范围/身份不符/未就绪返回error，RGBA可未知，由F3b按原图回退。
- 两组件FDC保留core8ns/pixel25ns；scalar只豁免第一级，稳定bundle限定6ns；本地级间仍计时。新缓存组件综合不等于实际素材DDR预取，板级初版用确定的本地测试素材流填充缓存。
- 官方硬件手册2.1.3.4.1及按键例程交叉核对KEY1=C23、低有效、LVCMOS33；KEY0=C22。只接KEY1为MODE，不猜用其他输入。保存手册/例程哈希与按键电路页截图。
- 独立板级所有框/点/头像目标为人工常量，同帧身份来自已经完成读回的raw提交。静态素材装好后才能提交AVATAR。模式应用于raw对齐后的SOF，首像素使用本拍待提交模式，随后保持；实际反馈等13级叠加与pad流水的首像素到输出。纯MODE不发raw record、不增加raw commits、不释放槽、不重采。

## Task 1：冻结来源与硬件核对

- [x] 保存HEAD、全部既有dirty/冻结Video输入与空暂存证据到`build/video/mode_board_baseline.json`。
- [x] 用PDF提取/渲染核对KEY1及低有效电路，和官方`key_led_test.fdc`的C23/3.3V属性逐项比对；正式文件只保存小型来源记录。

## Task 2：CDC测试先行

**Files:** `tb/video/tb_display_mode_cdc.sv`、`rtl/video/display_mode_cdc.sv`、组件manifest/FDC。

- [x] 用独立scoreboard测试双异步相位、命令/像素接纳背压、实际提交延迟、反馈背压、完整payload稳定、提前/重复commit、复位三个在途阶段及序号回绕；测试7/128/513bit上下文。
- [x] 延迟反馈故意错误替身须因接纳即反馈失败；保存RED非零和当前测试哈希。
- [x] 实现单事务toggle/mailbox，pixel接纳后保持到实际commit；core不依赖序号判断新旧，仅用握手事务寿命。

```systemverilog
// 接纳后仍未实际提交时，反馈必须保持0。
if (pixel_accepted && !pixel_committed) assert (!commit_valid);
if (held_valid && !held_ready) assert (payload === held_payload);
```

## Task 3：素材缓存测试先行

**Files:** `tb/video/tb_avatar_texture_cache.sv`、`rtl/video/avatar_texture_cache.sv`、组件manifest/FDC。

- [x] 检查装载停顿、最后一字门槛、未知/错last失败、封存后不可再装载、首次/末地址与全部65536字读回、错身份/非对齐/越界/未就绪响应、协调复位后用新图重装且不借旧RAM。
- [x] 提前ready/错误读延迟替身须非零；再实现双钟RAM及独立发布身份控制，不以reset清RAM。

```systemverilog
assert (!asset_ready || words_written == TEXELS);
// 一次请求对应一个固定响应槽，失败也不能悄悄丢槽。
assert (sample_valid == previously_sampled_request);
```

## Task 4：组件入口与审查检查点

**Files:** `scripts/video/run.py/build_pds.py`、`fpga/pg2l100h/project/video_{mode_cdc,avatar_cache}.json`、相应FDC、接口/台账/验证记录。

- [x] 新增`--suite mode_resources`，显式编译两个测试，记录来源/工具/关键产物哈希；纳入all。
- [x] 两个独立目标只支持synth；实际资源和setup/hold估计分开报告，不宣称布线闭合。
- [x] 按requesting-code-review技能独立审查CDC稳定期、响应槽、RAM封存与复位，父进程复核发现；冻结后定向回归mode_resources/overlay/mode_control及Python，保留未修改旧输入的完整基线对照。
- [x] 文档记录本检查点的实际交付与剩余板级工作，精确提交组件及证据；不得把下面未完成项标完成。

## Task 5：独立板级接入

**Files:** `fpga/pg2l100h/rtl/video_mode_board_top.sv`、独立manifest/FDC、`tb/video/tb_video_mode_board.sv`、构建/打包/串口脚本与测试。

- [ ] 派生冻结F2顶层保持已有层级/复位结构；对齐raw RGB对应的x/y/SOF，再接F3b和缓存。MODE记录经CDC原子应用，first-pixel retire marker触发实际反馈。
- [ ] 人工框/点/测试头像可观察，默认RAW；KEY1两级同步+20ms去抖。数字联测验证三模式全光栅、首末像素、快速请求合并、模式变化不触发采集/raw提交/HDMI或DDR复位，KEY0后重新装载和重采。
- [ ] 新UART模式记录包含request/active/seq/commit/asset/error状态；不能以旧type9健康条件替代叠加健康；包解析/epoch测试覆盖新类型。
- [ ] 保留原8ns core/6ns CDC束约束，审计所有新增/存活同步端点，实际综合/布线通过后才生成和打包位流。

## Task 6：现场验收

- [ ] 合格包在同一下载会话识别ID后易失Program/Verify；保持旧合格包可恢复，不写Flash。
- [ ] 逐项记录RAW完整四角、KEY1到BOX框/点、KEY1到AVATAR及回RAW；mode request/commit推进而raw提交/采集CRC/帧ID不变，60秒无欠载/叠加故障。
- [ ] KEY0后素材重装/重新校准重采、完整桌面恢复；需用户实际操作和观察才能关闭，不能用数字测试代替。
- [ ] 更新状态/来源/位流与现场证据并精确本地提交，无push或merge。
