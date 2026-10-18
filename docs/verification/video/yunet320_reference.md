# YuNet 320 输入数值参考验证

用户选择优先适配现有NPU设计。设计/计划提交ef591a6规定后续目标为固定800×600 RGB888→320×240 UINT8 BGR双线性→上下各40行零→320×320三平面NCHW，共307200B。NPU来源为4fc0fc8的处理/整数契约；320是其已派生、校准版本，原始ONNX标注640×640。

## 已实现

`scripts/video/yunet_input_reference.py`提供`preprocess_rgb800x600(rgb: bytes) -> bytes`，仅使用Python标准库。它校验输入类型/1440000B长度，并按RGB的2/1/0字节写B/G/R平面。输出原像素UINT8、scale=1、zero-point=0，无归一化或额外有损量化。

固定5:2缩小的取样起点为`(10*d+3)//4`，右/下权重在偶坐标为3、奇坐标为1，分母4。水平和H0/H1最大1020，输出采用`((4-wy)*H0//4+wy*H1//4+2)//4`。这是INTER_LINEAR的分步取整；一次性加权后舍入在部分输入上会差1。

## 独立来源与定向验证

官方`opencv-python==4.11.0.86` Windows wheel下载到忽略目录，SHA256为`085ad9b77c18853ea66283e98affefe2de8cc4c1f43eda4c100cf9b2721142ec`，与PyPI声明一致。只在隔离路径加载cv2 4.11.0，正常环境的4.14.0未替换，也不把OpenCV设为Video回归前提。

`build/video/yunet320_feasibility/20261018T091912_689589Z/probe.py`构造所有1021²种H0/H1组合，覆盖四个x/y权重相位，共4169764例。实际调用4.11 INTER_LINEAR，优化开/关均一致；对照普通单次舍入时390152例不同。水平权重为1/3，任意0..1020的和均可由合法0..255像素构成，故该检查覆盖本固定比例的完整数值范围，不是其他缩放比例的证明。

另从零、全255、RGB(211,93,17)和三个坐标pattern原图生成六份完整NCHW预期哈希。这些是**800×600源图经过letterbox后的张量**，与上游直接填满320×320张量的canonical full255用例不是同一个测试边界。

`tb/video/test_yunet_input_reference.py`先以缺模块运行获得RED，再以实际实现通过六项测试，包含六份完整张量身份、B/G/R三平面、128..255正值、上下40行、最后源像素贡献及非法类型/长度。

四个隔离突变（单次舍入、RGB未交换、交错布局、补边偏移）均被测试中的断言拒绝。初版突变runpy驱动残留argv，使unittest误解释测试路径；只修正忽略目录驱动并保留`mutations/harness_draft_argv_error.log`，该错误不计作有效拒绝，生产/测试文件未因此改变。

执行入口：

```powershell
python tb/video/test_yunet_input_reference.py
python -m unittest discover -s tb/video -p test_*.py
python scripts/video/gen_config.py --check
```

本批定向6项通过；Python发现63项中62通过、1项Windows条件跳过；现有生成定义核对通过。既有RTL、回归入口和公共配置未改变，因此沿用其原范围的硬件证据，本批不声称重跑全部RTL仿真。新测试由Python discovery发现。

最终独立审查无发现：重建六幅golden并增加13幅图案，两种OpenCV模式共11673600字节差异0；用不同枚举/像素分解独立穷尽4169764相位，同时核对生产函数和OpenCV。15类非法输入、首末点、四项独立突变和资产来源检查通过；父会话核对22项来源/日志及14项审查产物哈希。

小型证据见[yunet320_reference.json](evidence/yunet320_reference.json)，其绑定精确OpenCV来源、RED/突变、参考源码、独立审查及历史Video实现哈希。目标选择已完成，RTL固定比例缩小、NCHW/DMA、公共配置/输入槽迁移、三分支及板测按设计分批实施。
