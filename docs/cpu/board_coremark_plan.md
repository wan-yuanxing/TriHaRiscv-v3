# CPU CoreMark 串口跑分

2026-10-20。使用当前已上板的六级单发射核、HIGH PLL、100MHz、32KiB SRAM和115200/8N1 UART。保留cpu-board-physical-pass-20261020及其自检下载包，不改CPU RTL、管脚或约束。

CoreMark v1.0原始算法和许可文件保持字节不变。平台增加64位周期计时（现有timeh与cycle来自同一计数器），固定点输出精确时间、CoreMark和CoreMark/MHz。原始无浮点报告保留，明确其中整数秒吞吐仅为粗略值；最终精确行才用于性能记录。计时区间内不打印串口。标准2000字节performance数据集，5000次迭代，实物必须达到10秒且CRC全正确才判有效；短仿真不冒充完整实物成绩。

1. 先建立解析失败测试，覆盖CRC错误、短时运行、错误状态和不完整串口数据。
2. 同一冻结源建立5次迭代板级数字PLL仿真和5000次部署固件，记录两者差异及哈希。负例更改build副本预期CRC，必须实际失败。不执行数小时完整RTL跑分。
3. 用部署固件重新完整PDS构建，检查原100MHz全部corner时序及实际bitstream数据库，再封装独立CoreMark包。复用已通过且输入未变的实际PLL模型验收。
4. 实际易失Program/Verify，不写Flash、不恢复Video。下载流程不占串口；用户打开COM12并按KEY0，自行接收约17秒后的结果。未收到实物日志前，板级CoreMark数值保持未验收。

串口设置COM12、115200、8数据位、无校验、1停止位、无流控，文本接收。KEY0重新启动一次测试。保留原生GCC/ModelSim/PDS环境，不用WSL、不启动agent/automation、不合并主工程。
