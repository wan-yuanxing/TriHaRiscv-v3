# I/D Cache 跨时钟及 DDR 桥接核验

2026-10-21，父节点 `445ae87`，`cpu/windows-baseline`。本轮完成数字功能和原生资源映射节点；**没有缓存版实际100MHz后布线、真实DDR/共享fabric或板测准入**。未访问COM12、下载板卡、写Flash、合并或推送，原部署包保留。

## 连接与固定输入

新增 `triha_axi128_cdc.v`：CPU100MHz与DDR125MHz间的AW/W/B/AR/R五个独立弹性队列，完整保留地址、数据、ID、长度、访问参数、字节掩码、LAST及错误响应。每队列复用已有同步读Gray指针FIFO，四个RAM项加一个保持输出寄存器。DDR就绪/故障只同步到CPU，不能撤销已有通道载荷。一个协调复位输入在两域分别同步释放，并供CPU、Cache及DDR桥使用；真实控制器也必须参加相同复位epoch。

新增 `triha_cpu_ddr.v`，连接既有本地缓存CPU、CDC及独占native256 DDR桥。它没有生产CPU/NPU/Video仲裁器，也没有真实DDR PHY或板级PLL/管脚。后续共享仲裁须在这一个桥之前，不能在native写入与核验之间另插一个写端。

`config/cpu_ddr.json`固定提交 `8635a91626d87eb7573beba5ea805a5f6043bb8a`，桥SHA256 `c3d3f04bd183bc50e9ecbca25c0577c2ee802a426b3cae7c286212df9e6dea33`。`prepare_ddr.py`从共享Git对象读取四个固定文件，按哈希写入本轮build/pinned，不依赖另一工作树当时的内容，也不覆盖本工作树旧Video文件。FIFO、native数字模型和接口文档也分别绑定。已有core28、基准9、cache7个原件哈希保持不变。

## 实际验证

| 测试 | 观察 |
|---|---|
| 五通道独立oracle | 标称100/125MHz和半周期3/6ns、7/4ns两组压力比例通过；每通道每完整epoch256条，共两个完整epoch，另一个带在途数据的epoch被协调复位；核对每个载荷位、顺序、队列满及VALID保持 |
| 状态变化 | 输出受阻时撤销就绪并置故障，已接受队列继续排空；同步状态正确，不由状态事件重置FIFO |
| 真实CPU，Cache开启/旁路 | 同一个O2固件及ROM/SRAM镜像通过：ROM→SRAM、UART、私有/共享DDR代码与数据、FENCE.I、异常/MRET及故障后的本地执行 |
| 写完成 | 每次成功的CPU DDR store分别核对native写入、后续同址读回完成及真实模型中有效字节；每次完整软件运行22次成功store |
| 整体在途复位 | native AW/W已经接受、CPU尚未得到响应时，同时复位CPU/Cache/CDC/桥/native模型；之后整套软件重启通过，未复用旧FIFO响应 |
| 错误 | 一次可恢复读错误通过测试台明确注入AXI RRESP，检查CPU访问异常；native初始化丢失使实际桥锁存错误码1，CPU仍可执行本地代码。不是宣称native接口本身提供普通SLVERR |
| 负例 | CDC载荷损坏、CDC看门狗、native读回损坏、真实CPU看门狗均实际被拒绝，宿主退出1；不是根据模拟器退出0接受失败程序 |
| Python | 新DDR绑定4项和核验4项，加原60项，共68项通过 |

上述软件是定向诊断程序，周期含UART及重启，**不是CoreMark测量**。开启/旁路实际ROM、SRAM和ELF文件相同。数字存储模型没有模拟模拟信号训练、板级失真或实际DDR延迟；可恢复错误为显式注入，不掩饰为真实物理故障。FIFO仿真也不能证明亚稳态概率或物理Gray总线skew。

## PDS 原生资源

PDS2022.2-SP6.4实际compile/synthesize/dev_map通过，无锁存器；CDC使用6个DRM36K等效原生块存储。以下是同一综合上下文，排除串行面积夹具；RAM LUT已计入总LUT。

| 范围 | LUT | FF | RAM LUT子集 | DRM36K等效 | APM |
|---|---:|---:|---:|---:|---:|
| CPU核 | 6218 | 3563 | 688 | 0 | 4 |
| I/D Cache及传输 | 514 | 763 | 0 | 11 | 0 |
| 本地ROM/SRAM/MMIO | 127 | 89 | 0 | 16.5 | 0 |
| 本地路由及剩余逻辑 | 54 | 16 | 0 | 0 | 0 |
| CPU本地缓存子系统小计 | 6913 | 4431 | 688 | 27.5 | 4 |
| 五通道CDC及状态/复位同步 | 67 | 153 | 0 | 6 | 0 |
| 固定DDR桥 | 3691 | 3358 | 128 | 0 | 0 |
| 总计 | **10671** | **7942** | **816** | **33.5** | **4** |

桥包含原有完整burst缓存和写后读回核验，没有为了缩小面积改变完成语义。CPU核6218LUT属于本轮层次/常量传播上下文，不能与stage2的6434LUT或原板测5933LUT直接宣称优化收益。device_map顶层10883LUT/8597FF包含夹具，不作为CPU资源。面积夹具没有真实DDR管脚/PHY，不用于100MHz验收。

`review_ddr.py`独立重读全部冻结输入/输出、当前源码、固定Git文件、工具、真实命令退出码、native阶段标记、实际单发射/预测器/五队列参数与层次资源，结果PASS。小型索引及所有原始目录/哈希在 `id_cache_stage3.json`。

## 复现

```powershell
python scripts/cpu/test_ddr_binding.py
python scripts/cpu/test_ddr_review.py
python scripts/cpu/run_ddr.py
python scripts/cpu/run_ddr.py --cpu-half 3 --ddr-half 6
python scripts/cpu/run_ddr.py --cpu-half 7 --ddr-half 4
python scripts/cpu/run_ddr.py --test system --firmware-dir <stage2已通过runtime目录>
python scripts/cpu/run_ddr.py --test system --bypass-caches --firmware-dir <同一目录>
python scripts/cpu/run_ddr.py --fault data
python scripts/cpu/run_ddr.py --fault watchdog
python scripts/cpu/run_ddr.py --test system --fault data --firmware-dir <同一目录>
python scripts/cpu/run_ddr.py --test system --fault watchdog --firmware-dir <同一目录>
pwsh -NoProfile -File scripts/cpu/run_ddr_pds.ps1 -FirmwareRunDirectory <本轮已通过system目录>
```

四项故障注入应退出1。`review_ddr.py`接收三组CDC、两组system、四个negative及area目录，全部参数可由JSON索引定位。每次独立build，旧结果保留，包括模块尚未实现的RED和首轮测试台integer输出连接导致的ModelSim展开错误；该轮原始退出码12，不属于CPU时序失败。

## 剩余准入

下一步需要真实DDR控制器/CPU PLL/板级管脚顶层、CDC物理约束和实际100MHz多corner后布线。需要核对Gray总线延迟/skew及同步器位置，不能用整域豁免掩盖同步路径；也不能把本轮综合频率估算当实际时序。独立停钟/初始化监测及控制器参加的协调复位须在板级落实。

随后接CPU/NPU/Video统一fabric，验证跨主端可见性、仲裁和共同复位。当前桥独占native端口的写后核验只证明本端口数字观测，不表示物理持久化、任意旁路端或跨主端完整一致性。未执行板卡编程，缓存版仍不可替代已部署的稳定镜像。
