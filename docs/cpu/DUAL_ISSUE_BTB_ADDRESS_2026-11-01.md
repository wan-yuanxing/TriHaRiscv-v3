# 双发射 v83：BTB 写地址控制隔离

**原100MHz完整后布线已通过独立终态验收。** 六项Slow/Fast setup/hold/MPW
均无违例，原IO/hold/多corner约束保持；完整短RTL CoreMark仍为4.091964/MHz。
本记录的边界为外部时钟CPU+8KiB ROM/32KiB SRAM/MMIO，未上板。

父版为已完整测量但100MHz未通过的v82，保留其角色预译码，不含v81。
95MHz v78仍为通过版本，Git标签及完整归档不变。本轮不增加流水级、停顿、
复位同步周期或时序例外，不改变分支预测算法，不接Cache/DDR或编程板卡。

## 实际问题与改动

v82有38个外部复位→BTB RAM WADDR违例，最差−0.994ns。原两级hold地址缓冲
第一层以metadata_we门控、第二层以reset门控，产生了raw reset/train到地址的
组合路径；实际WE已经在复位/无训练时禁止写入，因此地址上的这些重复条件
没有必要参与有效写入地址的计算。

v83只改 `triha_btb.v`：第一地址LUT改用 `write_row[7:6]==block/2`，
第二地址LUT改用 `write_row[5]!=block%2` 的反条件。任一真实块写入都要求这两个
地址条件选中该块，因此有效写入时低5位地址不变。其他块/无写入时的WADDR
允许变化，WE为0/X/Z时原生RAM模型不会写入。Z地址位仍经过AND规范为X，
与父版一致。所有metadata/tag/target写许可、读地址和valid复位完全保留。

保留两个显式GTP_LUT6和syn_keep节点，原hold预算不变。必须通过实际映射确认
80个两级地址边界仍存在，不能依赖RTL属性或工具成功标记推断hold通过。

## 功能门槛

- 抽取真实两级地址LUT链，643072项八块交叉检查，包含全部地址、控制X/Z及
  未知地址位；在WE确定为1时与父版和原生AND地址语义一致。
- 旧链的独立控制污染检查按预期失败；新链不随reset/train/invalidate变化。
  真正损坏有效写入地址的负例仍被检出。初版测试把Z与原生AND输出X混淆，
  已以父版实测修正oracle，失败日志保留。
- 完整BTB/valid/WE/别名与四态159168项对照、现有indexed BTB及负例通过。
- 单/双ordered、IRQ/mret和真实E1恢复通过。
- 新候选22源文件字节补丁/manifest已独立重建，CPU中仅BTB相对v82变化；
  默认RTL、主工程与板卡未修改。

完整SRAM CoreMark已通过：1221907cycles/1448448 observed WB，observed IPC
1.1853995435，短测4.0919644457/MHz；CRC e9f5/e714/1fd7/8e3a。完整WB/store、
ROM/SRAM和profile均与保留v78相同，122输出核验。这是RTL短测，非板测或官方分数。
8组功能/native运行的361个输出、输入与工具哈希已逐一核验。
旧v82实际网表已由新检查器检出624个RAM地址中的reset/train依赖，80个hold
边界仍存在。这是新检查器的父版HOLD对照，不是新的物理结果。

固定物理配置的predictor invalidate由frontend绑定常量0，综合会移除该端口。
检查器显式核对冻结frontend的这个绑定；没有把一个缺失的变量端口当安全边界。
完整BTB组件测试另行覆盖动态invalidate的四态语义。

## 原生映射与物理准入

compile/synthesize/dev_map通过，CPU-only **9845 LUT/5001 FF/752已含RAM-LUT/
4 APM/0 DRM**，不计SRAM/MMIO夹具。对v82为−32 LUT/−2 FF，未新增RTL状态。
实际624个RAM WADDR的完整支持锥无reset/train依赖、无未知节点。

