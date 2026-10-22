# Video Record Probe Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to execute task-by-task.

**Goal:** 完整采显组合在双时钟注册边界下可布局布线，得到真实内部时序。

**Architecture:** 生成器只接受现有明确端口/约束格式，生成扫描 wrapper、FDC
和包含位映射的显式 manifest。现有 PDS 入口只对新目标开放 route，禁止位流。

**Tech Stack:** Windows Python、Icarus、PDS 2022.2-SP6.4。

- [x] 先写 `tb/video/test_record_probe.py`：接口完整覆盖、708/1148/26/341 位宽、
  域重复/缺失、错误时钟和未知约束拒绝，12 个物理端口、全部 16 条 CDC 约束
  仅加实例前缀，max/min 预算和额外 uncertainty 明确核验。
- [x] 运行测试观察缺失生成器导致失败，再实现 `scripts/video/gen_record_probe.py`。
  `python scripts/video/gen_record_probe.py --check` 必须检查全部生成文件。
- [x] 用独立测试 stub 验证全部扫描端口映射、shift/capture/hold/reset/双域隔离；
  用真实 RTL 对照 reset/idle。失败退出非零，证据放 build/video。
- [x] 给 `scripts/video/build_pds.py` 增加新目标、生成检查和输入绑定；仅新目标
  允许组件 route，拒绝 bitstream；既有默认及组件诊断入口保持兼容。
- [x] 运行原 PDS 25 项及新测试的普通/-O版本；独立审查边界和约束，不扩大
  时序/协议结论。所有自有文件均用显式清单，不递归引入 RTL。
- [ ] `python scripts/video/build_pds.py --target video_record_probe --stage route
  --seed-start 4 --seed-count 1 --pnr-mode performance` 保存首轮物理基线。
  核验源快照、约束适用与 slow/fast 的 setup/hold/recovery/removal/pulse-width。
- [x] 若有真实内部失败，先建立可失败回归，再作最小且协议正确的调整；不通过
  放宽周期或 blanket CDC 切除来过关。重复测试仅由变更或新失败触发。
- [ ] 更新规格、STATUS、验证记录和机器证据，最终审查后作本地小范围提交，
  通过 STATUS index projection 保留其他路线追加；提交后复核产物和保护哈希。

## 2026-10-22 检查点

- 前五项及最小产品调整已完成。Python普通/-O各46项、旧/新2723写2883读、
  既有MMIO驱动与6健康/3显示组合通过，独立审查问题已关闭。
- 首轮route中断，冻结旧版和字节使能版以各自DB独立布线，尚无最终报告。
  第六项保持开放，不把placement-only报告记为route完成。
- 新版相同估计连线模型core−2.953/pixel−1.184ns，最差13级；core未比旧版
  −2.841ns改善。普通report_timing读placement DB的零连线正值单独留存。
- 本批交付是注册边界、功能等价字节使能、严格验收与可续跑证据检查点。
  125MHz闭合未完成，最终route和后续地址/高扇出路径调整需继续执行。
