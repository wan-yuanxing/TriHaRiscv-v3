# Video链路关键仿真交付计划

**目标：** 把完整帧、三槽引用、DDR背压和端到端失败隔离组织成可复验结果及原生波形。

**方案：** 复用既有生产RTL和自校验测试台；现有四套件运行负责覆盖矩阵，少量ModelSim短场景负责WLF及截图。已授权在主工程完成验证和文档工作，不新建工作树、不提交其他任务修改。

- [x] 运行`capture_rearm`20场景、`display_slots`13场景、`shared_video`24场景和`video_pipeline`三种正常/错误输入，核对实际退出和PASS。
- [x] 在`build/video-key-simulations-20261030/`冻结显式源清单，使用ModelSim运行采集、槽引用、背压和采显联合四个短场景，保存WLF/VCD和工具哈希。
- [x] 对公开接口轨迹独立检查完成晚于写响应、release ACK之前不FREE、B/R背压不退休、实际显示帧身份；提取准确时间窗口。
- [x] 保存四张原生最大化ModelSim窗口截图，无鼠标指针、无裁剪、无重绘，截图完成关闭查看器。
- [x] 在`docs/technical-report/latex/chapters/06-appendix.tex`重组Video小节，正文只写实际方法、统计和边界；CPU与NPU章节字节保持。
- [x] 用现有build.ps1编译PDF，只检查日志；把小型摘要和支撑包放`docs/verification/video/`，核对文件哈希并更新Video台账。

CPU控制`cpu_record`作为历史支撑，先核对真实原始日志和输入绑定；不将本批native C控制器写成CPU执行，不重复长CPU仿真或任何PDS/板卡流程。
