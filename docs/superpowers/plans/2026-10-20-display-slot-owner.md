# F4a Display Slot Owner Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans in the current authorized Video checkout. Steps use checkbox syntax. Independent review follows superpowers:requesting-code-review; no parallel implementation or shared-directory branch changes.

**Goal:** 实现显示引用三槽管理，区分命令接纳、实际commit和完整退休/ACK。

**Architecture:** 新组件冻结完整参数化context，依据公共槽地址接纳新帧，MODE仅更新当前
记录的mode/seq。每槽独立状态与保持事件保护全部引用；全局采集/NPU所有权仍在上层。

**Tech Stack:** Windows PowerShell、Python、SystemVerilog、Icarus、PDS，core8ns组件估计。

## Task 1：测试先行

**Files:** Create `tb/video/tb_display_slot_owner.sv`；临时RED替身和日志仅在`build/video/`。

- [x] 写独立记分板和提交/反馈/退休驱动，先断言新提交保留槽但不提前active：

```systemverilog
check(slot_free_o == 3'b110 && !active_valid_o,
      "accepted frame is reserved, not yet active");
```

- [x] 用无行为接口替身实际运行，必须因未保留槽/无下游命令而失败并保存日志。
- [x] 增加三槽轮换、模式不释放、迟到退休、事件背压、同拍commit/退休、非法/X/重复反馈、
  非法基址/stride/frame/slot/mode、MODE原图/context变更、序号回绕与协调复位用例。

## Task 2：所有者实现

**Files:** Create `rtl/video/display_slot_owner.sv`。

- [x] 用5态/槽实现显示引用；FREE判定仅来自显式状态：

```systemverilog
localparam [2:0] FREE=0, RESERVED=1, ACTIVE=2, RETIRING=3, WAIT_ACK=4;
```

- [x] 接纳新帧即保留其slot/frame/generation，冻结命令直到真实提交；MODE核对完整active身份。
- [x] 实际commit匹配冻结记录才推进活动身份和旧槽退休，独立保持commit事件。
- [x] 校验退休身份并支持与合法新帧commit同拍；先WAIT_ACK，再在release握手后FREE。
- [x] 错反馈锁存首错；保留已公开命令并排空已有合法反馈；所有新提交停止。
- [x] 运行全用例，窄/宽context和确定种子的三槽压力；提前释放、模式释放和错seq替身必须失败。

## Task 3：显式入口与综合

**Files:** Modify `scripts/video/run.py`、`scripts/video/build_pds.py`；Create
`fpga/pg2l100h/project/video_display_slot_owner.json`、`constraints/video_display_slot_owner.fdc`。

- [x] 在既有runner加入`--suite display_slots`并纳入all，记录来源、工具与产物哈希。
- [x] 显式清单只列新RTL/TB；FDC为`create_clock -name clk_i -period 8.000 [get_ports {clk_i}]`。
- [x] 保持组件目标只允许synth。运行：

```powershell
python scripts/video/run.py --suite display_slots
python scripts/video/run.py --suite mode_control
python scripts/video/gen_config.py --check
python scripts/video/gen_regs.py --check
python scripts/video/build_pds.py --target video_display_slot_owner --stage synth
```

## Task 4：审查与收尾

**Files:** Update `docs/video/STATUS.md`、`docs/video/README.md`、`docs/interfaces/video.md`；Create
`docs/verification/video/display_slots.md`、`docs/verification/video/evidence/display_slots.json`。

- [x] 独立审查提前释放、同时事件优先级、首错与未知输入、复位及上下文冻结；逐项复核发现。
- [x] 运行Python回归和受影响RTL套件；原三模式板测保留为历史证据，不冒称本组件已上板。
- [x] 记录实际资源/时序估计、回归/变异/审查来源哈希、未实现F4b/F4c边界。
- [x] `git diff --check`并精确本地提交本批文件，保留其他路线原始字节，不push/merge/Flash。
