# F4c3a Video局部共享DDR验证

基线`c58186d`，日期2026-10-20。Windows原生组件开发；本批无COM/JTAG/板卡操作。

## 行为与责任

`video_memory_scheduler`把采集AW/W/B与raw扫描AR/R串行接到唯一的既有
`axi128_hmic256`，`video_shared_ddr`提供显式wrapper。已验收桥、ABI1/2、采集核、
raw_display与板级目标均保持原字节。CPU继续决定全局帧槽和graph所有权。

每次接纳一个总事务；完整AW/AR描述符锁存，下游VALID/描述符保持到真实握手。
W必须在下游AW握手后传递。写owner保留到B握手，读owner按ARLEN+1次R握手
退休，错误RLAST不提前释放。普通竞争交替服务，`display_urgent=1`时读优先，
但有写等待时最多连续`MAX_READ_BURSTS`次读grant（默认4，支持1..16），随后服务写。
界限以对端持续前进为条件，任意native、W供数或B/RREADY停顿下无周期上界。

失锁、桥fault、提前/无主响应、错ID/LAST或未知有效控制/负载锁存首因并阻止新
grant。已接纳/公开事务继续保持并按advertised长度排空，不能靠局部reset取消。
正常SLVERR/DECERR原样传回。`port_drained`仅证明本调度器无事务，不证明全局
槽FREE、其他master或像素缓存退休。wrapper用错误码bit7区分桥首因。

## 可复验入口

```powershell
python scripts/video/run.py --suite shared_video
python scripts/video/run.py --suite axi_bridge
python scripts/video/run.py --suite raw_display
python scripts/video/run.py --suite capture_v2
python -m unittest discover -s tb/video -p test_*.py
python scripts/video/build_pds.py --target video_shared_ddr --stage synth
```

正式filelist为`fpga/pg2l100h/project/video_shared_ddr.json`；没有递归收集全部RTL。
`shared_video`保存显式输入、工具和编译/运行产物哈希，运行期间变更输入则失败。

19项协议测试包括正常交替、urgent配额1/2/4/8/16、地址/响应背压、失锁、桥fault、
错误LAST/ID、无主响应、未知WVALID/WREADY和256拍非法读的完整DECERR排空。
故障排空后重新拉高两路请求，确认锁止；响应背压期间不能释放owner。

5组联测使用真实ABI2、多帧三分支核、raw_display、调度器和桥。测试源直接提供
core PIX/EOF；native字节模型独立按地址译码。每帧raw/preview/BGR NCHW数据、
CRC、stride空隙与地址护栏都检查，真实桥写后读回成功B后才提交显示记录。
仿真控制器模拟CPU槽引用：接纳记录即持有，匹配实际commit，实际release握手
后才复用旧槽；其中一组额外背压release 71个core周期。输出逐像素/同步/blanking
核验，三槽轮转且下一帧采集与旧帧扫描重叠。

| 场景 | raw几何 | 上/下padding | core周期 / pixel周期 | 帧数 |
|---|---|---|---|---|
| normal | 30×20 | 2 / 1 | 8ns / 50ns | 7 |
| minimum，读配额1 | 10×10 | 0 / 0 | 8ns / 24ns | 5 |
| wide，无native间隙，读配额8 | 40×30 | 4 / 5 | 8ns / 50ns | 7 |
| held_release | 30×20 | 2 / 1 | 8ns / 50ns | 7 |
| ratio，读配额16 | 30×20 | 2 / 1 | 8ns / 34ns | 7 |

每组必须有采集/扫描重叠、完整提交/释放和零欠载；整组必须观测同时AW/AR竞争。
最小几何可自然错开发请求，因此不要求每一组都有同时竞争。结果计数由
[机器摘要](evidence/shared_video.json)绑定，不以仿真时间推断物理带宽。
总计33帧、96237个有效写字节、39900个显示像素、61个完整光栅、28次旧槽释放，
1270次读grant/2214次写grant，4次同拍请求竞争，欠载0。

旧桥191例、raw_display 46项、ABI2 12份仿真及Python110项中的109通过、1项
Windows符号链接权限跳过。只重跑这四个受影响suite，没有声称重跑完整all。

## RED、变异与审查

实现前用原桥写优先策略持续竞争，实际触发`SHARED_READ_STARVED`，源快照与工具/
日志在`build/video/shared_video_red/`。9项父测试变异分别破坏读服务、写配额、地址、
R/B背压保持、RLAST退休、故障锁止以及两项未知W控制检测，均被指定断言检出。

独立审查复现未知WVALID/WREADY未置fault；增加状态限定检测后，恢复合法W、
完成B、证明排空及重新请求被锁止的RED/GREEN均通过。review保留原快照，不把
修复前结果重标为当前验证。独立随机长事务、descriptor变化、响应同拍、错误
排空及lease/pixel oracle故意破坏的证据另行哈希绑定。
最终独立检查包括19项正式协议、18项额外定向、5000个持续VALID/描述符稳定的
随机事务，以及五组完整联测；9项调度变异和2项lease/pixel注入均被检出。
24项来源、277项产物、14项工具哈希经父任务复核，无未关闭发现。

早期TB曾将复位后不完整首光栅纳入比较，现从完整光栅起检查；minimum/wide的
同时竞争覆盖条件过强，调整为逐场景重叠、整组竞争检查。故障负测曾在请求VALID
为0时检查READY，变异暴露覆盖不足后改为故障后重新提出请求。以上原始失败保留，
没有为此修改生产采集/显示核。

## 综合与边界

PDS 2022.2-SP6.4独立wrapper综合3806 LUT、3561 FF、0 DRM/APM/锁存器；core
8ns下寄存器路径估计setup +1.993ns、hold +0.730ns。组件I/O未约束且1105个端口
超过封装物理I/O，不能布板下载。保留旧桥缓存feedback/constant-probe、属性忽略、
常量/悬空清理及fanout警告；没有宣称综合网表全图无环或外部时序已签核。

本批只验证列明的数字几何、时钟和延迟模型，未验证800×600采显并行吞吐，未执行
新布线或板测。urgent在联测固定1，实际水位生产者未接入。测试控制器不是生产C
三槽库/显示MMIO退休适配器；不存在本批CPU执行、全局CPU/NPU fabric或物理跨
master可见性证明。HDMI不可背压入口、素材DDR、连续视频须后续联合验收。

下一步接显示MMIO/所有者与raw扫描器的真实提交、释放适配，并用CPU三槽库实际
事务回放验证，可以在CPU核接入之前完成。冻结来源、31项其他路线现状、18文件
精确本地交付及各项证据入口见机器摘要。
