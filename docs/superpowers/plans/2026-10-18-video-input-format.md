# 检测输入格式组件实施计划

**Goal:** 独立完成BGR/底部零补行及外部量化后C8/128bit打包，用DMA字节内存联测证明布局。

**Architecture:** 两个ready/valid组件以raw和quantized类型边界分开；量化算法仍由NPU侧提供。既有Video分支顺序实施并保留预览板卡配置。

## 1. RED与独立参考

- [ ] 创建`tb/video/tb_detect_input_pad.sv`及`tb_detect_c8_pack.sv`，直接坐标/字节oracle，不模仿寄存状态。先用缺失模块编译并保存Unknown module的RED。
- [ ] 先写`tb/video/test_input_format_reference.py`并运行缺失参考模块的RED，再写`scripts/video/input_format_reference.py`；定义RGB→BGR/零补行和已量化BGR→C8两函数，禁止隐藏量化。

## 2. 两个生产组件

- [ ] `rtl/video/detect_input_pad.sv`实现160×120→160×128，输出BGR及row_last/frame_last/padding；单输出槽，背压/取消/未知payload/额外输入按设计处理。
- [ ] `rtl/video/detect_c8_pack.sv`请求锁存req_zero，按坐标验证已量化输入及元数据；每像素8B，两像素128bit，奇数行尾00ff；最后输出消费后done，错误不能撤销VALID。
- [ ] 定向测试覆盖宽1/3/4/160、零/多补行、零值00/80/37、全256值、受阻保持、四态、错误行标及取消；当前数值不得来自模型假设。

## 3. 联测、综合与完成

- [ ] 新建`tb/video/tb_detect_input_dma.sv`，以测试量化函数连接scaler/pad/pack和既有DMA；完整800×600及缩小尺寸逐字节核验，延迟B响应不得提前成功，padding/stride哨兵保护不变。
- [ ] 新增`run.py --suite input_format`并纳入all，输入哈希覆盖RTL/TB/参考。加入显式`video_input_pad`、`video_c8_pack`综合目标和8ns FDC，无板级管脚目标继续拒绝route/bitstream。
- [ ] 错误BGR交换、硬编码零值、跨行拼半拍、提前done突变必须被拒绝；完整Video回归、组件综合和独立代码审查通过后，更新STATUS、接口、文件树及小型证据。
- [ ] 仅提交明确Video文件，保留本地分支；量化/正式三分支事件/物理板测仍分开报告。
