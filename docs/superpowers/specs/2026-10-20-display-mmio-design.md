# F4b 同源显示记录与控制端点

基线`05b1191`，日期2026-10-20。落实已批准全屏设计的F4控制接口；沿用F4a显示引用
所有者，用户已要求继续实施。Windows原生流程，板上F3c镜像保持。

## 地址与记录

Video区域仍为0x20010000/64KiB；采帧ABI1/全部旧偏移和生成头保持原字节。
独立显示子窗口为0x20011000/4KiB，版本0x00010000；最终fabric须先子译码，不能把
该请求送入现有capture端点。相比修改采帧全局版本或把整个SoC一次接入，此方案
允许独立回归和逐项集成。主规格原0x30/0x200显示偏移仅为未发布草案，本批以
`config/video_display.json`发布独立显示偏移，RTL/C从该源生成。

显示记录固定160个小端32bit字/640B，字0位于打包bus低32bit。前32字为头部：
version、bytes、slot、frame、generation、raw_base/stride、width/height、flags、
result_frame/generation、box_mask、primary_index、asset_id/generation/base/bytes/
width/height/stride、avatar_xy0/xy1；字23..31保留零。随后16框，每框8字：
xy0、xy1、5bit点mask、五个xy点。坐标为两个有符号16bit分量，x低/y高。
mode和seq在命令寄存器，MODE提交仅更改二者，记录其余640B必须与active完全相同。

flags为RESULT_VALID/RESULT_EMPTY/POINTS_ENABLE/AVATAR_ENABLE/PRIMARY_VALID的位0..4。
正式记录各模式均要求同帧/代际有效结果；无脸必须mask=0且没有点/主框/素材启用。
RAW/BOX可在素材未就绪时显示，非空AVATAR还要求主框、素材启用、封存素材身份匹配。
素材固定256×256 RGBA、stride1024/262144B，16B对齐且整个分配位于0x82600000..0x82800000。
非空AVATAR素材ready=0时保留pending和shadow租约；发布ready后素材身份/内容须保持至协调reset。
框/头像矩形必须正面积，允许跨边，像素端负责裁剪；无效框/无效点和未启用素材
对应字段须零，保留位须零。不推断真实NPU成功，结果资格仍由CPU后处理负责。

## 控制与事件

0x00/04为version/capabilities，08状态、0c首错、10 IRQ_MASK、14 EVENTS、18 ACK、
1c显示侧slot_free；20 SUBMIT，24 mode、28 seq、2c记录字节数。30..40为active身份，
44..58为保持的commit，5c..64为release，68/6c为reject，70..7c为计数，80支持模式。
100..37f为640B shadow记录，其余地址DECERR。RO写/WO读、非法值和忙提交SLVERR。
SUBMIT仅全字写1新帧/3同帧MODE；AXI B OKAY只表示本地冻结校验任务，非实际提交。

独立AW/W暂存，B/R背压稳定。WSTRB用于普通RW与shadow字节合并；命令/ACK必须全字
或零strobe空操作，未知传输payload先拒绝，禁止部分执行。校验/offer期间禁止修改
shadow/mode/seq，防止跨字撕裂；接纳到F4a后可准备下条shadow，仍需等已有commit ACK。

记录检查头部后逐框检查，期间shadow有显式租约保持；通过才公开到owner，失败保持
reject事件不保留槽。owner实际反馈或退休证明来自后续像素/引用消费者；接纳、commit、
release和拒绝独立可读。ACK位0/1/2分别消费commit/release/reject；任何指定事件不存在
时整次ACK拒绝。release ACK才清显示引用；协议首错只由协调reset清除，IRQ位3为fault。
新事件与ACK的竞态以保持事件和已存在条件处理，不用计数或序号猜测发生了什么。

## 驱动与验证

C驱动通过显式read/write/fence回调保留平台总线错误和排序边界。构造/提交只使用
同源头，先检查版本/能力/忙状态，再写完整记录、mode/seq、执行平台fence，最后SUBMIT。
事件读取期间不自动ACK，调用方在处理完整身份后显式ACK；release不能冒充全局可复用。
平台回调必须提供不可缓存MMIO及真实排序/错误语义，本批不假定CPU或跨master可见性。

先失败测试，再实现生成器、记录校验、AXI-Lite与owner联测、C驱动。覆盖16框/五点、
无脸、资产界限/身份、所有事件/总线背压、AW/W先后、错误/未定义输入、shadow冻结、
同帧MODE、三槽退休/ACK和协调reset。组件综合仅8ns估计，实际像素/DDR/SoC/板测另验。
