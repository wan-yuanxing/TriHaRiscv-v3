# 双发射架构图二次审查处理记录

范围：`docs/technical-report/figure/rv32-soc.drawio` 第5～14页，以及CPU正文、Video帧调度说明和CPU附录。图内文字为英文；第1～4页逐字节保持不变。本批未修改RTL、执行PDS或操作板卡。

CPU结构依据 `D:/FPGA/TriHaRiscv-cpu-dualissue-windows/rtl/cpu/`；Video依据主工程v0.6规格及 `docs/interfaces/video.md`。两者不能混用旧Video需求。用户确认保持800×600全屏RAW/BOX/AVATAR，审查提出的左右分屏不采用。

## 审查项处理

| 项目 | 核对结果与处理 | 证据边界 |
|---|---|---|
| FIFO单独弹出B | 组件具有该能力，但当前CPU的A固定为Head0，B须随A接纳；图改为CPU契约 `pop1 ⇒ pop0`。六项环形存储及双队首支持跨包配对。 | `triha_issue.v` 的队首选择、最终消费使能；整核程序增加逐周期断言。未修改FIFO行为。 |
| ALU与流水级 | 组合ALU在ID，结果在ID/E1保存；E1用寄存操作数解析通用分支。总图与ALU附图按实际边界重画。 | 两路实际ALU结果寄存器在非保持沿后与沿前组合值比较。 |
| Branch与Store配对 | 图加入ID早期零比较检查。只有有效无错BEQ/BNE与x0比较、由就绪前递零标志确认不跳转时，才允许B使用LSU/MUL；最终发射仍受相关与恢复屏蔽。未判定分支仅允许B简单ALU推测执行。 | RTL条件核对及整核分支恢复测试支持部分结论；强制内部输入的旧零比较夹具失败，未声称完整证明。 |
| 年长Load与年轻Branch | 描述共享暂停、按年龄取消年轻指令，以及CSR恢复高于普通分支恢复。 | 定向程序覆盖加载保持及完成/恢复交叠，不代表所有异常时序穷尽覆盖。 |
| Video显示模式 | 保持现行全屏三模式；Preview单列为诊断分支。 | 主工程v0.6及用户本轮确认；无Video实现变更。 |
| RAS恢复 | 显示推测指针和调用/返回事件参考指针，正文明确无通用重定向回滚。没有画出不存在的committed RAS或检查点。 | 结构核对。完整回滚或确认后更新仅列为后续方案，未实施。 |
| BTB优先级 | 仍为低字命中优先，BHT判断被选中位置；低字命中不跳转时不重查高字。正文明确可能损失预测机会。 | 结构核对，未改为“首条预测跳转优先”。 |
| 取指吞吐及恢复 | 接口允许上一响应和下一请求同周期接续；正文添加有条件的理想时序及旧响应丢弃事件表。 | 不将接口时序解释成缓存实测持续吞吐；重定向定向测试通过。 |
| 帧身份和慢推理 | RAW等待对应完整结果，安全SOF切换就绪记录，重复扫描活动记录，首像素确认提交，旧DMA/行/像素引用退休后释放。 | 设计与接口契约说明，无新增整机帧调度动态测试。 |
| LSU深度与归属 | 主图只保留功能连接。正文说明2×36位元数据不含PC/rd/槽标签，归属由Pipe状态和共享暂停保持；一个外部pending，ack/accept可交接。 | 队列组件测试通过；握手表根据RTL条件列出，不作为完整事务随机证明。 |
| 指令长度 | 明确RV32IM+Zicsr、32位定长、不支持C；PC连续性按4字节检查。 | 当前CPU前端和译码结构。 |
| 图文组织 | 正文使用第5、6、9、10、12、14、8页；第7、11页保留为支持视图，第13页移至附录。配对规则、边界和握手移至LaTeX表格。 | XML校验、原生PNG视觉检查、字体尺寸核对、LaTeX编译及模板检查。未将PDF渲染成截图。 |

## 定向仿真结果与未解决项

本目录 `rtl-contract-result.json` 保存五项测试的源文件SHA256、完整命令、返回码和结果；`cycle-contract.csv` 是整核分支程序的逐周期消费及ALU观测。原始日志保存在 `logs/`。

- FIFO：20821步，写/读指针回绕2008/1926次。
- 整核分支配对：156周期，9个保持周期，4次恢复，3次陷入；包含错误路径Store、B槽ALU取消和加载保持交叠。
- 乘法早期元数据：41027样本。
- 前端重定向：4次重定向、12个交付包、4个丢弃包。
- LSU FIFO：深度2与4各10001周期，包括空/满及同时出入队。

旧 `tb_issue_zero_pair_pending` 测试失败：指令 `00700463`，期望B发射=1，实际=0；其强制输入未构成当前队列预译码元数据的完整驱动。仅启用RF零元数据仍失败，完整夹具原因尚未确认。两次失败原日志均保留，不能将该测试排除后宣称所有分支配对均已验证。以上五项通过测试是有明确范围的检查，不是新一轮完整ISA、形式证明、时序或板级验收。

## 文件与复现

- 图稿：`docs/technical-report/figure/rv32-soc.drawio`。
- 正文：`latex/chapters/02-system/02-CPU设计.tex`、`05-图像采集与显示链路.tex`；附录：`latex/chapters/06-appendix/B-CPU仿真验证.tex`。
- 输出：`docs/technical-report/latex/技术文档.pdf`；正文宽度157mm，原生矢量图最小文字约8.3pt以上。
- 校验：本目录 `final-audit.json`、`diagram-validation.json`、`pdf-text-font-check.json`。
- 复现脚本、原始运行与修改前备份：`build/cpu-diagram-review2-20261102/`。ModelSim入口为 `run_contracts.py`（再次运行须选新输出目录）；图稿生成、XML校验、PNG/PDF导出分别为 `redraw.py`、`validate_review.py`、`export_pages.py`、`export_pdf.py`。
- 文档构建：`docs/technical-report/latex/scripts/build.ps1`；模板检查：`docs/technical-report/latex/tests/test-template.ps1`。

`final-audit.json`绑定实际交付文件、冻结源码/接口依据和日志哈希，README仅解释范围，不把文档修改当作RTL缺陷修复。
