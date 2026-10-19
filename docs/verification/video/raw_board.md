# F2 raw 全屏单帧板级集成

基线 `d9933dd`。独立目标 `video_raw_board` 复用冻结三分支采集、HDMI初始化、
128帧启动保护、协调复位及DDR桥/IP，校验三路后提交raw原图。旧三分支双窗
engine/top和F1 raw_display保持字节不变。该目标只显示静态单帧，KEY0重采；
MODE、叠加、正式SoC共享fabric与连续采集属于后续阶段。

## 数据路径与完成条件

固定slot A、frame_id=1、预处理版本1。800×600 RGB888 raw位于0x82000000，
stride2400B；400×300 preview位于0x82160000，stride1200B；320×320 UINT8 BGR
NCHW input位于0x82800000，307200B。good EOF和三路写响应全部退休后，依次
检查raw/preview CRC并读回全部input，再向raw_display提交raw_base/RAW_STRIDE。

输出保持40MHz、1056×628扫描；有效区800×600一对一显示原图，无双窗、缩放
或裁切。raw扫描每行150个128bit beat、每扫描600行，双bank实际覆盖完整原图。
raw_display的非法描述符仍通过非致命拒绝接口报告；固定记录的板级调用方将
拒绝记为0x69错误。错误保持首因，已公开的AXI/native事务仍保持并排空。

KEY0只协调复位采集、DDR和显示，保留已初始化HDMI链路。板级监督故障仍通过
两级同步送入引擎取消路径；不能清空在途事务来掩盖故障。

采集AW到桥之间增加49bit保持寄存，隔开burst计数/仲裁与桥描述符接纳逻辑。
W/B直连；仲裁器在AW进入寄存后继续持有owner直至B退休，因此写口排空不能
提前成立。故障不清除已接纳AW；DDR失去就绪时保持，协调复位才清除。

## 串口诊断

TRV1格式仍为37B，115200 baud。轮转次序6→9→8：6为raw/preview计数和CRC，
8为input读回。9的七个uint32字段为frame_id、commits、completed_scans、
underflows、read_lines、fifo_peak、heartbeat。type9明确区别于旧双窗type7。

`physical_raw_fullscreen_readback_verified`要求最新连续健康6/9/8后缀，各类型
至少两个新样本；raw/preview源与DDR CRC一致且保持，input全部307200B读回
及CRC保持，扫描/读行数增长、欠载0。600×completed_scans≤read_lines≤
600×(completed_scans+1)+2，覆盖正在扫描的一帧和下一次首两行预取。心跳必须
按uint32模数前进，倒退/重复、故障、重启或另一目标的记录均不能沿用旧成功。

本字段是独立板级读回/扫描证据。任意桌面的input CRC不能代替独立数值oracle，
也不能代替现场检查完整画面、四角及白框。

## 验证入口

```powershell
python scripts/video/run.py --suite raw_board
python scripts/video/run.py --suite all
python scripts/video/build_pds.py --target video_raw_board --stage bitstream
python scripts/video/package_board.py --target video_raw_board
python scripts/video/program_board.py --target video_raw_board --start-server
python scripts/video/read_board.py --port COM12 --seconds 60
```

仅易失JTAG Program/Verify，不写Flash。编程前自动核对PG2L100H/00602899、
冻结来源、位流与同名验证掩码。现场图像和实体KEY0结果单独记录。

## 当前证据

当前27个引擎场景包括三路独立数值oracle、CRC/ID/LAST/未知数据/超时、公开事务
保持、复位恢复、非法raw记录、显示阶段AR/R故障。板级数字替身6场景通过，
逐像素验证270个缩小光栅、27000像素；每次协调复位切换源内容，并独立检查
raw/preview及补零BGR input CRC。数字模型强制前端元数据、不模拟真实DDR训练。
F1另有800×600连续完整光栅逐像素证据，不能将缩小板级测试单独称作全尺寸板测。

6项包测试和独立审查通过。审查复现并修正了异目标故障未撤销raw资格、心跳
倒退跨epoch混用两项问题。检查点ed8a779的完整回归通过36套件、190项输入、
311份仿真PASS日志；Python85通过、1项Windows符号链接权限跳过。后续AW时序
修订仅改变raw_engine、对应TB及run.py用例数，其余187输入哈希一致，run.py其余
字节也一致。当前受影响raw_board套件重新通过27引擎场景及板级测试，共28份仿真
PASS日志；独立14场景另核对49bit字段、AW/W/B所有权、响应数量及排空，无遗留
问题。这是完整回归基线加受影响套件验证，不是修改后再次完整重跑。
父核验53项本批来源、725份日志哈希、两轮审查产物和35项保留文件
（31项其他路线文件及4项旧板级/F1来源）。
证据见[evidence/raw_board.json](evidence/raw_board.json)。

首轮PDS种子4–9均未满足最终内部setup，最佳为−0.178ns；综合16706LUT、
17022寄存器、9.5DRM、7APM。首轮所有最终种子报告已归档，不能下载其失败结果。
第二轮采用10–15及50ps保持优化，保留43项输入和8ns/6ns约束，仍全部失败。
根据两轮最佳路径同为DMA burst_beats→bridge base_q/CE，新增AW保持寄存；RED
测试已在未加寄存的实现上复现不能隔离接纳。第三轮仅改这一RTL及布局设置，保持
其余42项原构建输入和全部8ns/6ns约束，当前在种子4–9并行布线。
下载及现场验收尚未开始，不以综合网表结构检查代替布线时序或物理板测。
