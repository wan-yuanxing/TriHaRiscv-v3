# F4c4a 完整显示记录与叠加像素退休

2026-10-21，基线`d079e75`，Windows原生。新增独立`display_record_pixels`组件，
复用原`display_mode_cdc`、`display_overlay`和`avatar_sample_map`，原生产RTL、
ABI与C库保持字节不变。机器绑定见[record_pixels.json](evidence/record_pixels.json)。
本批无COM/JTAG、下载或Flash操作。

## 记录、首像素与引用边界

调用者先用冻结的`display_record_guard`完整校验640B记录，再传入本组件。
组件补查已知值、头部身份及800×600/stride2400几何，完整5120bit payload原子
跨域，解码16框、80点、primary和目标矩形。记录只在实际RAW的slot/frame/
generation匹配且素材就绪的输入SOF生效；同帧模式切换无需重新采帧。

素材未就绪时，已到达的匹配新RAW先透传，保留旧引用，等待下一匹配SOF；
已经就绪但素材身份不匹配则故障。素材id/generation随9级地址流水逐请求传递。
provider须按固定拍返回数据，并保留所有仍被引用的素材版本；本组件没有素材
DDR DMA、缓存分配或动态bank替换能力。

输入边沿n的像素在n+13退出末端，颜色、同步、坐标、源身份、mode/seq和效果标记
保持对齐。只有新记录的首个实际输出像素才证明commit，接纳命令不构成commit。
core消费真实反馈后，才发布保持至消费的旧像素退休贡献。raw身份改变时给出
`retire_raw`；旧素材不再使用时给出`retire_asset`及旧素材身份。同素材跨新帧持续
持有；同帧AVATAR转RAW只退休素材，不释放RAW。退休未消费时不接纳下一命令。

这里的退休仅证明像素流水排空，不能替代扫描器读DMA/预取/行缓存排空、owner
release或CPU ACK，不能直接把全局槽改为FREE。CPU继续唯一管理全局帧/graph。
已有`video_pipeline`和`video_display_scanout`仍为RAW-only，本批未接入正式
BOX/AVATAR显示MMIO闭环。

未知/非法命令、像素身份、provider或CDC错误粘滞fault。core故障双级同步后禁止
pixel接纳及未证明的commit；故障前已经证明的反馈/退休仍保持。n+13同拍后续输入
故障不追溯撤销n输入已正确输出的首像素证明，但当前退出像素错误会禁止其commit。
两个时钟域、provider和上下游状态必须协调复位。

## 可复验入口与覆盖

```powershell
python scripts/video/run.py --suite record_pixels
python scripts/video/run.py --suite overlay
python scripts/video/run.py --suite mode_resources
python scripts/video/run.py --suite display_scanout
python scripts/video/run.py --suite display_mmio
python -m unittest discover -s tb/video -p test_*.py
python scripts/video/build_pds.py --target video_record_pixels --stage synth
```

显式JSON列4个生产源、2个测试源和1个FDC；guard只用于测试夹具合法性校验，不在
生产wrapper内重复安装。每条实际提交的原始夹具先经guard验证，再注入指定错误；接纳后
毒化core payload，核验邮箱原子性。数值oracle独立从记录解码，调用既有数学参考，
以预期SOF和实际RAW身份选择上下文，不以DUT内部apply决定期望结果。

16场景包含normal、异钟比、无blanking、错误header、错误asset key、实际sample
故障、协调reset、未知命令、晚到故障、generation等待、新RAW先于素材、core故障
时仍有pending命令、同帧新generation、稀疏mask/禁用点、BOX无primary及完整尺寸。
I/Q/P日志分别保存输入、实际素材请求和实际输出；逐像素核对颜色、时序、身份、
全部效果标记和素材key，逐core拍核对commit/退休身份、背压保持及命令阻塞。

16场景全部通过。完整场景核对2440179个输出时隙、960023次有效素材请求，命中
21504个框像素、1184个点像素及960019个贴图像素，fault为0；实际commit为3次。
完整场景核验800×600有效像素，使用W+8、H+4测试光栅；这不是1056×628 VESA
物理时序或HDMI板测。其余40×24/80×64为相同ABI几何下的像素子区探针，不冒充
完整帧证据。最终逐场景计数、完整帧数及工具/源/产物SHA256见机器摘要。

旧overlay/mode_resources/display_scanout/display_mmio分别12/16/17/10份仿真
日志通过，共55份；Python109项通过、1项Windows符号链接权限跳过。未重跑all。

## RED、变异及独立审查

实现前测试因缺失模块编译失败，保留absence RED，不将它描述为已有生产行为失败。
独立审查复现两项实现问题：新RAW先到而素材未就绪时误报fault，core fault发生后
pending记录仍可能生效。修复后保留旧引用/等待匹配SOF，并同步core fault抑制
未证明提交；相同刺激的RED/GREEN及独立生命周期探针均保留。

密集启用夹具曾漏检强制点使能变异；增加record解码oracle、稀疏框/点mask及禁用
primary夹具后，该变异被检出。八项隔离变异全部检出：提前commit、使用实时素材
key、强制点/primary、连续素材错误释放、等待素材误报错、忽略core故障、忽略
generation。所有变异仅在build下运行。独立审查另核对同素材新帧只退休RAW、同帧
RAW或空AVATAR只退休旧素材，以及退休背压期间禁止新命令。

## 综合结果与未完成项

PDS2022.2-SP6.4综合完成：13267 LUT、15475寄存器、0 DRM、6 APM、0锁存器。
core8ns最差setup估计-1.249ns，路径为core busy到组件cmd_ready输出；估计周期
9.249ns（108.1198MHz），未满足125MHz。pixel25ns内部寄存器setup估计+12.426ns；
稳定CDC束6ns约束余量+5.172ns。边界hold估计-2.470ns，reset recovery/removal
最小-0.037ns，不能宣称时序闭合。

13项约束适用，0 error/critical，74项物理I/O未指定警告。顶层5076个组件接口位
超过器件300个物理I/O，本目标用于内部组件综合，不能作为板级top。零同钟端口
预算及输出pad边界影响当前估计；需在内部互连接入后按实际路径重新约束并布线。
工具忽略ASYNC_REG，保留高扇出/常量清理诊断；不宣称物理CDC签核。首次FDC总线
端口选择失败后改为逐总线通配符，失败记录保留，未放宽时钟目标。

462项保护文件和42项其他路线路径保持；旧入口除新增hook外原始CRLF字节一致。
只提交本批16个文件，STATUS中其他路线追加保持未暂存。后续实现素材DDR装载/版本
持有，再把实际RAW身份、像素退休与owner/扫描器联合接入。物理跨master可见性、
CPU/NPU执行、连续视频、布局布线、外部I/O和板测继续分别验收。
