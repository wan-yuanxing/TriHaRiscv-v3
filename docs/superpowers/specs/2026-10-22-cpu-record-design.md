# CPU控制路由与三模式采显固件设计

用户在536d8c6交付后要求继续执行，沿用已提出的CPU互连与时序方向。本批为F4c5a，
留在Video共享分支、Windows原生、小范围本地提交；不操作板卡或改动其他路线。

主目录尚未合入CPU核，已有CPU桥有其他路线未提交的MMIO_PREFIX参数扩展。本批
保持该文件原字节，不连带提交。采用独立生产AXI-Lite译码器，加冻结CPU数字诊断；
不直接导入整个CPU分支，也不通过两个CPU桥对请求广播。前者可独立验证控制流，
全CPU导入还涉及选型/时序/内存/CDC，广播则不能可靠绑定W与AW目标。

新增rtl/soc/video_axil_decode.v，同钟1入2出，capture为lane0，display为lane1。
地址取原生成头：ABI2采集0x20012000/4KiB，显示0x20011000/4KiB。旧ABI1窗口
0x20010000、其他地址与非字对齐访问本地DECERR，不触发下游。不得误用早期采集
地址。完整地址/PROT/WDATA/WSTRB保留，分别锁存AW/W；两者齐备才发布，允许
任意到达顺序和独立背压。读写各一笔在途、路由持有到响应握手，可并行不同目标。
读miss返回0/DECERR，写miss在收齐AW/W后DECERR。公开VALID/数据在背压下保持，
不得按实时上游地址改选目标，reset需与CPU/端点/在途DMA协调。

真实CPU采用原config/cpu_video_fixture.json冻结提交8a2a07c和显式Git blobs导出，
不读取CPU工作树，不把诊断CPU复制到生产目录。复用未改C capture/display/frame_pool
驱动、原native桥、新译码和video_record_pipeline；CPU轮询，IRQ仍可观察但不假冒
PLIC。ROM/SRAM只为仿真本地模型。测试既有已完成读写顺序，不以fence回调证明
物理跨master DDR可见性。CPU与Video在此诊断共用core时钟；100MHz→125MHz CDC、
生产Boot/SRAM、全局fabric仍待后续。新译码器只综合，不宣称CPU/125MHz整机闭合。

normal由CPU分配两帧800×600，实际三分支捕获后读取真实事件、校验独立CRC常量、
经frame_pool发布完整记录。首帧RAW→BOX→AVATAR→RAW，第二帧RAW；CPU以实际cycle
CSR等待完整光栅，TB逐像素独立检查每个seq至少480000像素。框点为固定夹具，
素材仍平台sideband装载并封存至协调reset，没有运行NPU。坏采帧应保留失败引用且
不显示；断控制、改路由和损坏RGB等隔离反例须实际被拒绝，不能只看ModelSim退出0。

独立译码TB先保存缺模块编译RED，再覆盖AW/W两种顺序、read/write并行、响应背压、
所有WSTRB、错误响应、边界地址与协调reset。固件测试使用原生GCC/ModelSim，每次
独立目录，冻结源码/CPU blobs/工具/模型/生成ROM，TB全部断言通过才关闭SRAM签名。
受影响cpu_axil与新路由、固件和Python测试分别记录，不重复漫无边际all。更新规格/
接口/台账/机器证据，独立审查后限定本地提交，其他dirty及STATUS NPU追加保留。
