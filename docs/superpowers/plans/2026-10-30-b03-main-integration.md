# B03 NPU 主工程集成总计划

> 执行方式：在当前主工程按阶段顺序实施；使用 superpowers:executing-plans 管理实现与检查点。本文是跨 CPU/NPU/Video 的总计划，各阶段在接口冻结后再展开为小范围实现任务，不把未实现模块或建议命令记为已存在。

**Goal:** 在 `D:/FPGA/TriHaRiscv-main` 接通 CPU 帧控制、B03 整网/后处理和 Video 同帧显示，并逐步完成资源、时序、板测、五点与有效输出帧率验收。

**Architecture:** NPU 自主运行 Graph/Layer/POST，CPU 只管理任务/帧、选择头像和提交显示。复用主工程唯一 AXI128/HMIC/DDR 路线，适配 B03 256 位服务，统一 100/125MHz CDC、不可缓存共享区、发布及恢复。

**Tech Stack:** Windows PowerShell、Python、Verilog/SystemVerilog、ModelSim 2020.4、PDS 2022.2-SP6.4、现有 RISC-V GCC；不新增 WSL 或 HDL 生成环境。

设计与事实依据：[集成设计提案](../specs/2026-10-30-b03-main-integration-design.md)、[上游审查证据](../../verification/npu/2026-10-30-upstream-integration-audit.json)。

## 本轮完成

- [x] 使用系统代理和现有身份拉取 GitHub，独立确认 HEAD/main 为 `558280b30219acdcf9f962acd6e907e0f680ab52`。
- [x] 核对主工程 `18d4c4c`、CPU 维护工作树及 Video/NPU 分项证据。
- [x] 用户确认采用 B03 整网与后处理，CPU 管理帧和显示。
- [x] 识别资源超紧、scope0、运行资产缺失、163同源证明缺口及五点差异。
- [x] 在主工程保存设计、阶段计划及来源哈希；未进行产品代码集成。
- [x] 将最终应用收拢为 `triha_face_board_top`，并接入显式板级 source list、HDMI/DDR 约束和最终应用说明。
- [x] 完成真实 CPU→采集/预处理→B03 整网/POST→CPU 结果读取→同帧 BOX 像素→三槽退休/复用闭环；结果保存在 `build/soc/face_system-20261030T151819_944972Z/result.json`。
- [x] 运行正式 PDS synth 入口；PDS 在 CPU 源 RTL 分析阶段因当前 Verilog 前端拒绝 CPU 中的 SystemVerilog 语法而停止，未把该次运行记为综合通过。

## M0：可复现基线与统一预算（第一批优先执行）

文件：新增 `rtl/npu/upstream/b03/UPSTREAM.json`、`model/yunet/UPSTREAM.json`、`config/soc_resources.json`、`scripts/npu/import_b03.py`、`scripts/npu/audit_b03_assets.py`、`docs/verification/soc/resource_budget.md`；更新 `docs/interfaces/npu.md` 与 `docs/TriHaRiscv_SoC_Design_Spec_v0.6.md` 的职责/调度/完成事件定义。

- [ ] 从固定 Git 对象提取 payload 功能闭包、必要原语 wrapper、模型参考与测试源码；生成明确 filelist、路径映射和逐文件 SHA，保留原始字节/许可。
- [ ] 将运行路径从 E:/npu_zgtc、旧 ModelSim/PDS 目录适配到主工程工具发现入口；不在生产 filelist 递归搜集上游所有候选 RTL。
- [ ] 列出 runtime 68 项及编译器输入的本地可用/可重建/缺失情况；重建 program、parameter、POST table 和三组合成输入，并与上游 manifest SHA 对照。
- [ ] 对 calibration_image_000、wider_stress_0/1 优先寻找已有合法本地冻结输入；缺失时列出精确文件/SHA作为额外依赖。可先继续组件验证，但六图验收保持未完成。
- [ ] 按同一综合/映射边界统计 CPU、NPU、POST、Video、HMIC、CDC、素材；去掉重复平台外壳，先测共享资源再设置分项上限。
- [ ] 形成现有 64DRM 头像缓存替代方案；首轮目标 RAW/BOX，AVATAR 的行/块缓存单独验收。

