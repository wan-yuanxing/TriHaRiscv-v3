# 三分支 HDMI 单帧板级集成

用户在25482e8完成后授权继续下一步。本批沿用已确认的800×600约60.32Hz
输入、双400×300显示及320×320 UINT8 BGR NCHW，不改变模型或CPU选型。
在现有video/windows-bringup工作树执行，保留其他路线改动和旧预览恢复镜像。

## 方案与边界

采用独立`video_three_board`目标及`video_three_engine`：复用已验收板级接收、
128帧启动保护、入口FIFO/寄存器、HDMI复位分离、DDR桥和显示组件，替换采集
核心为三分支。直接改旧预览目标会破坏恢复基线；等待CPU合入会阻塞独立板测，
因此选择独立目标。正式CPU MMIO、共享fabric/写后读可见性及三槽allocator
仍另行验收；本目标固定请求slot A、frame_id=1、preprocess_version=1。

流程：DDR就绪后请求一次，接纳accepted事件，等待good EOF及全部三路B退休的
成功completion，再串行读回raw、preview、input，最后提交预览供双窗显示。
raw/preview须匹配采集端CRC；input没有独立流式平面CRC，读回报告实际字节数
和CRC，借助已冻结数值oracle/已知测试图验证，不能把自算CRC称为任意桌面的
独立数值校验。三路读回均使用公共生成地址，禁止旧诊断0x873...地址混入。

实速集成补充：三路descriptor接纳后，arm还须等NCHW顶部补零完成并可接收有效
像素。最早到达的帧不能与整段顶部补零串行等待叠加，入口FIFO保持2048字。

为input读回增加CRC reader的`CHECK_EXPECTED_CRC=0`参数模式，默认1保持旧目标
语义；该模式仅取消最终expected比较，未知数据、描述符、ID/RESP/LAST、超时
和在途排空规则保持。input按3*(PAD_TOP+有效高+PAD_BOTTOM)行读取，每行有效
宽字节，跨越真实NCHW行步长，默认307200B；不把小尺寸仿真的对齐空洞计入CRC。

## 健康与诊断

失败立即锁存并阻止读回/显示提交，仍让已公开AXI事务排空；KEY0是协调复位。
HDMI锁定/DDR初始化丢失不得局部复位FIFO或撤销AXI。已发布capture事件是历史
事实，板级健康丢失则撤销实时PASS。原125MHz/8ns及CDC 6ns束约束不放宽。

UART保持TRV1 37B、type6/7格式，新增type8轮询：六个32bit小端字段依次是
capture frame_id、preprocess_version、有效input像素数、input写字节数、
input读回字节数、input读回CRC。type8是板级诊断，不等于CPU INPUT_READY。
所有包使用统一健康标志/阶段/错误码及heartbeat；错误不能显示旧PASS。

## 验收

1. 默认CRC reader回归不变，新checksum模式实际读回的CRC/count/错误/背压检查。
2. 新engine用实际HMIC字节内存检查三路数据、公共地址、读回先于显示、错误
   禁止提交和复位恢复；input对独立双线性/BGR/padding oracle。
3. 新board数字替身检查启动暖机、KEY0保留HDMI配置、三类UART、失钟/失锁/
   source fault撤销PASS；默认800×600按40MHz不可停顿输入检查FIFO容量和吞吐。
4. 独立规格/质量审查及完整回归冻结当前输入；PDS先综合再布线/位流，分别报告
   资源、内部时序、外部AC未签核。只有真实Program/Verify/UART和用户画面/KEY0
   观察才能关闭物理验收；没有硬件记录则保持待验。
