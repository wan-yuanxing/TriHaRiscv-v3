# 三分支 HDMI 单帧板级集成

基线25482e8，设计/计划26a265a。独立目标`video_three_board`复用既有HDMI接收、
128帧启动保护、复位分离、入口FIFO/寄存器、DDR IP/桥和双窗显示；旧预览目标
及`video_preview_board_33e1b8242053`恢复包保留。固定slot A、frame_id=1、版本1。
CPU MMIO、共享fabric、跨主端可见性及三槽分配器不包含在本目标中。

## 数据与完成顺序

同一帧写800×600 RGB888 raw、400×300 RGB888 preview、320×320 UINT8 BGR NCHW
input。地址由公共配置生成：raw82000000、preview82160000、input82800000。
good EOF及全部三路B退休后才允许引擎显式读回；桥自身的逐burst校验读发生在
采集期间，是写响应契约的一部分，不能误判为过早启动引擎读回。

引擎依次检查raw/preview CRC，读input全部307200B并报告CRC/字节数，再提交
preview给左右400×300窗口。input reader设置`CHECK_EXPECTED_CRC=0`，仅取消
最终expected比较，四态数据、描述符、ID/RESP/LAST、超时及排空检查保持。默认
reader参数为1，既有目标仍要求expected相等。小尺寸验证读取每行有效宽字节、
跳过stride空洞，完整读取三平面的上下补零。

input读回CRC不构成任意桌面的独立数值证明。已知图的独立oracle及冻结张量
身份另验。`capture_complete`是历史组件完成，后续健康丢失仍撤销实时PASS；
引擎`port_drained`仅表示采集写口，不能用于推断正在读回/显示的整个端口可复位。

## 集成修正

实速测试复现NCHW顶部补零尚未完成、输入帧已选中造成入口溢出：source2852、
core802、FIFO2048，input处于第39行补零。新增case29先保持补零B响应，旧核心
以`armed before input padding retired`失败；现在三路描述符接纳且NCHW可收
有效像素后才arm。保留2048字FIFO、125MHz和5秒超时，没有用增大FIFO掩盖启动
问题。完整40MHz候选流修正后FIFO峰值33，三路2107200个有效字节逐字节匹配
独立oracle，实际input写入内存的307200B匹配冻结OpenCV图3 SHA256
`959f1f661aaccc3194e33a9b2916e87d477a6fe752287f004324977016733c09`。

接收端一开始遗漏桥校验读响应的数字模型也会阻塞写入；该失败保留为模型错误，
未用来证明上述生产缺陷。最终实速模型实际保存W写入的字节并返回校验R。
本测试模拟标准光栅的候选像素/元数据，不模拟外部HDMI模拟采样或真实DDR训练。

UART三类包共用健康状态。独立审查复现晚到type8故障仍使旧preview资格为真；
测试先RED，修正为type6/7/8共同连续健康后缀，任一类型的故障/重启都使旧成功
失效。三分支资格还要求同一次任务的raw/preview/input CRC保持稳定。

独立审查另复现TX配置故障仅屏蔽指示、引擎仍提交显示的问题。新增KEY0前的
故障注入先RED，再把sticky board_error经两级core同步器送入引擎取消路径，
已公开事务继续排空，不复位本地所有权。UART仍优先报告板级e5/e6等原因，
引擎内部将同步后的板级不健康记为外部source fault。新增约束仅排除新同步器
第一级跨域D路径，第二级和全部既有8ns/6ns约束保持计时。修正后板级数字替身
六个场景通过，包括故障发生于采集完成但尚未提交显示的区间及KEY0恢复。

## UART与板测入口

TRV1包仍37B：4B magic、32B payload、1B异或校验。type6/7兼容原捕获/显示字段。
type8在type/flags/phase/error后跟七个小端uint32：

| 字段 | 默认完成值 |
|---|---|
| capture_frame_id | 1 |
| preprocess_version | 1 |
| input_pixels | 76800 |
| input_written_bytes | 307200 |
| input_checked_bytes | 307200 |
| input_ddr_crc | 实际张量CRC |
| heartbeat | 自由时钟心跳 |

`physical_three_branch_readback_verified`要求三类连续健康的新记录、raw/preview
源/DDR CRC相等、两次input读回信息相同、扫描/读行数继续增长。另一个字段
`physical_three_input_numerical_verified`保持false，只有已知源图的独立数值
对照才能关闭。LED0心跳、LED1 DDR就绪、LED2完整读回/显示通过、LED3错误。

