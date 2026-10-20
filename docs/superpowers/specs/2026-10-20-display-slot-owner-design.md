# F4a 显示帧槽引用所有者

日期：2026-10-20；基线 `511e6b5`。依据用户已批准的
[全屏设计](2026-10-19-fullscreen-display-design.md)第5、9节及“继续下一阶段”指示，
本批落实F4中可独立验证的core域显示引用管理。当前板上三模式镜像保持不变。

## 选型与范围

完整SoC一次接入需要CPU fabric、采集多帧rearm、结果/素材ABI同时具备，当前不能
用独立板测代替这些条件。直接扩展静态诊断顶层会混合单帧捷径与正式所有权。
本批采用独立 `display_slot_owner`：先冻结显示侧接纳/提交/退休握手，再接正式
显示ABI/MMIO和总线。它不修改采帧ABI1，不分配显示寄存器偏移，也不复制DDR桥。

该组件只管理显示引用。`slot_free`仅表示没有显示引用，不代表采集/推理引用已
清除；全局三槽分配器必须另行汇总所有消费者。它不证明HDMI像素或DDR事务已退休，
只接纳下游所有者提供的完整退休证明。

## 命令与冻结记录

同一125MHz core域，以valid/ready提交完整记录：新帧或同帧MODE事务、slot、
frame_id、generation、raw_base/stride、mode、seq及参数化context数据。
raw基址必须精确等于公共配置中对应的A/B/C槽，stride固定2400B；frame_id非零，
mode为0/1/2，所有被接纳字段必须已定义。context由调用方先完成同帧结果、框及
素材资格检查；本组件只负责冻结与身份保护，context宽度不是显示ABI。

新帧必须使用FREE槽；MODE必须与当前active的slot/frame/generation/raw/context
完全一致，只能改mode和seq。非法描述符、忙槽和不匹配MODE走独立保持的拒绝通道，
不改变已有命令、活动图或槽引用，也不置致命协议错误。拒绝包含seq与原因。

接纳后立即保留槽，完整下游命令稳定至接纳；单个在途命令在实际commit反馈之前
不能被新提交替换。接纳ACK与实际commit分开，不能因seq数值相同或回绕推断完成。

## 状态、事件与释放

每槽状态为FREE→RESERVED→ACTIVE→RETIRING→WAIT_ACK→FREE。
MODE不改变槽状态，不使原槽进入RETIRING。新帧匹配commit才将旧active变RETIRING，
发布新active，并产生完整保持的commit事件。活动记录保留mode、seq和完整context。

下游commit必须匹配已被接纳命令的mode/seq/slot/frame/generation。错误、未知或
无在途命令的反馈被消费并锁存首个sticky协议错误，不能发布active或释放任何槽。
已公开命令不因错误撤回；正确反馈及退休/ACK继续排空，错误后不接纳新提交。

退休证明包含slot/frame/generation，必须匹配RETIRING槽。允许它与切换到新帧的
匹配commit同拍到达并证明旧active已退休。活动/保留槽的提前退休、错误身份和
重复退休均为协议错误。只有退休证明与软件/上层release事件握手都完成，槽才FREE。
release事件背压保持旧身份；不能复用等待ACK的槽，不能借模式commit充当释放。

各输出事件独立背压。commit事件未取走时不接纳新提交；release事件未取走时
不接纳下一退休证明，避免覆盖。协调复位清除所有引用；不得单独复位本组件然后
复用仍被DMA、bank、素材或像素流水引用的数据。

## 验证与后续

自校验覆盖三个槽、命令/事件背压、MODE三模式、raw/context变更拒绝、槽忙拒绝、
seq回绕、同拍commit/退休、延后ACK、错误/未知/重复反馈和协调复位。
使用独立测试记分板检查保留/释放次序；错误变异须被实际拒绝。
先组件仿真，再PDS组件综合，8ns仅作综合估计；不宣称布线、板测或完整F4完成。

后续F4b发布正式同源显示记录/寄存器与CPU驱动，F4c接全局三槽、采集重武装和
共享fabric。像素域完整记录原子提交、末端实际反馈以及全部引用退休，需要单独
组合验证；真实NPU和素材DDR取数仍依各自契约集成。
