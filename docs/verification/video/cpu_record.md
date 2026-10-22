# F4c5a CPU控制路由与真实固件采显

2026-10-22，北京时间，基线`536d8c6`。Windows原生Icarus/ModelSim/GCC/PDS。
本批不操作COM/JTAG/Flash。[机器证据](evidence/cpu_record.json)绑定最终输入、工具、
CPU Git blobs、复制源、生成ROM/ELF/参考、实际回归、综合和独立审查。

## 控制路由

新增`video_axil_decode`，生产可复用的同钟AXI-Lite 1入2出：lane0为ABI2采集
0x20012000/4KiB，lane1为显示0x20011000/4KiB，均使用原生成头。完整地址/PROT/
数据/字节掩码保持，旧ABI1 0x20010000及其他空洞、非字对齐和未知地址本地
DECERR，不产生下游事务；读错误数据0。

AW/W分别缓存，收齐才发布；AW、W分别握手，目标持有到B握手。AR与R独立，
读写各一在途，可并行不同目标。响应背压不重发，非选中端点VALID不能完成请求。
不提供全局fabric、CDC、超时撤回或局部reset取消；reset须与CPU/端点/在途DMA
协调。旧native桥的其他路线未提交MMIO_PREFIX参数保持原字节，当前只用默认
Video前缀，新模块不依赖非默认参数。

独立TB先保存缺模块编译RED，随后118项定向检查通过，含AW/W两种先后、16种
WSTRB、并行读写、1100周期响应保持、下游SLVERR、窗口首尾、旧地址/孔及协调
reset。3项隔离变异检出错目标、过早W破坏保持和错误R目标选择。首个过早W变异
因残留w_sent条件实际上无效；扩成实际违规后被W_HOLD断言检出，汇总期望标签
随真实日志修正，未把无效变异或汇总标签失配记作生产RTL故障。

审查另有64项协议探针，覆盖W未配AW时独立读完成、非选中lane响应隔离、分别
接纳/背压、B等待时独立read miss，以及X/不对齐无副作用；两项复制源变异
分别用live AWADDR改目标和取错B lane，均被指定断言检出。

## 实际CPU与C驱动

CPU仍是原config/cpu_video_fixture.json冻结提交8a2a07cf02ae758131a0235887ea244b16c5a1f4，
仅由共享Git对象库显式导出至build；缺对象失败，无HEAD fallback，不读取CPU
工作树。CPU生产实现尚未合入本目录。诊断固定单发射、关闭MULDIV/SUPER/MMU，
使用仿真32KiB ROM0和32KiB SRAM0x10000，非生产内存集成。CPU intr绑0、轮询，
不能据此宣称PLIC或正式中断路径完成。

真实链为CPU→原native桥→新译码→原采集/显示MMIO→三分支/DMA/唯一共享DDR→
实际扫描/RAW/BOX/AVATAR。固件实际链接未改的video_capture/video_display/
video_frame_pool C驱动。字节内存、RGBA装载和整数像素oracle复用原独立模型。
平台sideband装载素材id7/gen71，仍封存到协调reset；框点是固定非空夹具，
未执行NPU。回调fence在该单在途native路径中使用编译器屏障并依赖每次MMIO
ACK后返回，不证明物理跨master DDR可见性。

启动固件真实触发两次load访问错误（旧ABI1、孔）及一次显示只读寄存器store
错误，检查mcause/mtval/ELF中实际指令PC，再返回；TB独立核对3次native错误。
成功流程CPU分配slot0/1、generation47，实际捕获两帧800×600并核对真实完成
身份、raw/preview CRC、三分支写入。frame_pool经显式固定结果发布seq100 RAW、
101 BOX、102 AVATAR、103 RAW、104第二帧RAW；MODE不释放旧槽，实际release ACK
后软件统计才推进。CPU用实际cycle CSR每次等待3000000个core周期，TB要求
每seq至少480000个已核对有效像素，无测试RPC或伪造生命周期反馈。

最终normal核对5025920个输出像素：RAW3105920、BOX960000、AVATAR960000，
实际三分支写4214400B；2次采集、5次显示反馈、1次联合退休，欠载0。软件
签名确认2帧/3MODE/1release，56次显式检查；driver回调129读/836写/17屏障，
直接事件轮询另计，实际native接纳/回复957785笔含3次预期错误。23728049个
仿真core周期不是CPU性能基准或物理125MHz证明。

坏EOF用例真实CPU检查失败完成、排空和保守引用，0次显示发布。断开的控制
通路实际超时且无成功签名；bad_memory用原native内存模型破坏实际raw字节，
原DDR桥读回核验后报PIPELINE_FAULT，进程非零退出，未篡改像素oracle。
ModelSim原始退出码不能独立判断成功：TB全部断言通过后才写完关闭SRAM签名，
入口同时要求原生退出0、唯一PASS、完整签名、ELF/ROM/工具/源码前后hash。

新采集链首次在ModelSim编译发现旧RTL在使用后才声明rearm_healthy/empty，
Icarus/PDS此前允许；本批仅把完全相同的3行wire声明提前，移除该块后原/新
文件其余bytes完全一致。新TB的proven_seq声明也前移。这是声明兼容修正，
没有改变采集状态机或表达式；受影响capture_rearm 20场景与cpu_axil2120用例回归通过。

审查实际复现Python -O移除assert导致模拟器退出7仍PASS。父测试保留优化模式
RED，然后把两新入口的判据/工具/源/ROM hash和negative签名检查改成显式if/raise。
新增回归证明优化模式仍拒绝非零仿真、ROM篡改和不完整CPU签名；tb/soc全部
10项测试在普通及-O各通过，完整CPU用例在加固后重跑绑定当前入口。

## 综合与边界

译码器89LUT/120FF/0DRM/APM/锁存器，458接口位超过300物理引脚。FDC为core8ns、
同钟输入/输出max2/min0.5ns，5条约束均适用，0 error/0 critical，40条未分配
物理I/O等警告；不设false path或multicycle。首轮总线pattern漏末尾通配导致
get_ports不匹配，入口实际拒绝；改为显式端口/位pattern后综合完成。

单slow corner综合setup估计−3.676ns、hold−1.970ns；reset recovery+6.629ns、
removal−0.263ns。最差setup为rst_ni组件输入pad到AWREADY/WREADY输出pad，含
I/O预算；估计85.6458MHz。工具明确Some Constraints Violated，不能以成功综合
宣称125MHz闭合。没有快角、布局布线、物理CDC、外部AC或新板测。

下一步在正式内部互连与CPU/DDR时钟边界下收敛时序，接生产ROM/SRAM及共享fabric。
全局帧状态仍由CPU维护；真实NPU、跨master物理可见性、连续HDMI与最终FREE
分别验收。当前共用core时钟及core域可背压PIX/EOF仅为数字集成边界。
