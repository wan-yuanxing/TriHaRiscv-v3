# F4c4d 实际 RAW 扫描与联合退休

基线8635a91，用户“继续执行”确认上一批提出的实际扫描器身份和owner联合退休
方向。沿用现有Video分支、Windows原生、本地提交，不操作COM/JTAG/Flash。

选择扩展raw_display的可选sideband并新增display_record_link/video_record_scanout，
而不复制整套扫描器或直接扩展正式MMIO。原RGB/握手行为保持；新增record_generation
贯穿冻结mailbox、pending/target/active和commit/release事件，并在同步RAM两级像素
输出处导出有效身份、坐标、SOF。身份在像素选中时捕获，不来自core反馈延迟猜测。
旧命名端口调用者可不连接新增sideband，不改变原功能。

video_record_scanout组合原display_slot_owner(CONTEXT_WIDTH=5120)、实际扫描器、
上一批真实DDR素材渲染器和新联接层。唯一AXI128读出口维持原共享DDR拓扑。
输入为调用者已通过display_record_guard的完整记录；模式支持RAW/BOX/AVATAR，
ABI仍800×600、stride2400，缩小几何仅供测试。正式video_pipeline/MMIO不扩展。

owner的cmd_data在cmd握手后保持至feedback消费，新联接层租用这份冻结记录，
避免再复制5120bit。先发布渲染命令，再对新帧发布扫描记录；同帧mode_only不重新
提交RAW。联接层分别保持扫描器commit和首实际输出commit证明，身份必须精确匹配
slot/frame/generation/mode/seq。只有两者齐备才反馈owner；mode_only沿用已经证明
的RAW引用，仅等待新的输出commit。所有事件valid在背压下保持。

每个已租用槽保持完整frame/generation与两项退休证明：扫描器release表示旧DMA/
bank/RAW像素均退出；渲染器retire_raw表示旧输出流水已退出。两个证明都消费，
并且owner已接受替换帧反馈后，才向owner提交一次退休。任一证明、generation或
替换反馈缺失均不释放。owner的release持续至调用者ACK；此FREE仅为Video引用，
CPU仍是全局帧/graph所有者。素材退休单独保持id/generation贡献，不能覆盖单份缓存。

故障拒绝新的显示记录提交，不伪造commit/retire。素材load沿用原cache接口，平台
必须检查online/综合fault后才发起；此入口不提供独立故障门控或自动撤销。已公开
扫描器请求仍按原协议排空，历史已
证明事件可保持。未知/错误/重复事件身份粘滞fault，所有域和AXI端须协调reset。

测试先RED，再实现：联接层定向检查证明顺序、单项缺失、generation误配、mode_only、
资产与owner背压；集成连接实际旧shared_ddr/原生桥、字节内存、真实扫描与素材，
按独立数值oracle核对三模式及换帧。分别运行小几何、异钟比、完整800×600；
记录RAW RGB与身份两级对齐及输出13级对齐。重跑raw_display、display_scanout、
video_pipeline受影响回归。综合按core8ns/pixel25ns记录实际资源、约束适用性和
路径，禁止以成功退出当时序闭合；本批不承诺route/物理CDC/板测或CPU/NPU执行。
