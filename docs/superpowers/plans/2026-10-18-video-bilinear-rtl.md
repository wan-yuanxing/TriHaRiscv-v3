# YuNet 固定5:2双线性 RTL 实施计划

> **For agentic workers:** Use superpowers:executing-plans inline; request independent code review at the component verification checkpoint.

**Goal:** 实现可背压、可取消且数值匹配已冻结OpenCV4.11参考的800×600→320×240 RGB888组件。

**Architecture:** `detect_bilinear`沿用Video ready/valid单帧接口及8ns组件约束。每5列/行取0/1、3/4两对，2号仍做几何/四态检查；同步RAM保存每个输出列的三通道10bit水平和。底部行的水平和寄存后，分阶段执行垂直分步取整与输出。输出仍为有效RGB，不包含BGR、40行补边、NCHW、DMA或正式完成事件。

**Tech Stack:** SystemVerilog、Icarus、Python标准库、Windows PDS，现有Video分支原位实施。

## 接口与错误规则

默认FRAME_WIDTH=800、FRAME_HEIGHT=600；允许5..2045内5的倍数，每轴输出2/5。接口为clk/reset_n/clear、s_valid/s_ready/s_rgb/s_row_last、m_valid/m_ready/m_rgb/m_row_last/fault。一次clear/reset接收一帧，末输入后不再接纳。fault sticky，停止接纳并取消尚未公开的运算结果；已经公开的VALID及数据保持至ready，clear/reset可协调取消。

所有被接纳像素（含未参与插值的行/列）的未知RGB或错误/未知row_last均报fault。末帧额外s_valid报fault。未知值只在被接纳时解释；blocked payload不报错。RAM及读寄存器不复位，每次新帧的top行覆盖后才读取；clear/reset必须同步取消旧生产者。

每通道水平和h=left+3*right（偶输出列）或3*left+right（奇输出列）。底部源行相位1时上下垂直权重1/3，相位4时3/1。q=((weight_top*h_top)//4+(weight_bottom*h_bottom)//4+2)//4。禁止提前水平舍入或改为一次最终舍入。

## 1. 测试先行

- [ ] 创建`tb/video/tb_detect_bilinear.sv`，从目标坐标直接计算四源点oracle，覆盖5×5、15×10、25×15、800×600、2045×5和5×2045；完整帧六模式与已有参考相同，并允许输出hex转储。
- [ ] 覆盖输入气泡、96拍级长背压、输出保持、每个5×5相位上的RGB X/Z和row_last错误、blocked未知值、末拍fault保持、部分行/运算中/受阻输出clear及异步reset。
- [ ] 缺模块编译获得有效RED（Unknown module），保存测试哈希与非零退出码。

## 2. 生产组件

- [ ] 创建`rtl/video/detect_bilinear.sv`，参数合法性检查；列相位0/3锁存left并在bottom行发同步RAM读，1/4计算水平和，top行写RAM、bottom行发计算流水。
- [ ] 输入计数按握手推进；流水占用或受阻输出时ready拉低。取消清控制/输出槽，不清RAM；fault不撤销已有输出。
- [ ] 运行定向测试；完整800×600转储由`tb/video/check_bilinear_dump.py`重建NCHW并匹配六份OpenCV4.11 SHA256，不依赖OpenCV运行库。

## 3. 构建与验收

- [ ] `scripts/video/run.py`增加`--suite detect_bilinear`并纳入all，独立套件不提取厂商包；明确加入RTL/TB/转储检查器/参考/项目/FDC的输入哈希。
- [ ] 创建`fpga/pg2l100h/project/video_detect_bilinear.json`与`constraints/video_detect_bilinear.fdc`，显式源、测试、8ns时钟；`scripts/video/build_pds.py`加入组件目标，route/bitstream继续提前拒绝。
- [ ] 用错误单次舍入、交换权重相位、提前截断水平和、错误行RAM地址四项隔离突变确认测试拒绝。实现与异常路径作独立审查，组件综合记录实际资源/估计时序，不代替后布线或板测。
- [ ] 运行定向与完整Video回归，核对当前输入哈希；更新接口、文件树、STATUS和验证/小型证据，只提交本批Video文件。125MHz、6ns束约束及5秒超时保持原有范围。

测试入口：`python scripts/video/run.py --suite detect_bilinear`；综合：`python scripts/video/build_pds.py --target video_detect_bilinear --stage synth`。完整验收入口为`python scripts/video/run.py --suite all`。下一批NCHW行缓存/DMA另列，不用本组件的输出消费冒充INPUT_READY。
