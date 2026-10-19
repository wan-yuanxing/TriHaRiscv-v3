# F3b 框、五点与单头像像素组件实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 在原图坐标完成最多16框、可选五点与一张256×256 RGBA头像的不可反压像素流水，独立验证数值与故障回退。

**Architecture:** `avatar_sample_map`用8级二进制小数除法精确计算`floor((p-start)*256/(end-start))`，几何输入先寄存，共9级；不裁源映射矩形。`display_overlay`并行判断BOX/五点，并把原像素和身份延迟到固定素材响应槽，再做三段Alpha算术。输入在边沿n采样，地址在n+8输出、外部同步缓存在n+9采样请求并注册响应，叠加在n+10消费响应，最终RGB/坐标/身份/同步/标志在n+12输出。

**Tech Stack:** Windows原生Python、SystemVerilog、Icarus、PDS组件综合；继续当前Video分支，不改F2/raw_display/公共配置，不下载组件。

## 接口与工程决定

- 固定原图800×600、纹理256×256。坐标接口为11bit无符号光栅坐标；框/点/头像端点为16bit有符号数，覆盖整个有效域并可跨边界。框半开裁到原图后绘制2像素内边框；无面积框连同其点忽略。五点独立使能，默认半径2的实心方点，覆盖框颜色。主人脸边框红色，普通框绿色，点黄色；主人脸优先于重叠普通边框。颜色/线宽/点半径为组件参数。
- `result_valid && result_frame_id==pixel_frame_id && result_has_face`才启用叠加；无脸、失效/错帧、RAW或保留模式透明通过原像素。BOX与AVATAR互斥，AVATAR不画框。
- 素材只提供18bit字节偏移（4字节对齐），总范围262144B；`RGBA[31:24/23:16/15:8/7:0]`分别R/G/B/A。外部缓存每个请求对应一个固定响应槽，无ready、不能滑动或重排。有效且无错误才使用素材，否则该像素退回原图，像素fault和sticky fault在输出末级报告；后续健康响应可以继续叠加。reset清空流水/故障，不清素材存储。
- 非预乘Alpha：`(a*fg+(255-a)*bg+127)//255`，两端精确。RTL使用定宽乘加与精确常数除255；Python oracle直接整数除法。像素、frame_id、坐标、DE/HS/VS/SOF与三个选中标志共同延迟13级（边沿差12）。空白像素保留原RGB且不叠加。
- 本批调用方须提供同钟、已提交记录；逐像素改参数用于压力测试不代表支持半帧提交。CDC、实际素材DDR预取/缓存、raw引用退休、MODE管脚和原子帧边界属于F3c/F4，不由这些组件代替。

## Task 1：基线、独立oracle与RED

**Files:** `build/video/overlay_baseline.json`、`tb/video/overlay_reference.py`、`tb/video/tb_display_overlay.sv`。

- [x] 保存HEAD、既有dirty/冻结来源哈希及空暂存证据。
- [x] Python生成配置与像素事件，按数学矩形集合、直接最近邻除法和混合公式产生期望；SV只驱动、固定延迟供数并转储，不复制期望像素算法。
- [x] 覆盖16框/主人脸重叠、五点开关、负坐标/跨四边/零面积、无脸/错帧、逐拍模式变化、空白、全屏、最大有符号跨度、1像素目标、缩小/放大、全部Alpha、缺数/错误/恢复和流水中复位。

```python
sx = ((x - x0) * 256) // (x1 - x0)
out = (alpha * foreground + (255 - alpha) * background + 127) // 255
```

- [x] 用忽略目录中的延迟原图/无请求替身运行相同测试，要求oracle以框像素或缺头像采样请求错误失败，保存非零RED证据。

## Task 2：RTL与入口

**Files:** `rtl/video/{avatar_sample_map,display_overlay}.sv`、`fpga/pg2l100h/project/video_overlay.json`、`fpga/pg2l100h/constraints/video_overlay.fdc`、`scripts/video/{run,build_pds}.py`。

- [x] 实现几何寄存及8级精确小数映射；最多65535跨度，移位减法17bit，中间值不溢出。
- [x] 实现BOX/点判断、13级数据/身份对齐及固定响应槽Alpha，错误仅退回对应像素并锁存故障。
- [x] 新增显式manifest及25ns像素时钟综合约束；只有synth，不允许route/bitstream。
- [x] `python scripts/video/run.py --suite overlay`：每个仿真与Python核验均唯一PASS；保存输入、工具、向量、输出与日志哈希。包含800×600完整有效区逐像素比较。
- [x] `python scripts/video/build_pds.py --target video_overlay --stage synth`，记录真实资源和估计setup，不称布线/板测。

## Task 3：审查、验证、交付

**Files:** `docs/interfaces/video.md`、`docs/video/{README,STATUS}.md`、`docs/verification/video/overlay.md`、`docs/verification/video/evidence/overlay.json`。

- [x] 按requesting-code-review技能派独立审查，检查定宽/符号/裁剪、Alpha、固定响应与reset对齐；reviewer只在忽略目录写证据。父进程复核发现与证据。
- [x] 冻结新代码后运行overlay、mode_control、raw_display和Python测试；未修改其他正式套件输入时，以F3a完整37套件基线哈希对照保留旧路径覆盖，明确本批未重跑33分钟的完整all。任何旧RTL变化必须扩大测试。
- [x] 保存当前输入/产物/综合报告/独立审查哈希，逐项核对保留文件，发布接口和真实验证层级。素材供数端仅为测试同步ROM，不声称DDR预取已实现。
- [x] 精确暂存本批Video文件并本地提交，验证Git clean-filter等价及工作文件字节未变化；禁止`git add .`。不push、merge、写Flash。

## 执行记录

当前计划依据已批准全屏设计内F3人工叠加范围；用户持续授权实施，本会话直接逐项执行，无需再次设计审批。板卡继续保持F2静态全屏桌面镜像。
