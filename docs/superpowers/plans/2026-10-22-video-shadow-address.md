# Video Shadow Address Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans in the current session.

**Goal:** 消除 shadow 写入的动态地址算术/索引，保持每拍外部行为。

**Architecture:** AW 接收时锁存160位字选择；绝对范围比较、静态逐字节写入。
所有错误/锁定检查保持。用固定Git参考与当前leaf作逐拍miter，实际物理结果另验。

**Tech Stack:** Windows Python、Icarus、原生C GCC、PDS 2022.2-SP6.4。

- [x] 捕获2c9c67f基线、95项既有保护清单和旧布局负裕量，复核旧route输入不变。
- [x] 在 `tb/video/tb_display_shadow_bytes.sv` 的AW/W握手后毒化原总线；执行旧版
  2723写2883读，要求通过。新增 `scripts/video/test_shadow_decode.py`：从固定Git
  blob取参考leaf，严格解析全部端口，生成候选/参考双实例，每拍比较所有输出。
- [x] 先在旧leaf跑10个MMIO场景（含原生C写轨迹）及shadow测试；错误AW地址锁存
  和取消BVALID两个有效编译变体须以 `SHADOW_MITER_MISMATCH` 非零退出。
- [x] 将 `rtl/video/video_display_mmio.sv` shadow存储移至逐字generate进程：
  `select[g] <= awaddr_input == BASE+SHADOW_OFFSET+4*g` 仅在AW握手更新；
  `execute_write && do_shadow && select[g]` 时按4个WSTRB写固定word。原always内
  删除shadow reset/write，避免多驱动；窗口改绝对64位常量范围。其余逻辑不改。
- [x] 重跑miter，执行受影响健康/三模式显示组合，锁定源/工具/生成物哈希。
  原生C工具失败须记录真实失败，不用旧trace冒充本轮执行。
- [x] 同约束组件/完整采显综合，审查资源、无latch/多驱动及实际新路径；需要
  物理比较时用独立冻结快照布局，保留旧route，不放宽8/25/6ns约束。
- [ ] 更新规格、STATUS、验证和机器证据；独立审查，范围提交与提交后保护审计。
  最终route未完成时单列开放，不能以综合/布局正值替代签核。

完整综合与同约束布局/估计连线测量已完成：32881LUT/44678FF/69.5DRM，core−2.135ns/pixel+0.216ns；core setup/hold/recovery仍失败。完整route已从冻结DB启动，未完成。