出口：主工程内可重现的来源/资产清单、资源分账、正式输入及任务布局提案；没有把“源码已拿到”记为硬件可集成。

## M1：CPU 与 B03 计算核心准入

文件：维护 `rtl/cpu/`、`rtl/npu/upstream/b03/`；新增 `config/npu_b03_sources.f`、`tb/npu/tb_b03_graph.sv`、`scripts/npu/run_b03_graph.py`、`docs/verification/npu/b03_graph.md`；按需迁入 CPU 原有配置/测试脚本。

- [ ] 以 CPU 证据提交 `340bcc2`、接受实现 `febadb3` 为追溯起点，核对后续 ISA/IRQ/取消修复的实际源 SHA。未提交修改逐项审查，导入被所选测试证据覆盖的集合，不能复制整个脏工作树。
- [ ] 保留已有 CPU/旧 NPU 单算子测试作快速诊断；生产目标只选 B03 整网核心，避免重复实例化标量卷积。
- [ ] B03 六图逐项实际运行 79 算子，逐字节比较中间张量/HEAD/最终记录；完整两帧冷暖回归绑定同一 Graph、Layer、POST 源集合。
- [ ] 数据破坏、结果注错和源哈希变化必须拒绝通过；部分用例缺失不能签成全矩阵 PASS。
- [ ] 163/fo128 或其他面积候选只有在新闭包六图及整帧证据齐全后才替换导入基线。

出口：主工程源码可构建、选定核心本地功能回归成立；仍不声称共享 DDR 或整机物理通过。

## M2：帧控制 ABI、地址生成与 CPU 驱动

文件：新增 `config/npu_frame_regs.json`、`config/soc_memory.json`、`scripts/soc/gen_config.py`、`rtl/npu/npu_frame_mmio.v`、`rtl/npu/npu_frame_top.v`、`sw/include/npu_frame.h`、`sw/drivers/npu_frame.c`、`tb/npu/tb_npu_frame_mmio.sv`、`tb/soc/tb_soc_control.sv`；维护 `rtl/soc/` 控制译码及 `docs/interfaces/npu.md`。

- [ ] 生成 frame ABI 的 RTL/C/Python 常量和 BMD3 任务构造，不手改三份地址/字段。
- [ ] 先建立自校验用例：独立 AW/W、WSTRB、读写背压、START 快照、BUSY 拒写、完成待 ACK、同拍事件/W1C、错身份 ACK、地址越界、frame/generation 耗尽。
- [ ] 实现 frame MMIO 与 B03 start/done 适配；完成快照读回不清事件，ACK 后才接新任务。
- [ ] 补 100→125MHz Video AXI-Lite/mailbox 控制边界及事件同步，运行采集/显示原 ABI 回归。
- [ ] 任务构造按实际 800×600、320×240、pad(0,40)；输入 A/B/C 使用原地址；新输出槽、程序、参数、POST表、workspace 逐区域核重叠/权限/加法溢出。

出口：真实 CPU 固件能提交帧描述符并正确处理模拟完成/错误；模拟端点只证明控制，不记为整网运行。

## M3：256 位服务适配、共享仲裁与 CDC

文件：新增 `rtl/soc/npu_service_axi128.v`、`rtl/soc/soc_compute_arbiter.v`、`rtl/soc/soc_ddr_fabric.v`、`tb/soc/tb_npu_service_axi128.sv`、`tb/soc/tb_soc_ddr_fabric.sv`、`scripts/soc/run.py`；按 SHA 迁入并适配 CPU 现有 `triha_axi128_cdc.v`。维护 Video shared-DDR 边界与显式工程清单。

