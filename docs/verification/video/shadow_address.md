# Shadow AW 并行译码检查点

F4c5c 的字节使能改动保留了 13 级 MMIO 地址到 shadow 写路径，布局 core
setup 估计仍为 −2.953 ns。本轮进一步移除 shadow 写入的动态索引，保持
原 ABI、AXI-Lite 响应拍数、健康检查与帧所有权规则。

AW 握手时，160 位字选择与原 awaddr 同拍锁存，完整绝对地址逐字比较。
每字拥有固定的四字节写进程；没有握手时选择保持，复位时选择和数据清零。
W 仍独立缓存，两个缓存都齐备才执行。地址总线在握手后变化不能改变目标。
shadow 窗口改为比较 64 位绝对常量边界，避免先减 BASE 再作范围比较。

原地址/四态、WSTRB、locked 检查保留。`do_shadow` 只在原组合逻辑判为
OKAY 时成立，静态写端不再重复串入总 write_response 比较；B 响应仍由原
逻辑产生。每个 shadow 字只有一个时序驱动；控制寄存器合并和读路径不改。

## 功能与验收边界

`test_shadow_decode.py` 从固定 Git 对象 `2c9c67f1797470fe038ec3de9b0cbcb2986b7daa`
提取参考 leaf，候选取本轮明确源快照。生成双实例 miter，接口 53 端口、
23 输出；在每个 core 上升沿后 1 ns 以四态比较采样值。这是选定场景的
周期级仿真对照，不是形式等价证明。

复用 10 组既有 MMIO 场景，包含本轮实际执行原生 C 驱动产生的 163 次写入；
另跑全部 160 字 ×16 种 WSTRB、AW/W 同拍与两种先后顺序、B/R 背压、错误
拒绝和复位，总计 2723 写/2883 读。AW/W 握手后立即将原地址/数据/选通总线
毒化为 X，检查锁存而非活总线依赖。错误 AW 对齐和取消 BVALID 的有效编译
变体须由 miter 明确拒绝，不能用编译失败充当成功负例。

初版 monitor 只比较非复位周期。独立审查与受控复位 fixture 都确认：只在
reset 期间改变 fault_code 的 RTL 可以逃逸。现已取消过滤，负例在 reset
期间报 `SHADOW_MITER_MISMATCH fault_code_o`；最终11正例/3反例和3项unit均
在普通/-O模式重跑通过。另拒绝
无法表示的 inout 声明，防止新增端口悄悄漏出比较清单。

实际健康和三模式显示组合另由 `record_mmio` 的六组 health 及
normal/ratio/asset_wait 验证；不把 miter 计数扩大为 CPU/NPU 或板测结果。

## 综合与物理工作

同一完整默认采显扫描边界、PDS 2022.2-SP6.4、8/25 ns 周期及原约束：

| 版本 | LUT | FF | DRM |
|---|---:|---:|---:|
| 原 merged shadow 写入 | 35321 | 44518 | 69.5 |
| F4c5c 字节使能 | 35254 | 44517 | 69.5 |
| 本轮 AW 并行译码 | 32881 | 44678 | 69.5 |

本轮相对字节使能版减少 2373 LUT、增加 161 FF，DRM 不变；综合无 latch。
同模型综合 core setup 估计从 −1.286 ns 变为 −1.306 ns，尚未改善。
资源减少不能代替时序通过。综合来源 `build/video/pds/20261022T115009_858784Z`；
本轮独立布局从其冻结源启动，定位 `build/video/shadow_decode_delivery/latest_static_place.json`。
最终物理结果未取得前，不宣称 125 MHz 收敛。

同 seed4/performance、原周期/稳定束/扫描 I/O 预算下，使用相同
`report_place_timing` 估计连线模型的一次布局对比：

| Slow corner | F4c5c字节使能 | 本轮AW并行译码 |
|---|---:|---:|
| core setup | −2.953 ns | −2.135 ns |
| pixel setup | −1.184 ns | +0.216 ns |
| core hold | −0.027 ns | −0.027 ns |
| core recovery | +1.366 ns | −0.954 ns |

core 最差 setup 改善 0.818 ns，仍未过关；fast core setup −1.306 ns，recovery
−0.724 ns 也为负。不得用 pixel 正值或 LUT 减少遮盖这些失败。最差路径现为
扫描输出寄存器至 `core_scan_o`（2级，−2.135 ns）；受限关键清单中还报出
内部 guard lane CE −1.551 ns 和 shadow→owner −1.510 ns，不能宣称产品内部
已全部过关。后续应分别处理扫描 I/O、复位网络和实际内部路径。

普通 `report_timing` 直接读 plc DB 的零数据连线报告另行绑定，不作这张表
的数据来源。本轮冻结 mapped/placed DB 曾启动完整布线，定位
`build/video/shadow_decode_delivery/latest_static_route.json`；进程在第10次迭代
后消失，最后记录43247个未布通net，没有 routed DB或最终STA。原因不作推断，
状态记录为 interrupted，不把它写成时序失败或成功。

19:55:49，原 merged-write 冻结版续跑路由真实结束：`Route-4022` 报拥塞、
`Route-0008` 报无法布线，详细迭代8仍有52375个未布通net，没有最终STA。
它是该布局/策略的一次失败，不代表所有策略或新版本都无法布通。全部冻结
源/DB/Tcl/工具另行复核；唯一变化仍是此前记录的当前生成器验证器，旧副本
匹配原绑定。PDS已先返回1，原helper未走到末尾哈希检查，不把预期验证器
变化误写为此次路由失败原因。原helper没有通过。

F4c5c 字节使能版完整布线仍以自己的 mapped/placed DB 独立运行；本轮新
RTL 不替换它的源。F4c5c 文档中的“两版运行中”是当时观察快照，本节给出
原版最新失败状态。两者与本轮并行地址译码的综合/布局身份分别记录。

没有修改公共配置、原 FDC、CPU/NPU 或技术报告；没有 JTAG、COM、Flash、
下载或板测。物理 DDR/CDC、系统资源与时序、连续 HDMI、真实模型和帧率仍
需独立验收。机器证据见 [shadow_address.json](evidence/shadow_address.json)。
