# 完整采显组件注册边界与 MMIO 字节写使能

本批在 `video_record_pipeline` 外建立可布线的双时钟扫描边界，并依据布局
诊断缩短显示 MMIO 的 shadow 写入逻辑。core/pixel 仍为 125/40 MHz，原
稳定束约束保持 6 ns；没有增加产品接口延迟或改变 ABI。**尚未取得最终
后布线签核，125 MHz 系统时序仍未闭合。**

## 边界与约束

- 完整默认 DUT，共 161 个原端口、2227 位，不缩减 FRAME_HEIGHT，不绑死
  online、MMIO、源、DDR 或三模式控制。物理包装层仅 12 个端口。
- core 扫描输入/输出 708/1148 位，pixel 为 26/341 位，各用自身时钟和复位。
  输出 capture 优先于 shift；输入 shift 与输出 capture 同拍时捕获旧输入的输出。
- 原 4 条同步器第一级 false path 和 12 条稳定束 max delay 只加 `u_pipeline.`
  前缀；不加异步 clock group。8/25 ns 周期不变。
- 原组件 0 ns I/O 预算替换为扫描端口 max 2 ns/min 0.5 ns，每域另加
  setup 0.100 ns/hold 0.050 ns uncertainty，总计 30 条约束。这是新的注册
  边界模型，不能将其数值与旧组件 I/O 模型直接解释为 RTL 优化幅度。
- 生成器拒绝端口遗漏、重复域、未知约束、等价数值/集合写法的重复 CDC。
  显式 manifest 保留全部源文件及逐端口 offset/width；`--check` 检查三个生成物。
- 仅新目标允许组件 route，所有组件均禁止 bitstream。扫描输入可产生非法
  协议序列，边界验证不能替代采显合法流量、吞吐、CPU/NPU 或板测。

## 真实布局证据与产品调整

首轮 `20261022T073453_980862Z` 完成布局，原前台详细布线随后中断，无最终
报告；保留为 interrupted，不计成功或最终时序失败。其 placement-only
报告 core setup −2.841 ns、pixel −1.393 ns，pixel→core 稳定束 −0.141 ns。

最差 core 路径从 `u_pipeline/u_display/u_mmio/awaddr[13]` 到
`shadow[135][3]`，经过 15 级逻辑，逻辑 3.364 ns、估计连线 7.191 ns；
包含动态旧 shadow 读取、字节合并及广播写回。综合诊断中的 APM 路径不能
替代这一布局结果。布局门槛负例已留存，然后才修改产品逻辑。

`video_display_mmio.sv` 对 shadow 改用四个独立字节写使能，仅写入被 WSTRB
选中的字节，省去写路径上的 160 项旧值选择器。控制寄存器合并、地址/四态
检查、错误响应、AW/W 独立缓存、B/R 保持、健康门控、owner 和响应拍数保持。
未增加内部周期；原产品 FDC 与公共配置不变。

| 相同扫描边界下的综合 | LUT | FF | DRM |
|---|---:|---:|---:|
| 旧 shadow 合并写入 | 35321 | 44518 | 69.5 |
| 字节使能写入 | 35254 | 44517 | 69.5 |

新版综合来源 `20261022T092319_503464Z`，同版 PDS 2022.2-SP6.4，输入快照与
工具在运行前后校验。资源差值是综合结果，不能作为时序收益。布局对比及最终
布线的独立结果以机器摘要中的阶段和状态为准。

新版独立布局 `20261022T093606_170256Z` 已完成。采用相同 seed 4、performance、
8/25 ns 周期、6 ns 稳定束和 30 条约束；用相同 `report_place_timing` 估计
连线模型对比：

| Slow corner 布局估计 | core setup | pixel setup | pixel→core setup | 最差 core 逻辑级数 |
|---|---:|---:|---:|---:|
| 旧版 | −2.841 ns | −1.393 ns | −0.141 ns | 15 |
| 字节使能版 | −2.953 ns | −1.184 ns | +1.579 ns | 13 |

