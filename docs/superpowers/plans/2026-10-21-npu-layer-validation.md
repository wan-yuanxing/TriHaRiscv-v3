# NPU 逐层 RTL 验证执行计划

**Goal:** 复用冻结数值包，验证当前47个卷积层的真实尺寸/完整输出，明确其余32算子硬件缺口。

**Architecture:** 独立主机资产导出 → 冻结真实RTL → 全尺寸行存储仿真 → 每层全量输出对照。ModelSim作为交叉核验；原生编译仿真可加速同源执行。

**Tech Stack:** Windows、Python/NumPy/既有ONNX参考、Verilog、ModelSim、可复现的本地编译仿真工具。继续执行已获授权，使用subagent-driven-development分工及先规格后质量审查，不提交或推送。

- [x] 复用隔离工作树并核对生成器/报告测试基线，盘点79算子及47卷积真实形状/MAC。
- [x] 资产：`scripts/npu/test_layer_assets.py` 先验证输入损坏拒绝、47/32计数、真实参数布局、全部tensor及历史head身份；执行 `python -m unittest discover -s scripts/npu -p test_layer_assets.py -v` 得到RED。
- [x] 实现 `scripts/npu/layer_assets.py` 的 `prepare(output, npu_root)`，独立保存三输入80tensor与47层完整二进制/32word配置；上项测试GREEN，保留源/模型/产物hash。
- [x] 仿真：新增 `tb/npu/tb_npu_layer.sv`、`scripts/npu/run_layer_rtl.py` 和 `test_layer_rtl.py`；小型独立fixture验证完整输出、非法资产/几何、损坏输出与选择子集的门槛。先RED后GREEN。
- [x] 工具：只在build下检验原生加速工具，记录来源/版本/hash；若可用，以同一DUT和向量在ModelSim/编译仿真对照，禁止force或跳算。
- [x] 全尺寸：`python scripts/npu/run_layer_rtl.py --manifest build/npu/layer_assets_full_20261021_final/manifest.json --cases zero full255 pattern --simulator compiled --jobs 3`，47层×3输入完整执行，保存每层实际输出、周期、结果。任何缩小范围必须标PARTIAL。
- [x] 独立规格审查：逐项核对真实形状、参数字节、三输入、完整输出计数、工具/输入身份及32未实现算子状态；问题修复后再查。
- [x] 独立质量审查：核验正反例、证据绑定/选择条件/退出码与代码可维护性；问题修复后重跑受影响验证。
- [x] 将本批明确文件迁回main，相关复测与保护检查；新增 `docs/verification/npu/2026-10-21-layer-validation.md` 和 `evidence/layer_validation.json`，仅追加main STATUS和外部项目台账。

文件责任：资产代理只写layer_assets/test_layer_assets；RTL harness代理只写tb_npu_layer/run_layer_rtl/test_layer_rtl；性能代理只在build试验；root负责工具适配、协调、审查、证据和主工程保护迁移。数据接口以同日设计文档为准，准备入口不重做校准。
