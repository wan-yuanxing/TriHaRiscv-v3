# 检测输入5×5缩小验证

依据v0.6第6.3、8.2节，本批在用户确认“NPU清单尚未提供，先推进独立Video组件”后执行。设计/计划为71c3e68，算术流水调整另见`docs/superpowers/specs/2026-10-18-video-detect-scale-pipeline-note.md`。

本文的27套件/128输入及“当前”哈希是09fd86d验收时的冻结记录。后续格式组件扩展回归/构建入口后，全树状态见[input_format.md](input_format.md)，不能用旧入口哈希批准新的工作树；缩小RTL本身未因此修改。

## 功能边界

`detect_downscale`把整幅800×600 RGB888按不重叠5×5分组，每通道`floor((sum+12)/25)`产生160×120 RGB888，输出57,600字节。输入均参与累计，包含四角及末行末列。输出仍为RGB；这不是最终BGR/INT8/C8张量，不含底部8行、DMA、SoC槽状态或INPUT_READY/CAPTURE_DONE。

组件使用单时钟ready/valid、row_last、clear和低有效异步reset。首次源行覆盖块列RAM，后续四行只读已写条目；RAM及算术数据寄存器不复位，状态/valid确保新帧不会使用旧值。未知RGB、错误/未知row_last或超出完整帧的输入锁存fault；公开输出保持到消费，fault不撤销VALID。clear/reset按协调取消语义丢弃pending状态。

最终算术阶段为累计并舍入寄存→乘5243的26bit乘积寄存→取[24:17]输出。全部可达sum0..6375的商均精确，独立TB直接求25坐标之和作oracle，不使用该乘数。两拍pending预留输出槽，期间暂停输入；未来板级入口必须以FIFO吸收背压，当前不改变HDMI接收硬件。

## 测试与综合

- 初始缺模块RED：`detect_scale_red/20261018T074334_775769Z`。其TB哈希属于初版fixture；后续修正末帧背压驱动，并增加末输出等待以容纳流水延迟，数学oracle未改。
- 当前定向回归：`regression/20261018T075320_675450Z`，42个输入哈希；最小/多块/完整800×600五类图像，6376个累加总和穷举，输入气泡/长背压、错误/四态payload、clear/reset和帧末输出保持通过。
- Python整数参考4项测试通过，覆盖所有累加总和、完整坐标映射、25个源位置贡献及非法输入。
- 四个错误版本在`detect_scale_mutations/20261018T075422_207220Z`均被拒绝：舍入12→11、红蓝交换、遗漏末行、fault撤销VALID。独立整数检查验证n0..6387的reciprocal恒等式。
- 组件入口对route和bitstream请求均在参数检查时拒绝，记录为`detect_scale_component_guard/20261018T081219_943552Z`，没有启动PDS或生成可下载产物。
- 组件综合：`pds/20261018T075320_673987Z`，191 LUT、88普通寄存器、1 DRM、3 APM；APM内的流水寄存器不计入普通FF数。8ns约束下综合估计setup+2.370ns、hold+0.758ns，269个setup端点无失败，估计177.6199MHz。通用构建结果的resources字典未解析APM，实际3 APM来自绑定的SNR/netlist，不能遗漏到资源预算。

首版直接组合除25的综合估计WNS−3.157ns（316 LUT/85 FF/1 DRM）已保留为失败性能对照。其原完整回归`20261018T074723_041506Z`被主动停止、标记superseded_incomplete，不算全套通过。最终流水候选的完整回归`regression/20261018T075444_074239Z`已通过27套件、128个当前输入哈希；实际95个仿真PASS日志已检查。独立审查`independent_detect_scale_review/20261018T075404Z/review_result.json`无未解决发现，另以15帧独立随机图、12个非法尺寸、1350次异常注入和4次流水取消验证通过，综合网表核实3个APM的常数、宽度、使能及输出切片。小型证据与来源哈希见[detect_scale.json](evidence/detect_scale.json)。

综合估计不等于布局布线时序、外部AC或板测；本批未运行新JTAG/UART，板卡仍为已验收的预览镜像。模型清单/输入尺度、舍入饱和及预处理版本由NPU侧提供后，再接量化、补边、C8布局及三分支写完成协议。
