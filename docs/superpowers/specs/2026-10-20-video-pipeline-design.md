# F4c3c 采集、共享DDR与显示多帧闭环

基线869a028。继续已授权的RAW端到端组合，Windows原生、当前Video分支、本地
限定文件交付。旧RTL、ABI及生产C库字节保留，无COM/JTAG/板卡操作。

新增`video_pipeline`显式wrapper：采集ABI2接开启REARM的三分支核，采集写和
`video_display_scanout`读共用唯一`video_shared_ddr`。采集/显示各保留独立AXI-Lite
控制口；不安装CPU全局fabric，不把两端点旁接成有歧义的64KiB译码。core同钟，
pixel沿用真实raw CDC。源输入是可背压core PIX/EOF流，不冒称物理HDMI连续流。

生产成功几何固定800×600/stride2400、preview400×300、320×320 BGR NCHW；仅
失败探针可缩短高度，不能更改采集宽度或假装支持可变显示ABI。显示仅RAW。
独立三类fault/错误码与IRQ输出留给平台，不合成旧MMIO故障位，不隐式局部reset。
urgent作为显式输入；联测固定1，真实水位生产者仍未提供。

相比继续分别验证或一次引入CPU/NPU/HDMI，本批把现有组件按正式尺寸组合。
软件通过现有capture/display/frame_pool C API控制；本机C进程以R/W/F和只等待
条件的仿真RPC读取真实RTL响应。C接到真实采集完成后调用validate，独立比对CRC，
成功/三路B退休后才交frame_pool；再由测试提供空检测结果的计算完成前提。
显示反馈/退休来自实际扫描，事件ACK成功后才全局复用旧槽。不是离线预期事件回放，
但仍非RISC-V执行、真实NPU图或物理DDR可见性证明。

默认成功场景至少四帧0/1/2/0轮换：旧图扫描时采新槽，第二次显示commit/release
保持未ACK时采第三槽，确认无FREE可分配；再消费真实事件、复用旧槽。一次同RAW
MODE只改变seq，不增加采集或raw提交。采集accepted/completion双ACK后显式REARM。
禁止CAPTURING直接present、错误后自动重试/释放。失败场景覆盖坏EOF与native
存储损坏触发真实桥写后核验错误，C应保留引用、拒绝REARM和新分配。

native模型按实际地址存储数据、检查全部有效写字节/护栏及读回；32字节打包存储，
只在有效native读拍生成数据，避免大数组在每core拍重算。数学oracle独立定义三路
像素布局与数值；源EOF CRC由Python/标准CRC另算，C再算raw/preview CRC。输出
光栅逐像素、同步与blanking核对；旧显示租约上的capture写或释放后读立即失败。

通过显式filelist、双时钟组件综合、受影响回归及独立审查交付。完整尺寸数字并行
证据只适用于所列时钟/延迟模型，不替代物理带宽、真实不可背压源、全局fabric、
Cache/fence、路由/外部I/O时序或板测；BOX/AVATAR和真实NPU仍待后续接入。
