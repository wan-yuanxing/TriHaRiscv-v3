# F1 raw 原分辨率全屏扫描验证

基线`53fd5ca`，依据[全屏显示设计](../../superpowers/specs/2026-10-19-fullscreen-display-design.md)。
本批新增独立`raw_display`组件，默认800×600 RGB888、40MHz像素扫描；旧双窗源与板级
目标保留。F1提供完整新帧记录，不含MODE/框/头像或正式显示MMIO。

## 行扫描与握手

core侧`record_valid/record_ready`消费一条命令，锁存base/stride/frame_id/slot。合法记录
经稳定邮箱跨域，bank0首行及身份就绪、前次事件退休且到达帧起点时实际提交；该拍
同时把`(0,0)`送入同步RAM流水。末列消费也包含起扫拍，1×1测试几何可以正常退休。
默认生产几何固定800×600；缩小参数1..800×1..600仅供组件测试。

每行2400B/150个128bit beat，两bank有效容量4800B。同步RAM不依赖reset清零；最后
像素退出读取流水后才归还bank，按行交替预取。每次扫描从DDR读取1440000B，重复
扫描仍计流量。RGB/DE/HS/VS同拍延迟，活动像素原样对应raw坐标，不缩放或加窗口偏移。

提交`commit_valid/ready`和释放`release_valid/ready`均保持身份至消费。旧DMA、预取和
像素引用全部退休后才发布旧槽释放；事件背压可跨多次扫描，活动图继续重复显示。
同base或同slot的新帧受保护；不同base所代表的分配必须由调用方保证不重叠。
当前组件验证128MiB逻辑DDR范围，生产槽译码/不可缓存属性由正式fabric与驱动负责。

非法尺寸/slot3、非对齐/越界/溢出/过小stride、未知地址/stride/frame_id/slot，均消费为
独立`record_reject_valid/record_reject_ready`事件，`record_reject_code=1`，并增加
`rejected_records`。拒绝事件保持期间不接新命令，活动扫描继续；它不改邮箱或全局
error，不会掩盖之后真实DMA故障。未知身份字段不作为可信回显发布。

## 故障与复位边界

AXI按16beat/4KiB/行尾拆分，公开AR在超时或DDR失效后保持到接纳；R仍按advertised
长度排空，不能按错误或早到RLAST撤销事务。RID/RRESP/RLAST错误、未知RDATA仿真
输入置code2，超时code4，DDR未就绪/失效code5，欠载code6。未知态检查不代表能检测
真实硬件中所有稳定比特翻转。故障输出确定背景并保持同步，失败扫描不记完成。

协调复位测试同时复位core、pixel和AXI从端BFM。单独复位master会清AR/R状态，不能
据此宣称从端保留在途事务时仍能排空；生产系统必须先排空或共同复位相关端点。
组件不支持局部取消、超时撤回或无条件持续运行；sticky故障要求受控恢复。

## 实际测试

```powershell
python scripts/video/run.py --suite raw_display
python scripts/video/run.py --suite all
python scripts/video/build_pds.py --target video_raw_display --stage synth
```

当前46项组件场景纳入all：33项命令/故障场景、5项非法几何、5种边界几何、2组时钟
比和800×600全尺寸。独立地址字节BFM与整光栅oracle比较所有活动像素，完整检查包含
首像素；全尺寸3次扫描共1440000像素一致。地址A以4KiB边界前16B开始，地址B与完整
raw区间不重叠，另有fixture断言；stride padding、行尾和释放后旧地址访问均检查。

CASE32验证活动画面中拒绝非法新记录、拒绝事件跨两光栅背压、再接合法新帧；CASE33
验证非致命拒绝之后仍能报告真实RID故障。该修正先在旧RTL上编译运行得到明确失败，
再在修正版通过。早期从双窗复用时的初始半帧未初始化测试已标记invalid_fixture，
不计有效RED；最终RED必须为已知frame17首像素背景与独立raw像素不符。

独立审查11项定向复核通过，包括非法请求后至少3个整光栅；5个实际编译RTL变异
（首像素、RGB地址、提前归还bank、slot保护、按早到RLAST退休）均被非零拒绝，另有
3项来源/复制篡改拒绝。原“非法描述符使当前图像转背景”问题已闭环，无剩余必修项。

## 综合与证据

最终组件PDS为`build/video/pds/20261019T105131_464218Z`：1332LUT、1614寄存器、
4个DRM36K、4APM。core8ns估计slow setup+3.094ns，pixel25ns为+19.809ns；11条约束
适用且无error/critical。首轮PDS因已合并的commit别名不存在被拒绝，修正为实际
active_frame/slot到commit输出的6ns束路径，未放宽约束。

该结果为未布线组件估计，外部端口未设置板级I/O延迟，PDS忽略的async_reg属性不能
代替物理CDC检查。仅切scalar同步首级D；稳定邮箱/请求/结果/事件束分别限6ns。
实际DRM多于有效数据量折算，来自128bit宽双bank映射，不以4800B直接推断块数。
运行时stride上界计算和输入到组合record_ready的路径尚未绑定上游寄存器/I/O预算；
上述内部setup余量不能据以签核正式可编程描述符端口，SoC接入时须补约束并按实际
路径结果决定是否流水化校验。F2固定记录的板级诊断也须以其实际网表重新布线验收。

最终全回归统计、源/工具/副本/日志与独立审查绑定见
[raw_display.json](evidence/raw_display.json)。完整all包含本批46项；早期中断/失败记录
保留，不将旧版本日志标作当前通过。本批只作本地小范围提交，保留31项其他路线修改。

最终完整回归`build/video/regression/20261019T105131_425226Z`退出0：35套件、184项
输入、285份仿真PASS日志，Python79通过/1项Windows符号链接权限跳过。父任务复核
192项源码及8项引用，归档614份日志哈希；交付12个文件，31项其他路线文件保持
起始内容。实施计划作为审查冻结快照保留，完成情况以本文和STATUS的实际结果为准。

下一阶段F2接独立板级raw全屏及实体图像验收；F3再接MODE与人工叠加，正式共享
DDR可见性、CPU/显示ABI、三槽生命周期、NPU推理及外部AC仍按各自依赖验收。