- [ ] 先用独立字节内存 scoreboard 验证 32B↔16B、所有 byte mask、最大16服务拍→两笔16拍AXI、4KiB边界与尾拍。
- [ ] 为 MODEL 块服务和 POST CMD/W/R/DONE 保留 owner/tag/epoch 与债务核算，全部子事务退休后才上报原命令完成。
- [ ] CPU/NPU 同钟事务仲裁后共用 CDC；125MHz 统一接采集写、扫描读与素材读，唯一出口为主工程 `axi128_hmic256`。
- [ ] 验证各主端响应归属、AW/W任意先后、R/B背压、错误ID/LAST/RESP、失锁、迟到响应和持续竞争下的服务配额。
- [ ] 确认 B03 supervisor 不再直接控制独占 HMIC reset；复位请求交给系统监督器。

出口：所有主端只通过一个 native 所有者访问 DDR；响应与排空测试通过，CDC 功能和后续物理约束分别记录。

## M4：跨主端可见性、发布与全局恢复

文件：新增 `rtl/soc/soc_memory_supervisor.v`、`tb/soc/tb_soc_publish_recovery.sv`、`docs/interfaces/soc_memory.md`；更新 `sw/drivers/npu_frame.c`、`sw/drivers/video_frame_pool.c` 和对应头文件。

- [ ] 建立 CPU写模型→NPU读、Video写输入→NPU读、NPU写结果→CPU读、CPU提交→Video读的实际跨主端测试；禁止走 TB 旁路读口。
- [ ] 末B延迟、CDC未排空、旧epoch完成、缓存旧行、写后读损坏均必须阻止成功发布/槽释放。
- [ ] 共享区域所有 CPU 访问走不可缓存路径；CPU私有 cache 与共享属性边界同时验证，不使用裸软件 fence 冒充 cache 清理证明。
- [ ] 实现系统级健康/排空/错误归因与协调恢复：停新任务、保留首错、旧结果失效、旧引用禁止复用、重新校准及新generation。
- [ ] B03 私有诊断头原字段保留；系统单独产出已验证的发布状态，不把 production_release0 改1冒充平台证明。

出口：四条写后读链路与故障恢复有可复现证据，CPU 帧池才能接收生产成功结果。

## M5：真实 CPU→整网→最终框闭环

文件：新增 `sw/tests/npu_frame/` 的固件及启动/链接文件、`tb/soc/tb_cpu_b03.sv`、`scripts/soc/run_cpu_b03.py`、`docs/verification/soc/cpu_b03.md`。

- [ ] 一次装载模型、参数、POST表，CPU提交单帧；B03实际运行79算子和POST，CPU经正式fabric读取最终记录。
- [ ] 对照无脸、单脸、多脸压力输入，核对框/score/排序、CRC、cmd/frame/generation、冷暖周期及无在途债务。
- [ ] 运行 polling/IRQ、重复 START、超时、错误模型、错误输入范围和两次连续帧；错误任务不得复用上次结果。
- [ ] 保留包含真实 CPU PC/MMIO、NPU阶段、DDR事务及最终框的波形和输入/工具哈希。

出口：CPU仅做控制和消费，真实整网结果可读；没有Video也能独立验证系统核心。

## M6：Video 同帧 BOX 与三槽生命周期

文件：新增 `sw/apps/face_avatar/`、`tb/soc/tb_face_pipeline.sv`；修改 `sw/drivers/video_frame_pool.c`、`rtl/video/video_live_engine.sv` 的槽授权边界，复用 `video_record_pipeline`/记录显示组件；新增 `fpga/pg2l100h/rtl/triha_face_top.v` 和 `fpga/pg2l100h/project/triha_face_box.json`。

- [ ] CPU统一分配三槽，采集完成后锁定raw/input；NPU和显示释放前不复用，满槽时只丢未接受帧。
- [ ] 用实际NCHW DMA输出逐字节核对模型输入；CPU仅传地址与变换元信息。
- [ ] 最终框截取至显示上限16，构造640B显示记录并核frame/generation；清除人工五点和诊断框。
- [ ] 验证长推理、多脸、无脸、模式切换、结果延迟/乱序、采集丢帧、显示延迟释放及故障恢复；核原图与框同帧。
- [ ] RAW和BOX显示保持像素域提交/释放确认；记录每个独立处理帧首次可见时间。

