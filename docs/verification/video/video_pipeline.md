# F4c3c 采集、共享DDR与显示端到端验证

日期2026-10-21，基线`869a028`，Windows原生。新增组件与测试，本批无COM/JTAG、
下载或Flash操作。完整机器绑定见[video_pipeline.json](evidence/video_pipeline.json)。

## 组件与所有权

`video_pipeline`仅显式连接原ABI2采集、开启REARM的三分支核、RAW显示MMIO和唯一
Video共享DDR端口。保留两个独立AXI-Lite口，不安装全局fabric；core125MHz、
pixel40MHz。源为可背压的core域PIX/EOF，未接物理HDMI ingress。
正式成功尺寸为800×600 RGB888/stride2400、400×300预览和320×320 BGR NCHW。
三类独立fault/错误码与两个原MMIO事件IRQ交平台使用，必须协调reset。

CPU仍是全局帧/graph唯一所有者；原RTL、ABI与生产C库保持原字节。显示仅公布
RAW能力；BOX/AVATAR仍拒绝。C收到实际采集事件，验证身份/几何/CRC及完成后才
调用frame_pool_capture_done。accepted/completion均ACK且rearm-ready后显式REARM。
显示真实commit与原槽退休不等于全局FREE；软件完成实际MMIO ACK后才复用。

## 可复验入口

```powershell
python scripts/video/run.py --suite video_pipeline
python scripts/video/run.py --suite capture_v2
python scripts/video/run.py --suite display_scanout
python scripts/video/run.py --suite shared_video
python scripts/video/run.py --suite frame_pool
python -m unittest discover -s tb/video -p test_*.py
python scripts/video/build_pds.py --target video_pipeline --stage synth
```

`video_pipeline.json`列出19个生产源和2个RTL测试源。Python runner严格编译本机
C99控制器，启动Icarus与C进程，通过管道逐笔转发实际R/W/F响应；A/S只等待真实
事件/状态，V核验native分支计数和B排空，E执行最终审计。协议不能注入capture、
commit或retire。保存工具版本/二进制哈希、输入/编译物/日志哈希、原始RPC往返；
新运行先作废旧PASS，期间输入变化会失败，只终止自身子进程。

RPC边界可暂停模拟时间，因此证明功能与生命周期，不证明CPU执行或延迟。C测试
提供空检测结果的graph/operator完成前提，未执行真实NPU。F是MMIO fence标记，
不代表物理Cache或跨master可见性屏障。

## 实际结果

| 场景 | 几何 | 采集请求/成功 | RAW记录/反馈/退休 | 实际写字节 | 完整像素/光栅 |
|---|---|---|---|---|---|
| normal | 800×600 | 4/4 | 4/5/3 | 8428800 | 2400000/5 |
| bad EOF | 800×10失败探针 | 1/0 | 0/0/0 | 71104 | 0/0 |
| native单bit存储损坏 | 800×10失败探针 | 1/0 | 0/0/0 | 256 | 0/0 |

正常四帧使用槽0/1/2/0。第二次真实commit/release事件未ACK期间捕第三槽，此时
C确认没有FREE且申请新槽返回NO_FREE；真实ACK完成后slot0才恢复可分配，第四帧
复用它。一次同RAW模式经真实SOF确认，不增加raw提交或释放。CAPTURING直接
present被拒绝且没有R/W/F回调；第三次因旧显示提交仍pending优先返回BUSY。

native模型以真实地址存储，独立算术oracle检查全部有效写字节和地址域；每个
word/frame tag保存覆盖bitmap，拒绝重复地址。配合每分支精确总量证明全区覆盖，
含全零padding。存储同时供桥真实写后核验和显示读取，不根据预期身份伪造读结果。
Python/zlib生成源CRC，C独立计算raw/preview CRC，完整光栅oracle核对保存的输出
像素、同步与blanking。core收到commit晚于首像素，故在光栅结束后核对整幅身份。

正常358万余core拍发生采显重叠，1194635拍捕获期间旧release仍保持，实际AXI
请求同时竞争42拍；读/写grant为30485/38292，欠载0。租约断言禁止覆盖仍被显示
持有的槽、释放后读或未完成就present。坏EOF/单bit损坏均产生实际失败完成，
采集写排空后C保持FAULT引用，拒绝REARM和新分配，不把失败探针当成功几何。

本机C正常2077检查，203读/850写/23 fence/10事件等待；两个失败探针73/66检查。
三场景共2216检查，正常1095笔、失败48/41笔实际RPC。旧capture_v2 12份、
display_scanout 17份、shared_video 24份、frame_pool 1份仿真日志全部通过，
共54份旧回归PASS；未声称重跑完整all。Python109通过、1项Windows符号链接权限跳过。

## RED、变异与独立审查

生产wrapper实现前，已写测试因缺失`video_pipeline`模块编译失败，保存absence
RED；这是集成缺失证据，不是已有生产行为失败。调试中保留runner路径/工具日志
兼容、首像素oracle的CDC身份采样及第三帧BUSY预期失败，均为测试/工具修正。

独立审查发现按分支字节总数无法单独排除重复写同一地址：原模型实际接受了等额
重复写，未覆盖位置仍为A5。新增bitmap后，不改刺激的独立探针触发
`PIPELINE_DUPLICATE_WRITE`，完整三路测试重新通过。另一测试预期问题为第三帧
pending提交时API先返回BUSY；已按冻结driver顺序修正，并加无I/O断言。
生产driver未改。独立审查另核实RPC旧事件/ACK/slot0重用的真实顺序。

三项隔离变异分别破坏native写字节顺序、完成记录generation读回、ACK前池内容
不变性，均被指定断言检出。所有变异均在build下运行，不修改生产源。审查来源、
原始探针/修复和最终结果由机器摘要绑定。

## 综合与后续边界

PDS2022.2-SP6.4组件综合为20318LUT、25158FF、5.5DRM、6APM、0锁存器。
core8ns寄存器路径setup估计+0.311ns，pixel25ns估计+19.809ns，最小hold估计
+0.619ns。14项约束全部适用，0 error/critical，94项端口I/O预算未指定警告；
源/控制/数据口按无外部预算的组件边界处理。同步首级例外及稳定束6ns约束沿用
原显示闭环并添加层次前缀，未整域切除。保留旧模块的属性忽略、常量/悬空清理等
工具诊断，不宣称物理CDC签核或全网表无组合环。

451项保护文件和31项其他路线现状保持，旧入口除本批新hook外原字节一致。
交付范围17文件。现有板级诊断镜像不变，本目标无管脚/位流，只有组件综合。

后续接BOX/AVATAR完整记录与素材退休，再联合CPU/NPU全局fabric及物理ingress。
本批完整尺寸采显并发证据仅适用于列出的可背压源/数字内存模型；物理跨master
写后读可见性、Cache/fence、不可背压HDMI连续流、真实NPU推理、物理采显带宽、
布局布线、外部I/O时序和实体板测继续独立验收。
