# SRAM本地命令许可 v78

基线v77，CPU22个文件保持原候选哈希。仅改隔离的SoC memory，正式rtl/soc不变。原100MHz、多corner/IO/hold、seed1保持。

## 根因和方案

v77最差-0.185ns，data_error经LSU delay/issue_lsu到SRAM memory_15 CEB。实际合成显示该CEB为取指inst_en（不是data_en）；写碰撞依赖通用d_fire是传播入口。只改数据CE不能覆盖它。

采用本地合法读/写命令译码，maintenance已知1或读写00/11直接禁用；maintenance已知0且单一读/写时，以原accept、SRAM命中、对齐形成许可。所有X/Z控制使用原表达式fallback。数据CE和d_write/取指collision同时使用此许可。既有LSU pending、ack/error、指令挂起队列、MMIO和ROM语义/周期不变。

备选为新增请求寄存级，会影响周期/握手而不采用；仅加同义wire不能保证综合隔离，必须实际检查DRM CE支持锥。不得删除mem_error阻塞以缩短链。

## 执行门槛

1. 独立四态wire oracle检查实际RAM数据CE、取指CE和字节WE；冻结父版对照，旧d_fire污染红测、新正测和实际CE损坏负例。
2. 完整memory组件验证字节写、错误/紧邻请求、instruction collision和reset。完整CPU CoreMark/profile/WB/store对v77比对。
3. fresh native compile/synthesize/dev_map，核验实际DRM两类CE不再穿越全局issue_lsu/d_fire节点；保留全部其它绑定。未知/歧义或目标未满足则HOLD。
4. 独立评审后才准入单次fresh原100MHz完整PNR，最终审计六项STA、performance与哈希，不提升默认RTL。

v78初步候选只改data_en，已经启动的完整CPU回归保留为诊断；不把该候选用于PNR。有效候选为sram-local-command-v78-v2，组件使用扩展三端口oracle的v2测试。早期/有效运行TB哈希不同，分别保留。

## 组件独立评审

四态变换审查成立。评审指出仅污染初始读场景不能拒绝只改dataCE的旧候选，现v3测试保持污染贯穿同字写/上半字/非碰撞写。有效候选38916检查PASS，旧dataCE-only候选语义PASS但结构污染FAIL，实际CE损坏负例检出。完整memory回归PASS，41输出哈希核验。实际网表门槛要求两个禁入名真实存在、恰好16动态DRM CE（8数据+8取指），不接受非空即视为覆盖。

## 完整CPU与native准入

有效候选完整CoreMark通过（coremark-20261027T075648276873Z），122输出哈希核验；measurement/profile、全部WB/store与v77完全一致：1221907周期，1448448 observedWB，IPC1.185400，短测4.091964/MHz，非官方或板测。

native fresh compile/synthesize/dev_map通过，68输出核验；CPU-only9856LUT/4975FF/752已含RAM-LUT/4APM/0DRM，较v77 +16LUT。实际16个动态DRM CE锥均不含通用d_fire/issue_lsu，注入共享控制返回HOLD。六组branch比较器、BTB256WE/624地址/80延迟边界、64目标FF与60sum carry亦重放PASS，均仅为结构门槛。

独立评审支持单次原约束PNR。fresh目录`build/cpu/dual-sram-command-io-physical-v78`，原10ns/IO/hold/multicorner、seed1，PNR600秒/外层900秒。已启动；未出现最终报告前不认为100MHz通过。
