# F4c4d 实际 RAW 扫描与联合退休

2026-10-21，北京时间，基线`8635a91`。Windows原生Icarus/PDS；本批不操作
COM/JTAG/Flash。[机器证据](evidence/record_scanout.json)保存最终结果和哈希定位。

## 实际数据链

`video_record_scanout`显式连接原`display_slot_owner(CONTEXT_WIDTH=5120)`、
新`display_record_link`、实际`raw_display`和上一批`video_record_renderer`。
扫描器与素材缓存通过原仲裁共用唯一AXI128读出口。数字集成测试继续接原
`video_shared_ddr`、scheduler和原生DDR桥；RGB现在来自同一内存返回数据，
不再使用与AXI流量独立的外部RAW像素模型。

输入完整记录须先经调用者`display_record_guard`校验。owner冻结cmd_data直到
feedback消费，联接层租用此记录，不另复制5120bit。RAW/BOX/AVATAR模式命令先
送渲染器，新帧再送扫描器；mode_only不重发RAW。正式MMIO和`video_pipeline`
保持RAW-only，CPU/NPU执行与系统级采显闭环不属于本组件结果。

`raw_display`新增可选generation/像素身份旁带：generation随冻结mailbox和
pending/target/active传递；在实际同步RAM像素启动沿选中target或active身份，
与RGB同步延迟两级输出slot/frame/generation/x/y/SOF。commit/release generation
采用原保持事件和ACK控制跨域，不从core反馈猜测像素身份。旧命名端口调用者可
不接旁带；原`tb_raw_display`的通配实例显式绑定新输入0并留空新输出，其他激励
和断言保持。新组件FDC覆盖旁带CDC，不引用旧目标的历史时序结论。

联接层须同时消费精确匹配的扫描器commit和渲染器首输出commit，再向owner反馈；
mode_only沿用已证明RAW引用。每个租用槽保存frame/generation、scanner release
与pixel retire_raw两项证明。只有二者齐备且替换帧反馈被owner消费，才提交一次
退休；owner release持续到调用者ACK，ACK前不可复用。此处FREE仅结束Video引用，
CPU仍负责全局帧/graph状态、跨master可见性和最终释放。

素材退休单独保持完整旧slot/frame/generation/seq与asset id/generation贡献。
新联接层按上一份实际渲染commit记录精确预测旧raw/asset退休事件，检查标志和
身份后只消费一次；允许合法再次使用相同seq/key，不假设序号单调。素材缓存
仍为一份封存数据至协调reset，不允许靠退休贡献覆盖缓存。

显示记录入口同时门控owner valid和外部ready，含当拍online/memory_fault资格。
故障停止新的显示记录提交，已证明历史事件在背压下保持；所有域、扫描器、owner及AXI端
须协调reset。`port_drained`仅为读端口/素材装载证明，不能替代扫描器、像素与
软件的全局释放条件。

素材load入口沿用上一批cache握手：平台必须先检查online/综合fault并停发新load，
组件不在该入口再门控ready或自动取消。故障时load_ready仍可能为1；平台违规提交
会被缓存锁存，后续AR可能停在故障仲裁器前，必须协调reset处理，不能当作自动
拒绝/回滚。独立故障装载探针记录此边界，不宣称所有入口都具有故障门控。

## 测试与故障证据

```powershell
python scripts/video/run.py --suite record_scanout
python scripts/video/run.py --suite raw_display
python scripts/video/run.py --suite display_scanout
python scripts/video/run.py --suite video_pipeline
python -m unittest discover -s tb/video -p test_*.py
python scripts/video/build_pds.py --target video_record_scanout --stage synth
```

新增联接层与组合模块先保存缺模块编译RED；新增RAW旁带先保存旧扫描器未知端口
RED。集成首轮还暴露测试把内存驱动信号初始化为reg的连接错误，已改为wire。
旧RAW测试通配实例因新增端口编译失败，改为显式旁带绑定后重跑。

联接层6个定向场景涵盖两种commit顺序、同拍commit、generation错误、重复commit、
联合退休、素材与owner背压、mode_only以及素材退休重复。原测试曾合成一个RAW
旧引用的素材退休事件；补精确退休历史时改为合法AVATAR→RAW夹具。独立审查
另在替换反馈已消费后分别只给RAW或像素证明，确认100周期不退休；删除任一
证明条件的复制变异都会被对应断言检出。

整链分80×64、异钟比80×64和800×600三场景，均使用实际字节内存、扫描器与
RGBA缓存。测试先检查扫描器RGB/坐标/同步/身份两级对齐，再对输出13级历史
逐像素核对独立整数RAW/BOX/AVATAR oracle。每个场景切换5次、换帧两次，检查
slot0/frame1从generation10退休后以generation11复用；release ACK前的复用被
owner以code5拒绝。RAW/素材装载并发、不可背压光栅、素材CRC及1025个burst分别
计数。光栅W+256/H+28，完整场景即1056×628数字时序；这不是物理HDMI验收。

首实际out_de/out_sof证明之前禁止owner commit。模式切换不增加scanner commit；
asset事件保持至独立消费。测试结束前每个已提交seq至少核对一幅完整画面，
最终数值、变异、独立探针与受影响回归以机器摘要绑定。

最终6个联接场景及3个实际扫描集成场景全部通过。800×600场景核对1920000个
RAW、480000个BOX、960000个AVATAR输出有效像素，以及3360000个扫描器有效像素；
完成5次commit、2次release，scanner仅3次新帧commit。原生读命令43678次，其中
RAW42653、素材1025；RAW与素材装载重叠计数359185个core周期，无欠载。

受影响旧回归为RAW扫描46个场景、显示扫描17个场景，以及实际C驱动参与的
video_pipeline三个场景；Python110项中109通过、1项Windows符号链接权限跳过。
父任务5项隔离变异与审查方2项缺失退休证明变异分别记录。父任务故障入口变异
已被探针实际断言检出，最初汇总脚本期待了另一个断言名字，后核对原GREEN/RED
日志修正汇总标签；未把汇总标签错误说成实现失败。

独立审查复现并关闭两项实现问题：故障后的新提交仍可预留槽；素材退休缺少
历史资格导致未期待/重复事件可被转发。修复分别是即时入口门控和精确单次退休
账本。原首个素材RED探针并非guard校验过的合法AVATAR夹具；合法首次事件及
再次获取、背压和重复拒绝由后续GREEN与隔离变异补证，不混淆两类证据。

## 综合与边界

PDS综合18624 LUT、30058 FF、68 DRM、10 APM、0锁存器。core8ns setup估计
−1.797ns（估计102.0721MHz），最差路径`u_raw/error`到`submit_ready`组件输出pad；
pixel25ns +11.549ns，pixel→core稳定束+4.934ns、core→pixel+4.355ns；最差hold
−2.470ns。工具明确Some Constraints Violated，125MHz尚未闭合，不能与另一top
的历史WNS直接作时序优化幅度比较。

26条约束均适用：2时钟、4条scalar首级例外、12条稳定bundle延迟及8条输入/
输出预算；不切整个异步clock group。constraint_check为0 error、0 critical、
138 warning；综合日志另有大量逐位清理/未连接诊断，以原日志为准，不能把138
当成全部综合警告。组件6944接口位超过300物理I/O，无板级管脚、布线或物理CDC
签核。ASYNC_REG等诊断保留，不以数字通过替代物理验证。

下一步是正式显示MMIO/采显流水线的三模式接入，再在真实内部互连下处理core
边界路径并完成布线。CPU全局帧池、NPU真结果、连续HDMI吞吐、跨master写可见性、
运行中素材替换和板测仍须各自验收。