出口：真实摄像头输入链数字联测成立，可进入资源合格后的整机实现；不把固定测试图或夹具结果写成真实NPU显示。

## M7：面积收敛、完整物理实现与板测

文件：维护 NPU 适配/派生模块、`config/soc_resources.json`、板级 FDC/RCF/filelist；新增 `docs/verification/soc/face_system.md` 与机器证据。

- [ ] 在 M0 分账基础上逐项验证 coverage RAM化、sumabs存储、向量选择网络共享；功能不变方案先比资源/周期，数值精度变更另审。
- [ ] 同一完整目标执行冷综合/映射，报告整机资源与各子系统开销；预算未收敛时继续组件改进，不盲跑满片PNR。
- [ ] 完整布局布线核100/125/40/27MHz、setup/hold/recovery/removal、Gray/bundled-data约束及板级电气引脚；保留失败报告。
- [ ] 生成具备版本/SHA的SRAM包，分项执行离线整网、CPU控制、持续RAW、真实BOX、模式和复位验收。
- [ ] 板上分别统计采集、检测完成、首次显示不同frame_id的速率、延迟分位数、丢帧与DDR等待；不以HDMI扫描率或UART传输率代替有效输出。

出口：当前功能范围的真实整机证据；此阶段通过仍不自动关闭五点及吞吐目标。

## M8：AVATAR、五点和吞吐目标

文件：维护 `model/yunet/`、NPU运行表/量化/输出契约、`rtl/video/`素材缓存与显示驱动、`sw/apps/face_avatar/`。

- [ ] 完成DDR素材行/块缓存，测试扫描最坏截止时间和显示背压；真实框选头像、同帧显示。
- [ ] 保留五点分支生成模型/量化/完整golden，扩展NPU输出和坐标恢复，重新核资源、槽容量及检测/关键点质量。
- [ ] 先分解当前91～96ms代理整帧的MODEL/POST/DMA/预检/表CRC成本，再选择缓存驻留、burst及控制调度优化；不得靠降低质量/容量或漏算等待满足fps。
- [ ] 以主规格有效输出≥24fps为优化目标，30fps单列进展；完整真实输入、后处理、提交及显示时间纳入统计。

出口：五点、AVATAR及目标性能各自有可审查证据；不能用bbox中间交付代替最终功能。

## 第一批的边界与现成检查

第一批执行 M0 和 M1 的来源/资产准入，并建立 M2 的接口测试；优先形成可重复仿真和统一资源账，不直接把B03诊断板顶层拼进现有Video目标。M3组件可以在天然图像资产补齐期间继续，六图结果必须等实际输入到齐。

以下命令是主工程已有入口，可用于建立此次集成前的短回归；本轮前两项生成一致性检查已通过，后四项硬件回归尚未执行：

```powershell
python scripts/video/gen_config.py --check
python scripts/npu/gen_regs.py --check
python scripts/npu/test_dma_runner.py
python scripts/npu/test_mmio_runner.py
python scripts/video/run.py --suite shared_video
python scripts/video/run.py --suite cpu_axil
```

每阶段新行为先建立能失败的自校验测试；通过后保存源/工具/输入/输出哈希。日志、波形、IP和PDS产物进入build，小型证据进入docs/verification。只提交阶段白名单，不连带技术报告、其他路线或上游工作文件。

本轮文档核对：19项本地/远端快照来源SHA保持一致，2份规划文档的4个相对链接有效，无占位项或尾随空白；`git diff --check`通过。Video台账按原字节前缀追加，既有技术报告未跟踪备份和上游未提交台账保持原位。没有运行新的RTL仿真、PDS或板测。