```powershell
python scripts/video/run.py --suite three_board
python scripts/video/run.py --suite all
python scripts/video/build_pds.py --target video_three_board --stage bitstream
python scripts/video/package_board.py --target video_three_board
python scripts/video/program_board.py --target video_three_board --start-server
python scripts/video/read_board.py --port COM12 --seconds 60
```

Program只写易失配置，并执行Verify；不写Flash。KEY0应保留HDMI配置，协调复位
DDR/入口/采集/读回/显示并重新采一帧。真实Program/Verify/UART、画面及KEY0
记录须独立保存；数字替身、综合或内部布线时序均不替代物理验收。

## 当前自动验证记录

冻结源码的完整回归`build/video/regression/20261018T130850_501612Z`已通过：
32套件、167项当前输入哈希、235份仿真PASS日志；Python共68项，67通过，
1项因Windows符号链接权限跳过。规格及质量审查均无未关闭的实质问题，
父任务复核了两轮审查的213项输入/产物哈希。

首轮PDS运行`build/video/pds/20261018T125545_862866Z`的六个种子4–9均未满足
最终slow setup要求，最佳WNS为−0.171ns，不能用于正式下载验收。该版本综合为
16713 LUT、17029寄存器、9.5 DRM；该资源数不代表布线通过。原始最后一个种子
的归档程序未赶上PDS清理，保留归档失败记录；六个种子的最终CSV结果仍在。
后续构建仅在全部输入及8ns/6ns约束保持一致的前提下尝试新的实现设置，
最终内部时序、Program/Verify、已知图三路CRC及实体KEY0结果分别记录。

## 最终布线与现场验收

保持44项源码/构建输入和全部FDC不变，第二轮仅调整PNR种子、并行数及两项
50ps保持优化目标。`build/video/pds/20261018T134303_455118Z`的种子14通过，
六个种子的最终报告/数据库均已完整归档。最终综合仍为16713 LUT、17029寄存器、
9.5 DRM；125MHz内部slow setup/hold为0.000/+0.066ns，fast为+3.013/+0.052ns。
建立时间余量很紧；通过的是当前约束下的内部STA，不代表额外PVT余量或外部AC签核。

最终网表结构审计核对139个管脚、68对既有同步器及新增板级故障同步器。
15次报告查询包含11个有效束、3组本地同步器及全局补充查询；所有必需端点覆盖、
约束类型及slow/fast路径检查通过。PDS没有独立MaxSkew汇总表，仅记录各位实际
数据路径到达时间差；没有据此新增reset recovery、外部AC或模拟MTBF结论。

下载包为`build/video/releases/video_three_board_89c2e860fde4`，位流SHA256为
`89c2e860fde4e3146a3a26ab793e310e8720fd6b328742220a0562a38ab158be`，
对应同名Verify掩码一起保留。PG2L100H/00602899识别、易失Program和Verify成功，
未写Flash。初次画面不是指定测试图，用户确认后保留原记录，再加载同一位流重采；
该初次记录不算已知图数值通过。持续UART首次启动受Windows脚本策略阻止，改用
项目既有`-Command`调用方式后启动；没有改系统执行策略。

正式记录`build/video/three_board_trace/20261018T141625_923210Z`共279包、两个epoch。
按键前连续健康115994.167ms；实体KEY0后心跳239→1，先记录两个未完成状态包，
随后160个稳定包连续健康159000.179ms。所有稳定样本无错误/overflow，显示欠载0，
扫描及读行数持续增长。raw/preview源与DDR CRC分别为`33bac95a`/`679ff89c`；
input读回全部307200B、CRC为`1f56fc1e`，均与独立四角图参考精确匹配。
用户分别确认初次及单次KEY0后左右两幅图的四角标、白边框完整；标记至确认期间
未执行JTAG下载。串口已正常关闭，板卡保持本三分支单帧镜像。

机器可读证据为[evidence/three_board.json](evidence/three_board.json)，绑定58项源码
及27项结果/记录引用。真实板测是已知图32bit CRC对照，未转储完整物理张量，
也未运行NPU推理。CPU MMIO/fabric、跨master可见性、三槽所有权及连续视频仍待集成。