ADS将相邻块相同的第一层AND共享，保留奇数块的具名第一层节点，因此旧逐块
名称检查是HOLD40/80。逐实际边检查证实80个地址输出全部仍经过第一层和第二层，
仅共享第一层；检查器绑定冻结源码中相同的半块地址条件，不允许任意跨块借用。
真实折叠一级的负例只剩79个边界，HOLD；重新接入真实复位的负例也HOLD。
原生rst_i逻辑名消失时，检查器追踪实际nt_rst_ni与顶层rst_ni，未忽略复位边界。

原256个目标WE的完整块内tag/valid支持、624个RAM地址绑定分别通过；原检查器
整体HOLD记录保留，由新的80输出共享结构检查组成独立准入记录。分支预比较、
完整地址结果、角色FF及16个SRAM CE门槛均通过。

已启动 `build/cpu/dual-btb-address-io-physical-v83` 唯一一次完整新PNR，
原10ns/IO/hold/multicorner、seed1、PNR600秒/外层900秒，私有TEMP与独立工作目录。
## 终态：原100MHz通过

实际周期10.0000ns、100.0000MHz，五阶段全部成功，PDS原生退出0、验收器退出0。
主详细布线135次到0；完整PNR阶段3分32秒。30个冻结输入、362个输出、原执行
工具快照、实际网表和最终报告哈希全部核验，source unchanged。

| 检查 | Slow/ns | Fast/ns |
|---|---:|---:|
| Setup | **+0.307** | +2.753 |
| Hold | +0.114 | **+0.103** |
| 最小脉宽 | +3.655 | +4.202 |

所有六项TNS/违例端点数均为0，Design Summary为All Constraints Met。
performance slack与最差setup一致，为+0.307ns；Recovery/Removal也无违例。
没有用报告中的估算最高频率代替100MHz实际验收，没有放宽任何IO/hold预算。

最差setup已转为FIFO头部→B路E1操作数寄存器，余量+0.307ns。
对v82同10ns的−0.994ns提高1.301ns，但属于新网表/新布局整体结果，不能把全部
差值归于一个局部逻辑变化。95MHz原归档继续保留，v81/v82失败记录不覆盖。

实际route综合网表与native文件哈希不同，因此重新检查了全部地址、角色、
分支比较、完整地址结果、BTB WE/地址绑定及SRAM CE，未直接复用native的PASS。
实际CPU-only仍为9845 LUT/5001 FF/752已含RAM-LUT/4 APM/0 DRM。

原运行记录保持 `TIMING_PASS_AREA_PENDING`，其中不填写夹具面积作为CPU面积。
独立终态审计已从本轮u_core综合层级补齐CPU-only资源，并结合功能/轨迹和时序
形成完整验收证据；不改写原始result.json。

源码继续由完整22源文件补丁和manifest重建，默认生产RTL及集成主工程不变。
本轮停止继续扫描频率或重复PNR；后续板级PLL/引脚/固件频率/UART及长跑CoreMark
属于部署验收，本次未编程板卡，4.091964/MHz不是新增板测或官方分数。

证据：[dualissue_btb_address_control.json](../verification/cpu/dualissue_btb_address_control.json)。
报告：[triha_minimal_soc.rtr](../../build/cpu/dual-btb-address-io-physical-v83/report_timing/triha_minimal_soc.rtr)。

重建入口（目标必须为新目录，禁止覆盖通过运行）：

```powershell
python scripts/cpu/prepare_dual_candidate.py build/cpu/NEW_V83_SOURCE --manifest docs/verification/cpu/dualissue_btb_address_control_sources.json
```

通过物理包的 `src/`、固件、原约束与build.tcl已经冻结。归档409个文件、
19882660bytes，逐文件解压SHA验证；ZIP SHA256为
`7ddfa9006cab6aa6641103d485586f47a983e4b0ef04b5c9c14c87235e09a54b`。
完整冻结物理运行、22候选源、重放补丁、映射审计与基准镜像已归档；完整功能
仿真库和WB/store仍保留在原build目录，并由结果哈希绑定，不称为已复制进ZIP。
Git标签为 `cpu-dual-sram-100mhz-20261101`，95MHz原标签继续保留。
见[100MHz保留记录](../verification/cpu/dualissue_100mhz_preserved.json)；不应在旧
运行目录再次执行PDS。
