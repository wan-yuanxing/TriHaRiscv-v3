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
其余42项原构建输入和全部8ns/6ns约束，第三轮种子4已满足最终内部时序，
种子4–9的最终报告和数据库均已归档。最终slow setup/hold为+0.112/+0.026ns，
fast setup/hold为+2.966/+0.020ns；16704LUT、17059寄存器、9.5DRM、7APM。

最终布线的15组只读专项报告与结构审计均通过：139管脚、68同步链，所有束端点
覆盖、slow/fast最大延迟及本地同步链setup/hold均合格，原设计与报告哈希不变。
工具未输出独立max-skew表，仅记录派生arrival spread，不宣称独立skew签核。
原始结果为`build/video/pds/20261019T124544_168568Z/result.json`，专项核验为
`build/video/raw_board_timing_audit/constraints/20261019T124544_168568Z/result.json`。

镜像`0cd4a546804b`已于2026-10-19通过PG2L100H/00602899识别及易失JTAG
Program/Verify；未写Flash。串口6/9/8已确认三路读回合格、raw全屏扫描增长且欠载0。
持续记录位于`build/video/raw_board_trace/20261019T130620_474086Z`。首轮源图CRC与
四角黄金图不同，用户要求重新采帧，该轮不计入图像验收。随后用同一镜像重新
Program/Verify，新raw/preview/input CRC分别为33bac95a/679ff89c/1f56fc1e，
均匹配既存四角黄金值。用户确认单幅800×600全屏、四角和白边框完整；实体KEY0
后heartbeat从581归1，三路CRC再次匹配黄金值，用户确认全屏四角及白边框仍完整。
随后源端换普通桌面，第二次单次KEY0后heartbeat从247归1，用户确认完整全屏桌面
已恢复，无黑屏、窄条或裁切。

最终持续记录共706个有效包，其中验收采用相邻epoch3/4/5，共495包，489个健康
完成状态。三个阶段分别连续稳定288.002/121.001/77.000秒，均超过60秒；三路
读回保持一致，input全部307200B校验完成，type9扫描和读行数增长、欠载0。

| 阶段 | raw CRC | preview CRC | input CRC | 完成扫描数增长 |
| --- | --- | --- | --- | --- |
| 四角图基线 | 33bac95a | 679ff89c | 1f56fc1e | 142→17332 |
| 四角图KEY0后 | 33bac95a | 679ff89c | 1f56fc1e | 168→7225 |
| 普通桌面KEY0后 | 05c0c426 | fd1dae0b | c7cc686e | 167→4691 |

接收记录已正常关闭，板卡保留全屏桌面镜像。机器验收结果为
`build/video/raw_board_acceptance/result.json`，关联原始UART、时间戳、用户回答、
实际Program/Verify、最终布线和黄金图；父证据见[evidence/raw_board.json](evidence/raw_board.json)。
F2独立全屏静态单帧板级验收完成。CRC比较不代表逐字节转储，也不替代任意桌面的
独立数值oracle；MODE、叠加、正式CPU ABI/共享fabric、连续采帧和外部HDMI AC
签核仍未完成。下一阶段为F3人工框/头像及MODE功能键。
