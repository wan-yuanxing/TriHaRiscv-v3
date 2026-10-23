# 双发射配对优化性能（2026-10-23）

片上 TCM 的五次 CoreMark RTL 短测已超过 4/MHz：**4.000512**。
使用原 GCC15.2、`-O2`、同一固件、六级流水、原128KiB测试TCM，未调整访存延迟。
目标只高出0.012802%，是窄余量的仿真结果，不能当官方成绩、板测或物理验收。

| 内存边界 | 双发射原基线 cycles | 新候选 cycles | 新 CoreMark/MHz |
|---|---:|---:|---:|
| 片上 TCM | 1,411,226 | 1,249,840 | **4.000512** |
| 模型 DDR、I/D Cache 开 | 1,781,952 | 1,624,274 | 3.078298 |
| 同模型 DDR、I/D Cache 关 | 10,892,242 | 10,881,596 | 0.459491 |

TCM 吞吐较双发射基线提高12.912533%，WB观察IPC为1.158907；这不是CSR minstret。
所有计时窗口均有1,448,448次WB、70,839次store。DDR读写模型及Cache容量/策略不变。
DDR旁路仍受共享AXI访存瓶颈限制；TCM最高成绩不代表外部DDR的性能。
CPU-only LUT/FF/RAM、CoreMark/LUT及实际100MHz后布线时序均 **UNKNOWN**。

## 修改与逐步测量

| 隔离候选 | cycles | 主要变化 |
|---|---:|---|
| narrow-mul | 1,366,766 | 将已有窄MUL提前结果转发用于两个生产者槽 |
| branch-pair | 1,319,841 | 已解析为不跳转的条件分支，可配ALU/LSU/MUL |
| cross-pair | 1,252,785 | 四字队列压紧，跨64位取指包配对并保留元数据 |
| role-pair | 1,249,840 | 依ISA实际寄存器角色判断依赖，保留独立单元互锁 |

分支比较进入B槽许可；队列增加PC、数据和元数据选择路径。这两处有物理时序风险，
没有用仿真收益替代100MHz验收。完整设计仍在build隔离快照，生产RTL未提升。

## 验证边界

- 基线/候选完整TCM WB/store一致，仅归一化经验证的初始cycle绝对时间及对应started存储。
- 同一候选DDR Cache开/关完整WB/store一致，加载程序相同；CRC、软件cycle一致。
- 用版本化补丁重建所有13个CPU模块，并逐文件核对哈希；不启用profile observer再运行，
  软件和CPU_MEASURE均为1,249,840周期，CRC e9f5/e714/1fd7/8e3a/f24c，errors=0。
- 分支条件/跳转/访存/中断门控1550检查通过，故意破坏跳转判断负例失败。
- FIFO4005检查覆盖独立容量接纳契约、B-only、随机flush、PC/故障/CSR标记；破坏标记负例失败。
- 真实寄存器依赖单/双定向测试通过，摧毁scoreboard的真实RAW负例失败。
- 两个种子的单/双整核WB/store/同步异常与golden完全一致。专门程序检查taken跳过store、
  not-taken后的load/store alignment/access fault的mepc/mtval。
- 独立IRQ程序通过，记录64次分支+LSU配对和10周期IRQ与未完成取指重叠。
  配对计数是聚合值，未逐个fault PC统计B槽覆盖；IRQ不做golden精确轨迹相等声明。
- 组件补测CSR两条逐个消费、空队列、flush、取指空窗和新ALU包释放中断抑制；
  正常通过，强制中断抑制负例失败。组件测试强制已mask的pending向量并暂停执行；
  mstatus/mie与实际陷入由独立ordered IRQ检查。这不是穷尽ISA/异常/中断证明。

全部实际目录、结果哈希、冻结绑定和限制见[机器记录](dualissue_pairing_performance.json)。
独立只读评审重跑轨迹比较、核对CPU替换来源与Cache/transport保留来源，未发现
阻断本轮有界诊断接受的问题。未执行本路线PDS、板卡下载或串口操作。

## 重现

从当前生产CPU文件的冻结base哈希恢复候选；输出目录必须新建且位于build/cpu下：

```powershell
python scripts/cpu/prepare_dual_candidate.py build/cpu/dual-pairing-repro
python scripts/cpu/run_dual_diagnostic.py --firmware-run build/cpu/firmware-coremark-20261023T1103533439788Z --cpu-dir build/cpu/dual-pairing-repro/rtl/cpu
python scripts/cpu/run_cache.py --test coremark --issue-mode dual --cpu-snapshot build/cpu/dual-pairing-repro/rtl/cpu
python scripts/cpu/run_cache.py --test coremark --issue-mode dual --bypass-caches --cpu-snapshot build/cpu/dual-pairing-repro/rtl/cpu
```

补丁及全部base/candidate文件哈希分别保存在`dualissue_pairing_diagnostic.patch`、
`dualissue_pairing_sources.json`。下一门槛是CPU-only资源与原100MHz约束的真实布线；
在SoC集成占用PDS/板卡期间不启动争用工作，也不将候选合并回主工程。
