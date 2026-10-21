# F4c4a 完整记录与叠加像素退休组件

基线d079e75；继续已授权的BOX/AVATAR接入。Windows原生、当前Video分支，限定本地
提交，保留旧RTL/ABI/C字节和其他路线现状，无COM/JTAG或板卡操作。

本批先增加独立display_record_pixels。相比直接改RAW闭环或把DDR素材DMA一次并入，
先复用display_mode_cdc传递完整640B记录，再解码原display_overlay，可单独核验
记录原子性、每请求素材身份和旧像素流水排空。后续再接素材装载、RAW实际身份与
owner，不能把独立组件能力当作video_pipeline已公布BOX/AVATAR。

core命令包含mode/slot/frame/generation/seq及5120bit记录。调用者须已通过冻结的
record_guard完整校验；组件另检查已知值、头部身份/几何一致性。payload在CDC完整
锁存，pixel只在SOF且实际输入raw slot/frame/generation相同后应用。素材未就绪时
AVATAR等待；若匹配的新RAW已先到，透传原图且保持旧引用，下一匹配SOF才可应用，已就绪但身份错误锁存fault。新记录作用于该SOF首像素，不从下一像素
才起效。源身份由未来扫描器提供，本批测试模型提供，不从core延迟反馈冒充像素身份。

解码16框、80点、primary和贴图矩形；每个avatar请求的asset id/generation随9级
寻址流水传递，禁止直接使用已切换的active key给旧请求贴标签。原overlay保持13级，
末端另加pad寄存，输入边沿n对应输出n+13。源slot/generation、模式和seq同步对齐。
仅当新首像素退出末端且无已观察故障时，才经原CDC反馈commit。反馈受背压保持。

core在实际commit被消费后更新本地active引用；若raw身份改变或旧素材身份不再使用，
发布旧引用的pixel_retire记录并保持至消费。raw_changed是像素流水排空贡献，不能
代替raw扫描器的DMA排空/release，更不能直接交CPU全局FREE。相同素材跨新帧持续
持有，不制造素材释放；同帧AVATAR转RAW只退休旧素材。新命令须等本地退休消费。

素材接口是每拍固定响应的同步provider；调用者必须保存所有仍被引用的版本直到
退休，不自行覆盖。该组件无缓存/DMA、无全局素材分配器。现有一次封存cache保持
不变，动态bank替换/DDR加载后续单独验证。

未知/不一致命令、provider身份错误、像素/overlay或CDC错误粘滞fault并停新命令，
故障前已证明反馈/退休仍保持；未证明新首像素不产生commit或释放旧引用。全部域
须协调reset。测试覆盖640B锁存/毒化源、全16框/80点、模式/代际/素材切换、首像素、
ACK背压、退休保持、缺失素材、故障/复位、不同钟比与完整800×600数值oracle。

组件综合按core8ns/pixel25ns，scalar首级CDC例外与稳定束6ns；接口按同钟寄存边界
给零预算。综合/布线/板测分别报告；不宣称CPU/NPU、真实DDR可见性或正式三模式闭环。

故障传播以各域已寄存/同步观察的fault为准，core故障双级同步后禁止pixel接纳及未证明commit。末端n+13同拍出现的后续输入故障不追溯撤销n输入已正确输出的首像素证明；当前退出像素本身错误仍禁止该commit。