**core 最差裕量未改善。** 新版失败 setup endpoint 从 24350 降至 16328，但
不能抵消 WNS 仍为负的事实。剩余最差路径从 `awaddr[12]` 到 `shadow[62][31]`，
经过 32 位地址减法/范围选择及高扇出数据写控制，逻辑 3.307 ns、估计连线
7.360 ns。后续应针对这些实际路径继续处理，而非宣称字节使能已完成收敛。

直接对 `_plc.adf` 调用普通 `report_timing` 的诊断值为旧版 +1.327/+18.300 ns、
新版 +1.264/+18.335 ns，但该调用将数据连线延迟记为零，不能当作上述估计
连线模型，更不能用于物理签核。两种报告和输入身份分别保留；新路由门槛
明确拒绝这种显式 placement DB。

## 验证与审查

- Python 相关测试共 46 项，普通和 `-O` 分别执行；验收代码使用显式异常，
  不依赖会被优化掉的 Python assert。
- 扫描边界仿真覆盖全部端口的逐位移动、capture/shift/hold、异步复位、
  双域隔离及同拍旧值语义。每个输出具有不同输入签名；错误输入 offset、
  capture 优先级和标量输出交换三个有效编译的 RTL 反例均被仿真拒绝。
- 完整默认真实 DUT reset/idle 通过，未用该 smoke 声称完整协议流量通过。
- shadow 新自检在旧版、新版均通过：160 个字 ×16 种 WSTRB，AW/W 同拍及
  两种先后顺序，B 背压时读回、B/R 保持、越界/错位/未知数据拒绝和复位，
  共 2723 次写入、2883 次读回。
- 既有 `display_mmio` 十场景与实际 C 驱动回放通过；`record_mmio` 六组健康
  检查及 normal/ratio/asset_wait 三组真实 RAW/BOX/AVATAR 显示组合通过。
- 独立审查发现的约束去重、属性端口遗漏、标量输出交换盲区、双角时钟对
  覆盖问题均有负例与修复记录。新版时序门槛拒绝筛选报告、placement/map/syn
  DB、错误频率/源、缺角/缺时钟对、重复/非有限数据及路径/汇总矛盾。

## 运行记录与限制

原 mapped/placed DB 以独立隐藏进程续跑详细布线，定位
`build/video/record_probe_delivery/latest_resume.json`。它使用旧版冻结 RTL，
即使最终测得报告，也不能签核新字节使能版。该 merged shadow 版本随后真实
结束并报 Route-4022 拥塞/Route-0008 无法布线，没有最终 STA；这个结果只
代表该冻结布局和策略，不外推到其他版本。

续跑 helper 额外绑定了当前生成器；审查期间只修改生成器的拒绝逻辑，三个
物理生成物完全不变。旧生成器副本、前后哈希、全部 47 项冻结输入及独立审计
均保留。原 helper 对这个当前验证器变化应报失败，不能改写为 helper 通过；
后续接纳报告须独立核对全部冻结源/DB/Tcl/工具/报告，并明确该唯一变化。

字节使能版的 frozen mapped/placed DB 已独立启动完整布线，定位
`build/video/record_probe_delivery/latest_optimized_route.json`。初次启动因 helper
误用 routed DB 后缀而主动中止，记录为 interrupted；核对本版 PDS 实际使用
`_pnr.adf` 后重新启动。没有改写 DB、约束或产品 RTL。新 AW 并行译码版的
布局和 route 状态另记在 `shadow_address.md`；不能把任何布局估计当作最终签核。

新版布局脚本只使用新版综合的冻结源。探索 PDS post-synth 导入、设备不支持
的 top_module 选项和同脚本显式 DB 报告的失败均保留；最终使用完整原生流程
和独立报告调用，不把“命令返回成功但没有 DB”当作完成。

没有 CPU/NPU 迁入、JTAG、COM、Flash 或板卡操作。没有对当前 NPU 镜像作
改变。CPU/fabric/唯一 DDR 通路、物理 CDC/外部 I/O、连续 HDMI、真实模型输出、
帧率和全系统时序仍独立验收。下一步按新布局/布线真实关键路径继续收敛，
不通过放宽时钟、稳定束或 blanket CDC 切除获得通过。

[机器证据](evidence/record_probe.json)；原始日志、DB 和波形位于忽略的 `build/video/`。
