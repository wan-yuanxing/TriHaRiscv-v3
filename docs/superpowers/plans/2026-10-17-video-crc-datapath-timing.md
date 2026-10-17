# Video CRC数据通路时序实施计划

**Goal:** 在现有125MHz/6ns/5秒约束下，缩短CRC读回数据与控制串联路径，继续完成启动黑帧修复上板验收。

**Architecture:** 保持CRC FSM和周期，用RECEIVE中的地址候选及BYTES移位scratch减少后续组合工作；请求payload装载不再由descriptor_ok控制。范围及无所有权payload差异见同日设计。

**Execution:** 当前会话依次执行，复用现有Video分支；独立代理只做代码复核。技术报告修改保持独立。

- [x] 保存第三轮物理RED与当前25套件数字基线；读取保留报告并完成独立架构复核。
- [ ] 在 `build/video/preview_timing_analysis/crc_datapath/` 保存当前CRC源码，基于现有15场景配对TB建立逐周期基线：所有public控制/诊断相同、AR payload按VALID限定，BYTES的next_crc相同；共同控制状态/计数/CRC/fault相同，描述符函数边界/X/Z相同。
- [ ] 仅在隔离候选修改上述三个数据通路点；运行配对及更广的行尺寸/背压/错误/复位场景，验证错误候选地址与错误移位突变被拒绝。保存工具、输入哈希、退出码及日志。
- [ ] 独立复核候选及等价边界；通过后仅应用 `rtl/video/video_frame_crc_reader.sv`，实际源码再复跑配对。保留canonical CRC自校验测试及既有故障/排空检查。
- [ ] `python scripts/video/run.py --suite preview_crc` 与 `--suite preview_board` 通过后运行 `--suite all`；同时启动 `python scripts/video/build_pds.py --target video_preview_board --stage bitstream`，冻结输入。
- [ ] 六布局新构建通过、全部八角及实际束路径审计通过后才打包/Program/Verify。持续串口记录先开启，再核对首帧、60秒扫描与实体KEY0真实桌面恢复。
- [ ] 更新STATUS/接口/机器证据，只提交本批Video文件；保持未验项开放，不push、不写Flash。
