# F4c4b DDR素材装载与封存版本

继续用户批准的素材DDR装载方向；基线770dfde。Windows原生、现有Video分支，
小范围本地提交，保留旧生产RTL/ABI/C及其他路线修改；本批不操作COM/JTAG/Flash。

选择先接DDR到既有单份封存cache，而非增加第二份256KiB bank或把正式RAW/owner
闭环同时改写。这样复用已验证的固定拍provider，不增加另一份64DRM素材存储。
版本持有为整次协调复位epoch；运行中替换和一般引用分配器不在本批能力内。

新avatar_ddr_cache接core域load_valid/ready，锁存base/bytes/asset_id/generation/
expected_crc。默认素材256×256 RGBA8888、262144B，base16B对齐，整个范围限于
0x82600000..0x827fffff；测试可用4的倍数TEXELS，不能把小探针当正式尺寸。
独占AXI128读主端，固定ID、16B拍、INCR、最多16拍、4KiB拆分、最多一笔在途。
这是待仲裁的客户端，不另接一套物理DDR或修改现有唯一端口。

每拍缓存128bit，逐字节更新CRC32/ISO-HDLC，按内存R/G/B/A顺序重排成高至低RGBA
送入冻结avatar_texture_cache。最后texel须先通过CRC才允许写入，确保校验失败不
封存/公布ready。装满后素材身份不可变，load_ready保持低，直到全部域协调reset。
source DDR在整个读取期间也须由CPU保持不可变并保证写后读可见性；本组件不提供
跨master fence或CRC抗碰撞保证。CRC是本地装载描述符字段，不修改显示640B ABI。

result邮箱保持success/code/id/generation/bytes/crc至消费；实际像素provider沿用
原同步固定响应。失败粘滞fault，禁止继续装载，已公开AR不能撤回，按公布ARLEN
排空R，不再发新burst，不写最后texel。错误RID/RLAST/未知响应导致port_drained
可信性丢失，直到协调reset；timeout也不能冒充总线已排空。未知/非法描述符无AR。
最后texel真实写入是完成证明，FINISH仅发布历史事件。封存后online丢失不撤销
已完成素材；封存后意外R保留历史成功结果/素材，另报端口fault和undrained。
AR未接纳时的提前R必须报错；当拍AR握手的零等待响应允许保留至RECEIVE消费。
online丢失、CRC/总线错和在途reset均独立覆盖。上下游和两个时钟域必须协调复位。

新增测试使用独立Python/zlib字节/CRC夹具及带停顿AXI源，核对每个地址、burst、
握手、结果保持和全部cache texel读回，覆盖默认65536词、边界非整burst、错误描述符、
RESP/RID/早晚LAST/未知数据、CRC、online、timeout、reset重装及封存覆盖拒绝。
正式pixel/record联接、RAW扫描器/owner、实时多版本替换、共享读仲裁、CPU/NPU、
布线和实体板测后续分别验收。综合按core8ns/pixel25ns，真实报告资源与违例。
