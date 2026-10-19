# F3c core 错误控制流水实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. 当前共享 Video 分支内执行，不另建工作树，不派实现代理；独立审查按 requesting-code-review。

**Goal:** 在 core8ns、pixel25ns、原跨域约束及 AXI 所有权不变的条件下，切断三分支结果字节数校验到缩放器使能的长组合链，完成合格三模式位流及现场验收。

**Architecture:** 在 `video_three_branch_capture` 的第一错误码与数据通路停止之间增加一个 core 寄存边界。正常路径的事务及画面不变，故障锁存允许晚一个 core 周期；pending 故障立即阻止新描述符并驱动 cancel/子 DMA abort。成功发布使用独立的标量故障检查，防止 WAIT_EVENT 恰逢 abort/offline 时漏报失败。错误帧内的合法数据计数可包含故障检测边沿的一次接纳，不能发布成功或提前释放已公开事务。

**Tech Stack:** Windows PowerShell、Python、SystemVerilog、Icarus、PDS2022.2-SP6.4；PG2L100H。

## 依据和取舍

此前三轮局部逻辑优化的公开周期等价检查均通过，但实际布局仍未闭合。最新构建 `20261019T182101_599588Z` 为17365 LUT/18737 FF/73.5 DRM/16 APM，setup -0.225ns/18端点、hold slow/fast +0.124/+0.089ns；最差为 preview DMA written_bytes→结果校验→停止控制→preview scaler CE。网表140管脚/77同步链/13束审计通过，失败镜像未打包或下载。

推荐内部控制流水；另一选择是维持原逐拍行为并尝试区域布局。已向用户说明两种取舍，内部等待周期属于当前实施范围内的建议默认值。本计划不以放宽8ns或新增多周期例外解决问题；不引入新输出模式、NPU结果、多帧槽或新外设。

## Task 1：故障和成功边界测试先行

**Files:** 修改 `tb/video/tb_video_three_branch_capture.sv` 或新增其独立定向 bench；验证副本/日志放 `build/video/capture_fault_pipeline/`。保留改造前 `rtl/video/video_three_branch_capture.sv` 原字节及哈希。

- [x] 建立独立握手 scoreboard：descriptor只接纳一次；所有曝光AW/W/B必须排空；失败completion永不success；结果背压时保持；reset前后的帧上下文不能混用。
- [x] 覆盖终态result字节数/标签/成功位错误与abort同拍、下一拍online丢失、最后一项retire与故障同拍、WAIT_EVENT即将发布时abort/source_fault、pending时新descriptor、已公开AW/W/B各阶段故障、像素/EOF及缩小流错误。
- [x] 以预期不变量检查时序，不强制改造前后的故障锁存周期相等；正常成功数据/地址/CRC/提交仍须相等。漏pending隔离或漏成功边界guard的替身必须编译后失败。

```systemverilog
if (dut.fault_pending && dut.req_ready)
    $fatal(1,"pending fault advertised descriptor acceptance");
if (!previous_completion_valid && completion_valid && completion_success && dut.fault_pending)
    $fatal(1,"pending fault published successful frame");
if (held_completion && !completion_ready && completion_bundle !== previous_bundle)
    $fatal(1,"completion changed while held");
```

## Task 2：最小 core 寄存边界

**Files:** 只修改 `rtl/video/video_three_branch_capture.sv`，原所有权/描述符/三分支AXI代码保留。

- [x] 新增第一故障码寄存器；只在为空时捕获原 `fault_now`，不覆盖较早原因。所有复位仍来自既有协调core reset。

```systemverilog
reg [7:0] fault_stage_code;
wire fault_pending=fault_stage_code!=0;
always @(posedge clk or negedge reset_n)begin
    if(!reset_n)fault_stage_code<=0;
    else if(fault_stage_code==0 && fault_now!=0)fault_stage_code<=fault_now;
end
```

- [x] `transport_stop` 和 `stopping` 均使用 `error||fault_pending`。`req_ready` 加 `!fault_pending`；cancel和三个子DMA的abort使用 `error||fault_pending`。主状态机从 `fault_stage_code` 锁存公开错误码，保持原DRAIN/port_drained/held completion。
- [x] 合法像素计数/CRC更新额外以 `pixel_legal` 或 `eof_legal` 限定；preview/input更新分别以现有 `preview_legal/input_legal` 限定，避免未知/非法数据因控制流水进入摘要。不能把宽位result计数比较重新接回实时ready/valid。
- [x] 为WAIT_EVENT单独生成 `commit_fast_fault`：按原优先级检查online、arb_fault、writer_fault、abort、overflow、source_fault，排除已经retired的result payload比较。成功发布同时要求 `commit_fast_fault==0`。在WAIT_EVENT之前原条件已要求eof_seen、全部retired、port_drained及count_good，须以测试确认该阶段不存在未验证结果。

```systemverilog
WAIT_EVENT:if(accepted_consumed && commit_fast_fault==0)begin
    completion_valid<=1;completion_success<=1;completion_code<=0;state<=DONE;
end
```

- [x] 核对 fault_now 原第一原因优先级、所有已发布AXI不撤回、first accepted帧事件以及held completion不变。失败帧不发布给raw扫描；MODE/SOF/pad流水不修改。

## Task 3：回归与独立审查

- [x] 运行定向bench、`python scripts/video/run.py --suite three_capture`、`--suite raw_board`、`--suite mode_board`；按新语义对故障接纳/排空检查，不删除失败场景或放宽数据检查。
- [x] 独立审查 pending隔离、第一错误、WAIT_EVENT、超时、复位和所有权。更新父审计为有记录的capture例外，其余冻结输入逐项核对。
- [x] 数字通过后精确本地检查点提交，保留原位流；不得将数字通过标作时序或板测通过。

## Task 4：实际实现和现场

- [ ] 原约束实际综合/布线；依据新报告检查路径，完成140管脚、素材RAM、77同步链和13束的结构/物理端点审计。全部setup/hold/recovery/removal通过才打包。
- [ ] 易失Program/Verify，绑定Program会话记录UART。实际RAW、三次KEY1及KEY0桌面重采、60秒稳定性仍按原F3c验收，不由仿真或旧日志替代。
- [ ] 更新 `docs/video/STATUS.md`、`docs/verification/video/mode_board.md` 及来源/位流/现场证据；精确本地提交，不push/merge/Flash。
