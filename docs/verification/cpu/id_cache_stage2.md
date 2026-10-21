# I/D Cache 本地 SoC 接入核验

2026-10-21，`cpu/windows-baseline`，父节点 `10b1bf5`。这是功能和原生映射节点；**缓存版实际100MHz、真实DDR/CDC、共享fabric和板测尚未准入**。原部署包 `cpu_coremark_6ff82025b53d` 保留，未打开COM12、编程、写Flash、合并或推送。全部证据绑定见同目录 `id_cache_stage2.json`。

## 实现

- 新增可选 `triha_cached_soc`，复用原核和本地ROM/SRAM/UART/System。原最小SoC及板级目标不变。
- `triha_cpu_memory_router`在接纳时登记I/D各自的响应拥有者和未完成计数。目标变化等待旧响应排空；返还数据按拥有者选择，避免旧RAM/Cache输出串入新响应。维护请求不依赖地址，零地址也送到D Cache；本地执行期间FENCE.I仍作用于I Cache。
- `0x2002000c`只读状态，bit0就绪、bit1保持故障。DDR未就绪只阻塞新DDR请求；故障后的新DDR访问返回访问异常。本地状态/代码可继续运行，已接纳请求及AXI响应保持连接。无法完成的致命在途故障仍需要CPU/Cache/fabric/DDR协调复位，不能靠局部复位丢弃事务。
- 配置和RTL/C头一起生成；预检拒绝状态偏移、时钟域或协调复位契约变化。接口上的DDR就绪/故障及AXI信号须已处于CPU时钟域。

## 实际验证

| 验证 | 结果与范围 |
|---|---|
| 路由独立测试，缓存开启/旁路 | PASS；本地不走DDR，未就绪背压，I/D跨目标等待、标签保持、共享区旁路、部分写、I/D争用、AW后撤销就绪仍排空W/B、在途读取遇故障仍完成、故障保持及协调复位 |
| 真实CPU程序，缓存开启/旁路 | PASS；同一ROM/SRAM加载镜像，ROM→SRAM、初始化前本地访存、UART两字节及慢写等待、私有/共享DDR数据与代码、修改代码后FENCE.I、只读状态写错误、下级读取错误及平台故障后的访问错误，三次异常后MRET并继续本地执行 |
| 数据损坏负例 | 路由及真实CPU均实际被拒绝，宿主退出1；并非只凭模拟器退出0接受结果 |
| 看门狗负例 | 实际第9周期拒绝，宿主退出1 |
| Python回归 | Cache策略6项、系统配置6项、证据核验4项、原SoC44项通过 |
| 独立证据复核 | 重新读取冻结输入、当前源码、工具、所有输出、原生阶段成功标记、实际单发射/预测器/Cache参数和层次资源，PASS |

真实CPU测试包含维护、故意错误及UART等待，周期仅用于诊断，**不是CoreMark性能比较**。开启与旁路ELF仅非加载 `.strtab` 的GCC临时汇编对象名不同；所有其余节及实际ROM/SRAM加载字节一致。此前五次CoreMark数字模型测量保留在stage1；本轮没有重新测量或更新性能结论。

首轮RED分别因路由和系统封装尚未实现而失败，原始日志保留。之后发现的测试台问题也保留：共享指令ID3误计到D计数器、路由冻结目录漏带本地生成器所需的链接脚本，均已修正并重新运行。没有覆盖旧结果。

## 原生资源

PDS2022.2-SP6.4的实际compile/synthesize/dev_map成功，无锁存器。以下为同一次综合层次资源，排除串行观测夹具；分布式RAM LUT是总LUT的子集。

| 范围 | LUT | FF | RAM LUT（已含） | DRM36K等效 | APM |
|---|---:|---:|---:|---:|---:|
| CPU核 | 6434 | 3531 | 688 | 0 | 4 |
| I/D Cache及AXI传输 | 519 | 763 | 0 | 11 | 0 |
| ROM/SRAM/UART/System | 183 | 121 | 0 | 16.5 | 0 |
| 新路由/状态逻辑 | 44 | 16 | 0 | 0 | 0 |
| 合计 | **7180** | **4431** | **688** | **27.5** | **4** |

实际device_map也成功；其顶层7313LUT/4840FF包含夹具，不能充当CPU资源。本次边界/综合上下文不同，不将6434LUT与原板测CPU5933LUT直接计算优化收益。串行夹具只用于保留总线位并测资源，不能用于时序、DDR或板级验收。

## 复现

```powershell
python scripts/cpu/test_cache_soc_config.py
python scripts/cpu/test_cache_soc_review.py
python scripts/cpu/gen_cache_soc.py --check
python scripts/cpu/run_cache_soc.py --test router
python scripts/cpu/run_cache_soc.py --test router --bypass-caches
python scripts/cpu/run_cache_soc.py --test runtime
python scripts/cpu/run_cache_soc.py --test runtime --bypass-caches
python scripts/cpu/run_cache_soc.py --test router --fault data
python scripts/cpu/run_cache_soc.py --test runtime --fault data
python scripts/cpu/run_cache_soc.py --test runtime --fault watchdog
pwsh -NoProfile -File scripts/cpu/run_cache_pds.ps1 -Target cpu-soc -FirmwareRunDirectory <本轮缓存开启runtime目录>
```

最后三项故障仿真应退出1。结果目录每次独立，`result.json`记录真实命令/退出码、冻结输入和输出哈希。证据复核入口 `scripts/cpu/review_cache_soc.py`接收四个正例、原生映射和三个负例目录；本轮命令及目录由JSON索引完整定位。

## 下一道准入

主工程在只读检查时为 `8635a91626d87eb7573beba5ea805a5f6043bb8a`。当前异步FIFO与CPU工作树字节相同，但DDR桥已从工作树的 `f898c468…` 变为 `c3d3f04b…`；精确SHA256和接口文档绑定在JSON中。检查没有修改主工程，也没有把旧桥当作最新桥接入。

接下来应先冻结最新DDR版本，复用现有异步FIFO实现CPU100MHz→DDR125MHz的完整AXI五通道边界，验证背压、协调复位和在途失锁；再接统一共享fabric，核对跨主端写可见性。实际物理验收须包括真实系统/CDC边界，维持原100MHz、IO/hold及多corner约束，独立复核Slow/Fast setup/hold/MPW及performance slack。当前没有缓存版后布线报告，不能宣称已达100MHz或可以部署。
