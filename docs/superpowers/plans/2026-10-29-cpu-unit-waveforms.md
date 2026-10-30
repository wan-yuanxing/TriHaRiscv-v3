# CPU 分层功能仿真与原生波形

**目标：** 保留 B.1 ISA 逐项结果，按 B.2 单元级、B.3 模块级、B.4 系统级补齐功能验证。本批交付乘法器、除法器和 CSR 三组单元测试及 ModelSim 截图。

**执行方式：** 当前会话内逐项执行，复用既有 CPU 工作树，不创建新工作树，不修改生产 RTL。使用 Windows PowerShell、ModelSim 2020.4；截图从实际 WLF 数据集获取。

## 第一批：单元级

- [x] 复用 tb_multiplier_payload.v 的独立整数运算 oracle，覆盖四种乘法、气泡与 hold。
- [x] 复用 tb_divider_arithmetic.v，显式选择 triha_divider，覆盖四种除法/余数、除零、溢出、缓存复用、重启与复位。
- [x] 新增 tb_csr_functional.v，只驱动公开端口，覆盖六种 CSR 指令、EPC 对齐、非法指令/ECALL 异常、MRET。
- [x] capture_unit_waveforms.ps1 三组正例和三个 Broken 负例；原始日志、WLF、VCD、输入输出 SHA-256 均落入 build/cpu/ 独立目录。
- [x] 打开正例 WLF，使用 ModelSim 原生 Wave 窗口；全屏、信号名简洁、十六进制数据和 ns 时间轴，截图不带鼠标指针。
- [x] 将原图保存到 docs/technical-report/figure/，在 B.2 按测试场景、关键波形、结果撰写；B.1 内容保持。
- [x] 以 docs/technical-report/latex/scripts/build.ps1 编译，检查日志；不渲染或预览 PDF。
- [x] 保存 docs/verification/cpu/unit_waveforms_2026-10-29.json，绑定测试日志、原始波形、截图、RTL/TB 和文档哈希。

原生命令：

    pwsh -NoProfile -File scripts/cpu/capture_unit_waveforms.ps1 -Test mularith
    pwsh -NoProfile -File scripts/cpu/capture_unit_waveforms.ps1 -Test divarith
    pwsh -NoProfile -File scripts/cpu/capture_unit_waveforms.ps1 -Test csr

正例须返回 0 并出现对应 PASS 标志；加 -Broken 的三个负例须返回 1，并由相应自检报告实际数值错误。

## 第二批：ALU 与寄存器堆

- [x] 新增 ALU 独立整数参考，执行 17804 次结果检查和 384 组移位扫描。
- [x] 复用并补强寄存器堆测试，使用实际安装的 Pango 原语模型；完成 2476 次读值检查、1006 次有效写入、2 次复位和 6 次全地址异步扫描。
- [x] 两组正例通过，两组错误注入负例被检出；不修改生产 RTL。
- [x] 保存两张原生 ModelSim 全窗口截图，保持无鼠标光标，不重绘。
- [x] B.2 补入 ALU、寄存器堆说明，编译并校验结果，保存增量支撑包。

## 第三批：前端与发射/旁路

- [x] 复用 tb_frontend_redirect.v 的端口激励，检查注册重定向、晚响应丢弃、背压及连续重定向；使用未注册重定向的旧前端作为预期失败负例。
- [x] 新增 tb_issue_flow.v，用完整核的公开取指/数据端口运行16条固定指令；只读观察实际发射/写回，独立检查操作数与按序结果。插入数据请求接纳等待和晚加载返回，覆盖ALU、load、窄乘法、高位乘法及相同目的寄存器的旁路优先级。
- [x] 通过下级数据端口注入错误加载值作为负例，不强制DUT内部状态。两组正例返回0、负例返回1，保存原始WLF/VCD、命令和输入输出哈希。
- [x] 使用原生ModelSim全窗口截图，分别展示前端重定向与实际流水相关等待；补入B.3，集中登记支撑材料。
- [x] 运行latex/scripts/build.ps1，检查日志和支撑包哈希。本批不进行PDS、板测或生产RTL修改。

## 后续批次

- [x] B.3 补齐 LSU 与 I/D Cache 的命中、填充、写回和维护交互；四组正例及四组错误注入负例均已完成，原生波形截图已保存到技术文档图目录。
- [x] B.4第一批：当前冻结核运行Cache开启/关闭的最小系统固件，记录启动、总线事务、三次访问异常及MRET、平台故障隔离；修正旧路由测试台的写穿预期和刷新超时，正例通过，数据错误负例被检出。采集原生故障与异常返回截图。
- [x] B.4后续：外部中断进入与返回的整核波形。使用512项直接映射BTB、512项BHT、4项RAS、GShare关闭的单发射配置，检查CSR保存和MRET返回；正例与返回数据错误负例均有实际日志。功能仿真与物理时序、板测分别登记。

每批只保留说明关键行为的短波形窗口，完整运行结果由自检日志与原始数据支撑。
