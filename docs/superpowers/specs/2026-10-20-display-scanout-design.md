# F4c3b 显示MMIO与RAW扫描反馈闭环

基线bf6effc。用户已授权继续前一步提出的真实提交/退休适配；沿用Windows原生、
当前Video分支及小范围本地提交。无板卡/COM/JTAG操作，CPU核不是本批前提。

新增独立`display_scanout_link`及`video_display_scanout`wrapper，保留既有显示ABI、
所有者、raw_display和模式CDC字节。相比修改owner内部或一次接全部叠加，本批
显式适配已有事件，便于核验generation/seq与真实RAW引用。wrapper只发布RAW能力
`modes=001`；BOX/AVATAR由现有validator拒绝，不把缺少的叠加路径宣称已接通。

新帧命令锁存slot/frame/generation/base/stride/seq。raw记录保持到接纳，只有
匹配真实raw commit才向owner反馈，命令握手或AXI B不制造commit。按槽保存代际，
旧raw release必须匹配已持有且非active身份；该次替换的旧active引用等对应新commit
反馈消费后才交owner。更早非active引用的延迟release在下一命令OFFER/WAIT_RAW
期间仍须排空，不能与扫描器的旧事件ACK条件形成互等。
owner继续保持release至软件ACK；link的退休握手不代表CPU全局FREE。
raw事件本身不携generation，link按唯一在途命令/按槽账本回填；新代际并不使未
协调reset或任意重复同slot/frame的事件可被识别，必须保持raw既有有序握手契约。

同帧RAW MODE不重复发布raw记录，也不释放槽。通过既有display_mode_cdc保持
身份，pixel消费命令后等raw输出两周期对齐的光栅帧边界，再返回真实提交反馈。
这是RAW到RAW的幂等模式命令，BOX/AVATAR仍未接入。没有声称首次像素的精确时间戳。

adapter一次只保持一条命令，持有反馈/退休直到消费。未知/错身份/无主事件、raw
拒绝或运行错误粘滞fault，停止新命令，保留已发布记录；不伪造commit/retire或
局部reset。独立fault输出由未来平台接收，不改变既有MMIO ABI或合成虚假事件位。
全部core/pixel/AXI/owner协调复位，不能单独清空代际账本。

默认实际几何800×600、stride2400；缩小参数仅供联测扫描同一固定ABI记录的左上
子区，不改变ABI定义。至少一项完整800×600像素验证。独立地址字节模型检查
AR范围/4KiB/身份与完整光栅，slot复用只发生在真实退休后且软件release ACK成功。

验证包括接纳不等于commit、命令/反馈/退休背压、同RAW模式无重复raw提交、代际/
seq关联、三槽循环、跨代际同frame/slot、错误保守保留、reset、完整像素和C三槽库
真实事务回放。C回放允许等待真实事件，禁止注入Q/T模拟提交或退休；本机C与RTL
对照不是RISC-V执行，也不证明采集/NPU/物理DDR可见性。综合只报告8ns/25ns组件
估计和实际约束诊断；无布线、全局fabric或新板测结论。
