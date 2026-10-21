# F4c4e 正式显示 MMIO 与采显三模式

基线28f7ec9。用户“继续”批准上一阶段提出的正式MMIO和采显链接入。Windows原生，
留在当前Video分支，小范围本地提交；不操作COM/JTAG/Flash，不改ABI配置及C驱动。

选择在既有video_display_mmio的唯一owner之后直接复用display_record_link、
raw_display和video_record_renderer，新增video_display_record；不串联第二个
owner，不改写整套控制端点。既有地址0x20011000、640B完整记录、事件与ACK保持，
modes公布111，素材ready/key来自真实DDR缓存。先验证再发布，mode_only不重发RAW，
反馈及退休沿用上一批双证明；MMIO影子记录在CHECK/OFFER期间锁定，cmd_data租用
owner冻结副本到feedback消费。素材装载仍为平台sideband，不新增软件寄存器。

video_display_mmio新增默认关闭的EXTERNAL_HEALTH参数及可选健康/故障输入、
故障输出。旧实例默认完全保持原行为；只有新组合打开健康检查。在线且无下游
故障才接受SUBMIT或向owner预留槽；外部故障锁存至协调reset，以现有FAULT事件、
STATUS bit6和ERROR_CODE=0xf0报告。owner自身协议错误保持原优先级/错误码。
故障后的ACK和读操作仍可消费历史事件；已提交前的CHECK/OFFER可保持锁定至
协调reset，不能凭故障自动回滚引用。新组合同时门控素材load的valid/ready，
已接纳装载及已公开AXI必须排空/协调reset，不撤销历史结果。

新增video_record_pipeline复用既有三分支捕获MMIO/引擎和原唯一shared_ddr，
将新显示组合接入原读出口，RAW与素材共享此出口，捕获写端仍受原调度器控制。
既有video_pipeline及其RAW-only目标不变。新目标输入仍为已跨到core的可背压
PIX/EOF；本批不把它冒充物理不可背压HDMI入口或完整CPU/NPU fabric。

测试先保存新模块缺失和旧MMIO缺健康参数的编译RED；健康检查定向测试当拍故障、
CHECK/OFFER中故障、历史ACK及粘滞FAULT；直接MMIO小几何测试真实扫描/素材和三模式。
采显链用Windows原生C执行既有capture/display/frame_pool驱动，与真实RTL MMIO
双向握手。两帧800×600由实际PIX/EOF捕获，检查三分支写入、CRC、同帧三模式、
真实图像/框/点/头像、mode_only、旧槽双证明和release ACK。NPU结果是显式固定
测试夹具，不声称执行模型。失败场景拒绝坏EOF与数据错误的捕获资格，无显示发布。

数值oracle独立预计算，RAW从同一字节存储返回，RGBA从真实素材地址读取；保留
输入/工具/产物哈希、RED/GREEN与定向变异。重跑旧display_mmio/display_scanout/
video_pipeline及Python/config检查。两新目标分别综合、逐项检查约束适用性，
core8ns/pixel25ns；报告实际setup/hold与资源，不以工具退出成功宣称125MHz闭合。
CPU仍是全局帧/graph所有者，跨master物理可见性、布局布线、物理CDC、连续HDMI、
运行中素材替换和板测仍独立验收。
