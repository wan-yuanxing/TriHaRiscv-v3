# F4c4e 正式显示 MMIO 与采显三模式

2026-10-21～22（北京时间），基线`28f7ec9`。Windows原生Python/Icarus/GCC/PDS；本批没有操作
COM/JTAG/Flash。[机器证据](evidence/record_mmio.json)绑定源码、工具、结果和审查。

## 实际链路与所有权

`video_display_record`复用原`video_display_mmio`内唯一owner，直接连接原
`display_record_link`、`raw_display`及`video_record_renderer`。新组合替代独立
组件的外部owner，避免重复所有者。MODES公布7，素材ready/id/generation来自
真实DDR缓存。地址0x20011000、4KiB窗口、640B记录、事件/ACK及三个C驱动不变。
完整影子记录在CHECK/OFFER锁定，owner冻结记录租用至反馈消费；mode_only不
重发RAW扫描。扫描器commit和实际首输出commit须联合成立；旧RAW引用须收齐
扫描器release与像素退休，再向owner送一次退休，release保持到软件ACK。

`video_record_pipeline`复用原ABI2采集MMIO、三分支捕获及唯一共享DDR端点，
将显示端替换为新三模式组合。旧`video_pipeline`目标继续RAW-only。新源仍是
已同步core域、允许背压的PIX/EOF；数字光栅1056×628不代表物理HDMI入口。

MMIO的`EXTERNAL_HEALTH`默认关闭，仅新组合开启；当拍offline/fault即阻止
SUBMIT和OFFER预留。下游fault粘滞，以既有FAULT、STATUS bit6、ERROR_CODE=0xf0
报告，owner协议错误优先。读和历史ACK仍工作；CHECK/OFFER可保持锁定至协调
reset，不自动回滚引用。新组合同时门控素材load的VALID/READY；已接纳load、
已公开AR及既有反馈保持。单bank素材封存到协调reset，平台旁带装载，不新增
软件寄存器。此处只证明Video引用，CPU仍负责全局帧/graph和最终FREE。

## 回归与反例

```powershell
python scripts/video/run.py --suite record_mmio
python scripts/video/run.py --suite record_pipeline
python scripts/video/run.py --suite display_mmio
python scripts/video/run.py --suite display_scanout
python scripts/video/run.py --suite video_pipeline
python -m unittest discover -s tb/video -p test_*.py
python scripts/video/build_pds.py --target video_display_record --stage synth
python scripts/video/build_pds.py --target video_record_pipeline --stage synth
```

初始RED保存旧MMIO缺EXTERNAL_HEALTH参数的编译失败，以及两个新组合缺失的
编译失败；不是行为RED。早期RED助手还尝试运行未生成二进制，unable-open是
测试工具错误，单独说明。首轮采显TB残留调试计数名导致编译失败，删除过时字段
后重跑，无生产RTL修复。直接测试最终增加素材未就绪全过程监测，任何提前
owner预留都会失败，避免仅检查瞬时CHECK状态。

直接MMIO有6个健康场景及normal/异钟比/asset_wait三个80×64实际显示场景。
通过真实总线写/读/ACK发布，验证冻结影子、素材等待、5次commit、2次release及
3次scanner新帧commit；字节内存、实际扫描器、DDR素材和整数oracle逐像素核验。

采显联测由Windows本机C执行未改动的capture/display/frame_pool驱动，RPC只
传递实际RTL总线回复和事件，没有伪造生命周期反馈。normal实际捕获两帧
800×600到slot0/1、generation47；检查raw/preview/BGR NCHW三路写入及CRC。
第一帧seq100 RAW→101 BOX→102 AVATAR→103 RAW，第二帧seq104 RAW；每个seq
必须核对至少480000个有效输出像素。素材id7/generation71来自0x82600ff0、
262144B RGBA，1025个burst，并检查实际素材退休贡献。bad_eof和corrupt场景
保持失败捕获引用，不发布显示。框/五点为固定非空测试夹具，没有运行NPU。

最终6个健康场景累计1008次检查，3个直接MMIO显示场景核对122880个有效输出
像素。完整normal采显场景通过：2次采集/2条捕获记录、5次owner反馈、1次联合
退休和1次素材退休；核对RAW 1920000、BOX 480000、AVATAR 480000，共2880000
个有效输出像素。三分支实际写入4214400B，软件检查1928次，129读/836写/
17次可见性回调/7次事件等待，均使用实际RTL回复。可见性回调只证明测试边界
调用顺序，不证明物理DDR跨master可见性。RAW新帧提交仅2次，素材装载1025个
burst，显示欠载和综合fault为0；bad_eof/corrupt均无成功捕获或显示发布。

受影响回归display_mmio 10场景、display_scanout 17场景和旧video_pipeline
3场景通过；Python110项中109通过、1项Windows符号链接权限跳过，三份公共
配置/ABI生成检查通过。本批未重跑完整all，不以受影响回归替代完整工程验收。

父任务4项隔离变异分别删除不健康SUBMIT拒绝、强制素材就绪、错误公布MODES及
破坏退休generation，均被指定断言检出。独立审查另有3项入口变异，覆盖当拍
故障门控、素材VALID及READY双向门控。独立164+667次健康探针核验默认关闭时
忽略未知可选输入、AW/W缓冲后当拍故障/离线、故障后保留预留与历史组合ACK、
owner错误优先；素材探针确认新装载阻止和已公开AR保持。最终审查无未关闭
实质问题，原始探针、变异、各次最终结果和工具哈希均由机器证据绑定。

## 综合与未完成范围

| 目标 | LUT | FF | DRM36K等效 | APM | core8ns setup估计 | pixel25ns setup估计 |
|---|---:|---:|---:|---:|---:|---:|
| video_display_record | 26254 | 35278 | 68 | 10 | −2.090ns | +11.549ns |
| video_record_pipeline | 34480 | 42299 | 69.5 | 12 | −3.337ns | +11.128ns |

两目标均0锁存器，最差hold估计−2.470ns；pixel→core稳定束+4.934ns，core→pixel
+5.047ns。显示组合最差core路径为core_reset_n输入到load_ready输出，采显组合
为rst_ni输入到src_ready输出，均含组件I/O预算；不能将top之间WNS差直接当作
内部优化幅度。工具明确Some Constraints Violated，估计core频率99.1080和
88.2068MHz，125MHz尚未闭合。综合是单slow corner估计，fast表为空，不宣称
快角或布局布线时序通过。

每个目标26条约束均适用，含两时钟、4条scalar首级例外、12条稳定bundle延迟、
8条I/O预算；未切整个异步clock group。constraint_check为0 error/0 critical，
显示组合124 warning、采显组合161 warning，均含未绑定物理I/O等诊断；综合
日志另有逐位清理和ASYNC_REG等诊断，以原日志为准。组件接口1519/2215位
超过300物理I/O，没有板级管脚或可下载位流，不能当作上板目标。

下一步在正式内部互连/板级wrapper下处理健康、ready及边界路径，继续core125MHz
时序收敛；CPU执行、真实NPU结果、跨master可见性、物理CDC、连续HDMI吞吐、
运行中素材替换及上板均须独立验证。本批原生C联测不等于CPU执行或物理可见性。
