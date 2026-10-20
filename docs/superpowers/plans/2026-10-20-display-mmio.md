# F4b Display ABI/MMIO Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans in the authorized Video checkout; independent review follows superpowers:requesting-code-review. No parallel implementation or branch switch.

**Goal:** 同源640B显示记录、验证后的AXI-Lite提交/事件和C驱动，接F4a而不修改旧采帧ABI。

**Architecture:** JSON生成RTL/C常量；shadow在逐框校验期间保持，合格后交显示引用所有者。
commit/release/reject保持到显式ACK，实际像素/DDR反馈是外部接口。

**Tech Stack:** PowerShell/Python/SystemVerilog/Icarus/PDS、现有Windows C工具。

## Task 1：同源定义与失败测试

**Files:** `config/video_display.json`、`scripts/video/gen_display_abi.py`、
`tb/video/test_display_abi.py`、生成的`rtl/video/include/video_display.vh`与`sw/include/video_display_abi.h`。

- [x] 先用字面期望检查0x20011000、640B/160word、shadow0x100、16×8word框及字段，坏类型/重复键/漂移拒绝；空实现必须RED。
- [x] 严格固定版本、生成确定输出和`--check`，不改capture配置/头；记录配置与输出hash。

## Task 2：记录检查和端点

**Files:** `rtl/video/display_record_guard.sv`、`rtl/video/video_display_mmio.sv`、
`tb/video/tb_video_display_mmio.sv`。

- [x] 空端点先在版本/提交检查失败；保存RED。自校验按字面地址驱动完整AXI事务，不从DUT内部状态推断结果。
- [x] 实现保护shadow租约，头部检查后逐框验证，result/frame/代际、保留字、点mask、正面积、素材64bit界限及能力失败不得保留槽。
- [x] 独立AW/W、稳定B/R、strobe合并、错误访问无副作用，接F4a完整记录data，不将B响应当commit。
- [x] 实际feedback保持commit；完整retire保持release到ACK后FREE；验证shadow可复用但已公开命令不变、MODE完整context相同。
- [x] 覆盖同拍事件/ACK、背压、错误/未知响应、三槽、协调reset；破坏冻结/校验/释放的变异须检出。

## Task 3：C驱动

**Files:** `sw/include/video_display.h`、`sw/drivers/video_display.c`、`tb/video/test_display_driver.c`。

- [x] 先断言完整字序、版本/忙检查、fence先于SUBMIT、错误不继续发布、事件读取不暗中ACK。
- [x] 实现显式I/O回调与640B无脸初始化、提交、保持事件读取和ACK；验证真实C编译/执行或明确记录工具限制。

## Task 4：入口、审查与交付

**Files:** runner/PDS入口、显式`video_display_mmio`manifest/FDC、Video接口/台账/README、主规格11.3与验证证据。

- [x] 新增`--suite display_mmio`及synth-only目标，运行新套件、display_slots、capture_mmio、Python和配置检查。
- [x] 125MHz组件综合，逐项核对实际资源/估计路径/警告；无新布线或板测声明。
- [x] 独立审查校验、记录冻结、事件ACK、CPU/硬件所有者边界和驱动排序，修复实质问题后鲜验证。
- [x] 小范围本地提交，保留其他路线修改及旧板测字节；全局allocator/共享DDR/真实退休生产者另批接入。
