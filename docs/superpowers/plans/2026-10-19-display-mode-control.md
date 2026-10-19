# F3a MODE 按键与请求控制组件实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 完成可独立仿真和综合的20ms按键去抖及RAW/BOX/AVATAR请求/提交控制组件，为F3b像素叠加和F3c板级接入提供接口。

**Architecture:** `video_button_debounce`只同步/去抖并产生单次按下事件；`display_mode_control`在core域保存最新合法请求，冻结带frame_id/slot/generation/不透明上下文的提交命令，等待实际提交反馈后才更新active。上下文数据由调用方验证并保持同一generation的内容不变，BOX/AVATAR资格按同帧结果检查。像素域提交/CDC、raw槽所有权、框/头像像素和MODE管脚在F3b/F3c验收，本组件不提供释放接口。

**Tech Stack:** Windows PowerShell/Python、SystemVerilog、Icarus、PDS独立组件综合；沿用当前Video分支，不改F2位流来源、公共配置或CPU工作树。

## 接口约定

- 去抖参数`CLOCK_HZ=125000000`、`STABLE_MS=20`、`ACTIVE_LOW=1`，门槛为`ceil(CLOCK_HZ*STABLE_MS/1000)`，使用64位常量计算。两级同步后的信号连续满足门槛才改变状态；稳定按下产生一拍pulse，长按不重复，重新触发前须稳定释放同样门槛。reset视为释放；reset期间按住的键在重新资格满后最多触发一次。未知样本清除累计但不改变已去抖状态。
- 请求为ready/valid和2bit模式，3拒绝。`request_seq`每次合法接纳加1，32bit按模回绕；重置requested/active为RAW、序号0、active_valid为0。拒绝事件保持至接纳，阻塞时请求ready为0。
- 上下文输入为valid、frame_id、slot、generation、参数化数据；数据含义由调用方定义。调用方保证frame_id非零、slot有效、地址等已校验，同一身份/generation的上下文不可变。结果资格为`result_valid && result_frame_id==context_frame_id`；有效无脸结果可在BOX/AVATAR提交空叠加，不要求头像资源。
- capability[0/1/2]对应RAW/BOX/AVATAR；能力缺失置unavailable。无上下文/同帧结果/非空AVATAR资源未就绪时pending，保留active。准备允许后发cmd，命令包含mode/seq/frame_id/slot/generation/data；valid至ready期间全部保持。接纳后只允许一个在途命令，继续接纳新请求并合并尚未发出的中间值。
- 实际commit反馈含相同mode/seq/frame_id/slot/generation；仅匹配在途项才更新active并加commit计数。反馈在无在途时ready为0；不匹配反馈被消耗、置sticky protocol_error并计数，仍等待正确反馈。不会因命令接纳而提前更新active。
- 新请求与准备同拍时先接纳请求，下一拍准备，避免发出已被当拍取代的值。合并计数只记录被新请求替代且尚未冻结发出的旧请求；已冻结或已接纳命令不算合并。
- 请求完成性用独立dirty和在途命令覆盖标记维护，不能仅比较32bit请求/提交序号；即使完整回绕后数值相同，新请求仍需其实际提交。同拍接纳新请求不能被旧反馈清除。
- 同帧新generation/新帧上下文在旧命令等待期间改变，旧命令仍保持并退休，随后按最新上下文和最后请求准备新命令。消费者必须将raw与叠加/模式在安全边界原子提交，不能只把此组件输出接像素mux。上下文撤销不会取消已公开命令；协调reset才清除命令/反馈状态。

## Task 1：保护基线和RED

**Files:** `build/video/mode_control_baseline.json`、`tb/video/tb_video_button_debounce.sv`、`tb/video/tb_display_mode_control.sv`。

- [x] 保存HEAD、全部既有dirty文件和F2/旧双窗/公共配置哈希，确认没有既有暂存。
- [x] 按去抖门槛独立参考计数检查同步延迟、门槛前/恰好/之后、长按、抖动、释放重武装、复位按住、未知和1周期门槛；使用1001Hz/20ms验证向上取整21周期，默认125MHz另验证2500000周期。
- [x] 控制测试用真实ready/valid任务驱动，检查默认RAW、三模式循环、非法请求保持拒绝、capability/unavailable、错帧/未就绪pending、有效无脸、命令背压保持、接纳与提交区分、等待中新请求合并、上下文变化、错反馈、复位及序号回绕；case14/15/16检查未发出请求别名、旧在途命令别名及新请求与旧反馈同拍。

```systemverilog
// 关键断言：命令在背压期间全部稳定，active只跟随匹配的实际commit。
if (held_valid && !held_ready)
    assert ({cmd_mode,cmd_seq,cmd_frame_id,cmd_slot,cmd_generation,cmd_data} === held_payload);
assert (active_mode == previously_committed_mode);
```

- [x] 用`build/video/mode_control_red/`中的直通去抖/接纳即生效故意错误替身运行同一测试；要求非零且分别报告门槛/提前active错误，保存RED日志。替身不进正式filelist。

## Task 2：GREEN与正式入口

**Files:** 新增`rtl/video/video_button_debounce.sv`、`rtl/video/display_mode_control.sv`、`fpga/pg2l100h/project/video_button_debounce.json`、`video_mode_control.json`，约束`video_button_debounce.fdc`、`video_mode_control.fdc`；修改`scripts/video/run.py`、`build_pds.py`。

- [x] 先实现去抖计数和两个同步寄存，仅把异步引脚到首级设false-path，第二级和计数保持8ns约束。
- [x] 控制器独立请求/拒绝、命令offer、await_commit、活动状态；持有cmd payload，只有匹配反馈更新active。使用`CONTEXT_WIDTH`参数透传完整上下文，不在此发起DDR或槽释放。
- [x] 用`python scripts/video/run.py --suite mode_control`运行两个组件及门槛参数组合；只有每个仿真唯一PASS且退出0才通过，保存全部来源/工具/产物哈希。
- [x] 向`--suite all`加入新套件；显式两个组件目标只能综合，不能误打包成板级位流。
- [x] `python scripts/video/build_pds.py --target video_button_debounce --stage synth`及`--target video_mode_control --stage synth`，保持8ns，记录实际LUT/FF/DRM/APM及估计setup；不称布线或板测。

## Task 3：审查、回归与交付

**Files:** `docs/interfaces/video.md`、`docs/video/{README,STATUS}.md`、`docs/verification/video/mode_control.md`及`evidence/mode_control.json`。

- [x] 按requesting-code-review技能独立审查资格、序号/合并、背压、上下文及复位；以独立错误/边界或突变检查测试有效性，修复实质发现。
- [x] 冻结输入后运行`python scripts/video/run.py --suite all`和`python -m unittest discover -s tb/video -p test_*.py`，记录实际通过/跳过与日志哈希；新运行不能沿用旧PASS。
- [x] 文档发布本组件接口、资格前提和下游安全帧边界责任；明确F3b叠加、F3c按键管脚/CDC/板测尚未完成，MODE没有接到当前F2硬件。
- [x] 核对全部保留来源和构建输入，精确暂存本批Video文件、本地提交，不连带其他路线。

后续F3b实现16框/可选五点、RGBA最近邻/Alpha及裁剪像素oracle；F3c才核对实际MODE管脚、加入跨域原子提交和独立三模式板级目标。F4仍负责共同显示ABI/CPU所有者和共享DDR。
