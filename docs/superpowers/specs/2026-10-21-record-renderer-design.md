# F4c4c 共享读仲裁与完整记录素材叠加

基线3f34cce，继续用户已批准的共享DDR读仲裁和完整记录叠加方向。Windows原生、
现有Video分支、本地小范围提交；本批不操作COM/JTAG/Flash，不改旧RTL/ABI/C。

选择在旧唯一Video DDR读口前新增video_read_arbiter，保留原读写scheduler；相比
重写旧scheduler或一次改整个SoC，更容易核验两个读客户端的归属。RAW紧急时最多
连续授权MAX_RAW_BURSTS（默认4）后给等待素材一次机会；非紧急时轮转，只有一个
客户端则直接服务。最多一笔总在途；源AR先锁存，再公开到唯一下游，已公开AR/R
不可抢占。有限burst公平不等于真实时间或显示截止期保证。

只接本工程AXI128/16B INCR、1..16拍、不跨4KiB/DDR窗口的描述符。非法/未知
描述符不公开到下游并fault。响应只按锁存owner路由，不能依据RID换owner，即使
两个客户端使用同一ID。RREADY由owner给出；错RID/RESP/LAST仍路由给owner并按
公布长度排空，故障禁止新授权，已接纳事务继续完成。意外R或未知/错RID/LAST
丢失排空可信性，即使已fault也保持undrained直到协调reset。允许实际下游AR握手
同拍的零等待R，但不豁免未接纳AR时的提前R。online/外部memory_fault独立报错。

新增video_record_renderer显式组合新仲裁、冻结avatar_ddr_cache和冻结
display_record_pixels。素材装载与外部RAW读客户端共用一个AXI128出口；素材cache
封存后，经pixel ready资格和稳定身份再捕获到像素域，连接真实同步provider与
每请求key。完整记录/实际RAW流、输出对齐commit及本地像素退休接口保持原语义。
三类独立fault交平台协调恢复，不把本地贡献当scanner release或全局FREE。

RAW像素流及其slot/frame/generation来自调用者；本批不从core延迟反馈伪造它们，
也不改raw_display去导出新标签。正式RAW扫描器/owner/MMIO接入另批完成。已有
video_pipeline继续RAW-only。素材为单份封存版本到协调reset，不做运行中多bank替换。

验证分开覆盖仲裁协议和真实组件链。集成TB连接旧video_shared_ddr/原生桥及数字
内存模型：素材来自真实地址字节，另一个RAW AXI客户端并发核对返回字节；外部
RAW像素模型送已知图，完整记录夹具先经guard。Python独立数学oracle预计算RAW/
BOX/AVATAR颜色/标记；核对完整800×600及小探针、首像素/同步/身份、反馈与退休
背压、素材等待、错误和复位。保存缺模块RED、定向变异、输入/工具/产物哈希。
组件综合core8ns/pixel25ns，真实报告资源/违例，不宣称物理CDC、布线或板测。
