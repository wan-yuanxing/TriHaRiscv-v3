# F4c1 CPU Frame Pool Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans in the authorized Video checkout.
> Independent review follows superpowers:requesting-code-review. No parallel implementation,
> branch switch or CPU worktree edits.

**Goal:** CPU唯一维护三槽生命周期、整图工作区租约和ACK后的全局释放。

**Architecture:** C库保存不可混帧的状态和唯一计算/显示在途记录；复用显示驱动，
保持外部DMA/NPU资格和实际fence边界。C真实事务回放到既有显示RTL。

**Tech Stack:** Windows PowerShell/Python、现有MinGW/xPack GCC、Icarus，无新环境。

## Task 1：接口与可失败的策略测试

Files: `sw/include/video_frame_pool.h`, `tb/video/test_video_frame_pool.c`.

- [x] 定义token、allocation、阶段、错误、统计及init/allocate/capture_done/graph_begin/
  operator_begin/operator_done/result_ready/drop/present/poll_display/fail/recover接口。
- [x] C测试字面核对0x82000000/0x82200000/0x82400000、preview+0x160000及input
  0x82800000/0x82850000/0x828a0000；三槽占用不覆盖、graph锁跨算子空闲保持。
- [x] 空实现必须在分配身份/地址断言失败，保存RED；随后实现最小策略到GREEN。

```c
struct video_frame_pool pool;
struct video_frame_allocation a;
video_frame_pool_init(&pool, 7);
assert(video_frame_pool_allocate(&pool, &a) == 0);
assert(a.id.slot == 0 && a.id.frame == 1 && a.id.generation == 7);
assert(a.raw_base == 0x82000000u && a.input_base == 0x82800000u);
```

## Task 2：事件、错误和实际C驱动

Files: `sw/drivers/video_frame_pool.c`, same native C test.

- [x] 先测试旧代/错frame/tag及重复反馈不推进状态，软件tag顺序/回绕/耗尽不复用；发布/事件读取/ACK全部回调失败
  均停止新任务并保持引用；错误后合法反馈可排空，recover仅接受完整证明和新epoch。
- [x] 实现present/poll_display，验证全事件快照后ACK、ACK后改状态；同帧MODE不释放，
  合并commit/release合法，新帧拒绝回READY_DISPLAY，回退显示frame拒绝。
- [x] 计数饱和、frame耗尽、丢弃原因和输出参数失败不改；无脸模板不能跳过计算资格。

## Task 3：真实事务回放与正式入口

Files: `scripts/video/test_frame_pool.py`, `tb/video/tb_video_frame_pool.sv`, `scripts/video/run.py`.

- [x] 原生C产生R/W/等待命令提交/退休/拒绝事务；TB驱动现有video_display_mmio、guard
  和owner，逐字比较读值/640B命令及mode/seq/身份，不能以纯模型替换正式RTL。
- [x] MinGW实际运行及RV32I/ILP32对象编译；快照hash前后核对、失败非零、旧成功先失效。
- [x] 增加frame_pool套件并重跑display_mmio/display_slots/capture_mmio/Python配置检查。

```powershell
python scripts/video/test_frame_pool.py
python scripts/video/run.py --suite frame_pool
python scripts/video/run.py --suite display_mmio
python scripts/video/run.py --suite display_slots
python scripts/video/run.py --suite capture_mmio
```

## Task 4：审查与交付

Files: Video接口/README/STATUS、主规格9.5实施注记、`docs/verification/video/frame_pool.md`
and `docs/verification/video/evidence/frame_pool.json`.

- [x] 针对整图锁、提前释放、ACK失败、旧身份与MODE错误编制变异，必须由实际断言检出。
- [x] 独立审查策略、原生测试和RTL回放，核对CPU唯一所有者、错误引用和共享DDR边界。
- [x] 更新证据并验证既有冻结来源、其他路线文件和工作字节；精确暂存、本地提交，
  不把软件组件结果冒称CPU执行、连续采集、共享fabric、布线或新增板测。
