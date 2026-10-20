# F3c AXI 桥收集缓存时序修正

目标：保持 core 8ns、pixel 25ns、跨域约束和所有 AXI/native 公共行为，缩短收集缓存的写使能路径。

依据：capture 故障流水的数字检查点为 `1709d2a`。第7次实际构建
`20261019T185344_840850Z` 的 setup 为 −0.202ns/92端点，最差路径是
preview DMA burst_beats→WLAST→arbiter→bridge COLLECT 校验→expected 缓存 CE。
报告显示逻辑1.035ns、布线6.390ns，缓存控制节点扇出1881。结构审计通过，镜像未下载。

设计：仅从 expected/masks 的私有缓存写使能去掉当拍 WLAST 校验。
WLAST 首错诊断、COLLECT 的失败分支、故障隔离和 AXI 写拍排空保留原样。
坏 WLAST 对应的事务进入 BRESP/隔离，不会将缓存送往 native；协调复位后的合法
请求会完整覆盖其有效缓存和掩码。其他 init/offline、既有 fault、非法长度和
非预期 native R 控制保持原有即时缓存保护。不能删除公共故障或放松任何约束。

- [x] 先保存原桥源码/哈希和实际失败报告，建立原版与候选全公共输出逐周期对照。
- [x] 运行原桥自校验、完整长度/两种半字对齐、每个 WLAST 故障位置及 X/Z、复位后恢复；错误地删除公共 WLAST 诊断的替身须被检出。
- [x] 独立审查缓存的全部消费者、失败首因、未知控制、缓存不能泄漏到 native、协调复位后重用；通过后精确采用候选。
- [x] 运行 axi_bridge/raw_board/mode_board 回归，绑定当前来源与产物，保留旧数字和物理证据的精确历史例外。
- [x] 再次实际实现及结构/完整物理端点审计；通过后才打包、易失 Program/Verify 和原三模式现场验收。
- [x] 更新 STATUS、mode_board 记录和机器摘要，小范围本地提交，保留其他路线修改。
