# DDR CoreMark 板测对照

2026-10-22，`cpu/windows-baseline`。原始结果、串口、下载记录、实际时序报告和
复核日志的 SHA256 绑定见 [JSON 索引](id_cache_board_coremark_comparison.json)。

已取得带 Cache 两次、共享区旁路一次有效板测；**DDR 启动可靠性尚未解决**。
这些是实际板卡结果，非 RTL 估算或官方提交。

| 5000 次实际板测 | 私有 DDR，I/D Cache | 共享 DDR，I/D 旁路 |
|---|---:|---:|
| 代码/数据地址 | 0x80000000 | 0x82000000 |
| 完整 64 位 cycles | 5925962390 | 48866603284 |
| 秒，按标称 100MHz | 59.25962390 | 488.66603284 |
| CoreMark | 84.374480817 | 10.231936873 |
| CoreMark/MHz | 0.843744808 | 0.102319369 |
| CPU-only LUT | 6558 | 6558 |
| CoreMark/CPU LUT | 0.012865886 | 0.001560222 |
| CPU+Cache/transport LUT | 7077 | 7077 |
| CoreMark/(CPU+Cache/transport LUT) | 0.011922351 | 0.001445801 |

缓存版另一次为 5925962602cycles、84.374477799CoreMark。全部有效运行均为
5000 次、2000 字节，标准 CRC e9f5/e714/1fd7/8e3a 及至少 10 秒检查通过。
以首个缓存结果计算，两种地址属性下吞吐比 8.246188563、周期减少 87.873185383%。
这不是同地址、编译期开关 Cache 的严格对照：共享版重新链接，地址和内存属性不同，
可加载载荷字节也不同。两者使用相同算法源码、GCC15.2、-O2、无 LTO，Cache 硬件均存在。

六级单发射 RV32IM/CSR、BTB512/BHT512/RAS4、GShare 关闭。I/D 各 16KiB，
两路、32B 行；D 写直达，原生 DDR 桥仍等待实际写入和读回校验。该边界延迟不能
用先前 SRAM 短 RTL 分数直接替代。没有 instret CSR，物理 IPC 未知。
原始上游 Total ticks 仅显示低 32 位；精确分数按 CPU_COREMARK_TIME 的高低位复算。

## 实际时序与资源

两个 Cache 硬件保留版均完成实际 100MHz 后布线准入：Slow/Fast setup
+0.213/+3.617ns，hold +0.136/+0.082ns，脉宽 +3.655/+4.202ns。
全部时钟域恢复/撤除、Gray max-delay/skew 亦通过，原约束未放宽。
复核重新检查冻结源、工具、证据、全部输出哈希和真实阶段标志；不是综合频率估算。

CPU-only 6558LUT/3562FF/688RAM-LUT（已含在总 LUT）/0DRM/4APM。
Cache/transport 另列 519LUT/763FF/11DRM36K 等效；CDC、DDR、板级逻辑不计入 CPU。

原生工具从两个实际路由数据库关闭 DRM 数据和时间/厂商元数据后生成的位流
SHA256 均为 `5ace471fc000aaf2d3220cf93d75200c27c157a1e97f094577f8b4efda8fe35b`。
这证明该排除范围内的配置相同，不能扩展为全部 RAM 初始内容相同。

## 启动失败与当前板卡

所有失败保留，没有从失败捕获中抽取分数：

- 编译期 Cache=0 镜像虽通过 100MHz，实际下载校验后报 DDR init 失败，无分数。
- 共享旁路第一次进入 CoreMark 后出现另一次启动并报 init 失败；随后仅 KEY0 复位也失败。
- 用户确认在下载校验期间保持 KEY0、完成后松开的一次共享运行成功，只有一个完整启动 epoch。
- 恢复缓存镜像时也使用了保持复位的流程，但最新自动串口仍报 init 失败。
  因此该操作不是已证实的通用修复，不能把故障归因于 Cache、布局或 JTAG 校验。

当前已下载并校验 `cpu_ddr_coremark_on_e5503c690208`，Program/Verify 原生返回 0。
下载成功与 DDR 本次启动成功分开记录；最新自动启动失败，内部 PLL/训练/故障码原因未知。
用户要求停止长按配合，保留已下载镜像，自行用串口助手短按复位查看。
自动采集已退出，COM12 已释放，不再自动下载或打开串口。

串口为 COM12、115200、8N1、无流控。松开 KEY0 后，正常缓存跑分约一分钟，
应看到 PAYLOAD_PASS、有效 CRC、精确分数和 CPU_COREMARK_BOARD_PASS。
若出现 CPU_DDR_COREMARK_FAIL init，表示本次没有产生有效分数。

未写 Flash、未改主工程、未合并或推送。原 SRAM 发布包十项文件重新校验未变。
61 项 CPU 与 45 项 SoC Python 检查、配置/来源校验及既有 PDS/STA 解析检查通过。
本报告不承诺无条件启动稳定、完整 DDR 地址/电气验收或多主 SoC 集成完成。
