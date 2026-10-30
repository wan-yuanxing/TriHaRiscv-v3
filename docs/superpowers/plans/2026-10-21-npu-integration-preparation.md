# NPU合拢准备 Implementation Plan

> 本轮在当前会话顺序执行，每项以实际命令和结果验收；继续执行已获用户授权。

**Goal:** 交付可重复的CPU离线算子表、三槽重定位和资源检查入口。

**Architecture:** 读取外部冻结模型包，经独立标准库解析后转换为主规格逐算子C表。候选布局单独配置，不修改现有Video配置或硬件。

**Tech Stack:** Windows PowerShell、Python unittest、RV32I GCC15.2。

## 文件分工

- `config/npu_integration_fixture.json`：主机候选地址、CPU/fabric/素材预算。
- `scripts/npu/prepare_integration.py`：严格解析、完整性/布局校验、重定位、C表与机器证据导出。
- `scripts/npu/test_prepare_integration.py`：正例、损坏资产/非法布局拒绝、准备与硬件门槛区分。
- `docs/verification/npu/2026-10-21-integration-preparation.md`与`evidence/integration_preparation.json`：实际运行和局限。
- 两端已有任务台账仅追加本批记录；其他既有变更做哈希保护。

## Task 1：定义数据并先验证失败

- [x] 写候选配置，与设计文档中的大区、三输出槽及128/144DRM场景一致。
- [x] 写unittest，使用小型独立构造的小端程序测试解析；真实资产单独集成测试。
- [x] 运行`python -m unittest discover -s scripts/npu -p test_prepare_integration.py -v`，确认因准备工具尚未实现而失败。

## Task 2：实现并生成真实三槽包

- [x] 实现严格类型/整数边界、program header/records、manifest SHA与地址校验。
- [x] 张量input/head按slot重绑定，内部张量用workspace相对地址，参数映射权重区域；不改写原模型程序或算子。
- [x] 生成C表/JSON和参数镜像，记录输入/输出哈希；新输出目录独占，异常保留FAIL。
- [x] unittest全部通过后，用设计文档所列入口运行真实模型包。
- [x] 用同入口加`--require-hardware-ready`运行另一目录，确认实际退出2，普通准备仍PASS且硬件门槛false。

## Task 3：独立核对与记录

- [x] 用实际`riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -std=c11 -Wall -Wextra -Werror`编译引用生成表的C文件，输出ELF32目标文件。
- [x] 独立脚本逐地址复算三槽全部张量/参数、输出顺序和算子记录，核对所有引用哈希及保护文件。
- [x] 更新设计/计划执行状态、验证报告、小型机器摘要、main STATUS及NPU台账。
- [x] 对本批文件执行`git diff --check`和最终测试，报告已完成的准备与仍开放的硬件门槛。

实际结果见`docs/verification/npu/2026-10-21-integration-preparation.md`。最终33项测试通过；新增的独立小型MaxPool程序补齐了审查时的计划差异。首次保护检查发现既有Video计划在期间变化，本批未写入，证据单独记录；49项其他保护文件不变，台账采用原字节前缀保留、仅追加方式更新。本批未执行RTL/PDS或板卡编程。
