# RX像素分布诊断实施计划

**Goal:** 用接收端坐标/颜色观测区分输入内容与预览映射异常。

**Architecture:** 独立RX镜像共享现有初始化/下降沿几何监测/稳定snapshot，增加完整好帧统计和type8/9；不更改preview及其发布入口。

**Execution:** 当前会话按用户既有实施/板测授权顺序执行；已有Video分支中仅新增诊断文件，技术报告独立保留。设计见同日rx-image-probe-design。

- [ ] 编写 `tb/video/tb_video_rx_image_probe.sv`，独立循环计算CRC和亮区边界，检查8×6全彩、合法黑帧、局部区域、坏帧、连续帧及中途复位。先用接口替身验证断言确实失败。
- [ ] 实现 `rtl/video/video_rx_image_probe.sv`，完成frame_start→good EOF原子发布，运行相同TB通过。
- [ ] 新增专用RX top/JSON及构建入口；保持原RX所有管脚/时钟/CDC约束，冻结原始文件并记录哈希。UART按发送完成循环模式/几何统计包。
- [ ] 新增专用读取器及包解码测试，保留未知包、错XOR/版本/保留位拒绝和同序号配对规则。
- [ ] 实际综合、布局布线和内部时序/约束检查；通过后打包、识别PG2L100H/00602899并执行易失Program/Verify，不写Flash。保持四角源不变，采集连续RX统计及必要KEY0记录。
- [ ] 依据输入四象限/边界确定下一诊断点，保存原始UART及来源哈希，更新STATUS/验证摘要。当前preview图像验收维持false，直到实际完整画面恢复验证通过。
