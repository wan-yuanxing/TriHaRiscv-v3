# CPU片上系统100MHz验收（2026-10-19）

**PASS：实际CPU＋片上ROM/SRAM＋本地总线＋UART系统的100MHz后布线STA通过。**原裸核224总线端口的失败记录保留；未做板测、PLL/正式管脚绑定或下载，没有生成bitstream。

配置：PG2L100H / FBG676 / −6，PDS2022.2-SP6.4原生ADS，`triha_minimal_soc`，六级主流水、默认单发射顺序执行、RV32IM/CSR。8KiB启动窗口0x0，32KiB SRAM 0x10000，CPU宽总线内部连接，13个实际顶层端口。源码和软件维护在同一主仓库的CPU工作树，主工程未自动合并。

## 实际时序

| 检查 | Slow / ns | Fast / ns |
|---|---:|---:|
| Setup | +0.232 | +2.833 |
| Hold | +0.128 | +0.104 |
| 最小脉宽 | +3.655 | +4.202 |

六项均零违例，performance slack=+0.232ns，与最差setup一致。10ns时钟、IO max2/min0.5ns、setup/hold uncertainty 0.1/0.05ns，未添加false path或multicycle。使用compact完整CPU时钟区和现有输出寄存器打包、placement seed1；无额外PC复制体，未选失败的frontend/fanout/seed2对照。最差路径现为ROM原生块RAM输出到CPU执行结果寄存器，余量为正。PDS实际返回0、宿主0；冻结输入、真实输出、初始化镜像、工具哈希和五阶段成功标记均独立复读核验。

## 资源（CPU核与系统额外部分分开）

| 原生综合层次 | LUT | FF | 分布式RAM | DRM36K等效 | APM |
|---|---:|---:|---:|---:|---:|
| CPU u_core | 6080 | 5205 | 32 | 0 | 4 |
| ROM/SRAM/总线/UART | 136 | 88 | 0 | 16.5 | 0 |

完整系统dev_map为6216 LUT、5292 CLM FF、16.5 DRM、4 APM，另有13个IO及10个OREGIS。综合层次FF相加为5293，dev_map再优化1个，两个阶段不混算。IO FF另列；这些资源字段不是完整架构状态位计数，系统面积不冒充CPU-only。

## 功能与性能

实际ModelSim从ROM跳到SRAM运行本机GCC固件。415项协议检查、全部7种maintenance组合伴非法写、字节/高低lane/边界、连续事务、I/D冲突、复位和独立UART线级接收通过。坏读数据负例被拒绝；整核未映射读、ROM写、未映射取指及SRAM边界四类异常的cause/mtval/退出码经真实UART检查。工具配置漂移、非法ELF、地址窗口重叠拒绝测试通过。

CoreMark1.0，GCC15.2.0，RV32IM_Zicsr/ILP32，−O3、无LTO，2000字节、5次迭代：1685831周期、1467843次WB完成观察，观察IPC **0.870694**，短测估算 **2.965896 CoreMark/MHz**。CRC e9f5/e714/1fd7/8e3a正确。相比旧128KiB测试TCM周期多0.212333%，地址/启动/传输环境不同，不把差异全部归因于RAM。保留不足10秒的原始警告，这是RTL短测而非官方分数或板测；WB事件不等于完整架构minstret证明。

NPC改写完成逐拍全状态、三种背压seed×单/双模式整核/按序WB/store/异常及IRQ/mret对照；新增确认return与预测call重叠优先级、完整32位及X/Z标签oracle。无新增预测级/额外load周期。原始28文件和11项派生清单哈希已核对。原生SRAM另用实际Pango模型执行综合网表12296项检查，真实损坏被拒绝；该组件与系统使用相同RAM RTL和镜像，不是整核后布线仿真。

最后收敛来自共享完整tag比较、RAS提前按条目选择写地址，以及已命中SRAM时把本地写有效性与通用MMIO错误译码分开；均保持程序周期。历史失败、未选物理对照及每步源版本保留。

## 复现和后续范围

```powershell
python scripts/soc/gen_config.py --check
python scripts/soc/test_tools.py
python scripts/soc/run.py --test memory
python scripts/soc/run.py --test runtime
python scripts/soc/run.py --test coremark
pwsh -NoProfile -File scripts/soc/run_route.ps1 -FirmwareRunDirectory build/soc/coremark-20261019T125836820370Z -PhysicalProfile compact -PlacementSeed 1
```

实际冻结运行：[result.json](../../../build/soc/route-20261019T1301015447457Z/result.json)、[最终时序报告](../../../build/soc/route-20261019T1301015447457Z/report_timing/triha_minimal_soc.rtr)、[PDS日志](../../../build/soc/route-20261019T1301015447457Z/pds-route.stdout.log)。

小型索引：[验收绑定](minimal_soc_acceptance.json)、[独立时序复核](minimal_soc_local_decode_route.json)、[系统功能/性能](minimal_soc_local_decode_validation.json)、[CPU功能回归](minimal_soc_ras_entry_validation.json)。地址/协议见[接口契约](../../interfaces/cpu_local_bus.md)。

下一阶段是正式板级100MHz时钟/复位/管脚绑定和UART/存储板测，再接入DDR/Video/NPU；当前未实现窗口仍错误完成，尚无UART RX动态装载器。更高频率、完整ISA/PMP/Cache等也没有由本次STA代替验收。
