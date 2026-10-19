# CPU与Video控制路径验证

基线`704b076`，设计/计划提交`c9efc5f`。本批连接原生CPU数据协议与现有Video
AXI4-Lite端点，不修改CPU分支、采帧核心、DDR桥或板级生产目标。

## 组件边界

新增`rtl/soc/cpu_native_axil.v`，同钟单事务，保留完整11bit tag及已对齐字节数据/
掩码。独立AW/W背压和响应门控，CPU ACK/error注册返回。Video窗口之外、可缓存、
非法混合访问及维护命令在本地错误结束，不触发外设。既有采帧请求、邮箱及IRQ
ABI保持不变。复位必须与CPU/端点/在途DMA协调；无局部取消、超时撤回或多帧重采。

## 实际CPU诊断

固定CPU提交`8a2a07c`，完整对象ID和显式blob清单由`config/cpu_video_fixture.json`
冻结。每轮从共享Git对象库导出至build副本，不读取CPU工作树的未提交文件，不向
生产Video分支复制CPU实现。该诊断需要本地存在固定对象，缺失时失败且不换版本；
普通Video组件回归和综合不依赖这个对象。CPU源许可及适配记录随快照保存。

测试ROM0/8KiB、SRAM0x10000/32KiB为数字测试内存；测试完成写普通SRAM签名，
没有增加退出MMIO。使用已安装GCC和ModelSim、按哈希读取PDS原语模型。
真实CPU经适配器和现有MMIO，连接小几何实际三分支采帧、DMA、仲裁及字节内存。
轮询、中断/W1C、采帧失败、load/store访问错误均由固件及独立测试模型检查。
单源IRQ直接接CPU仅用于此诊断，不是正式PLIC或多中断优先级证据。
该CPU会把外部IRQ锁存到MIP；固件先ACK Video，再显式清除CPU挂起位后返回，
并分别检查外设电平和CPU pending。CPU本身当前发tag0，非零tag由桥接组件TB穷举。

固定CPU还存在CSR读使能边界：普通主发射指令也会使能CSR读，`lw`立即数0x144与
SIP地址相同，可在IRQ为高时打开MIP更新缓冲。实际波形确认外设IRQ已低，但首次
清MIP会与旧缓冲0x800合并；连续清两次仍可能保留该位。诊断固件在Video W1C读回
后清MIP、间隔8条NOP、再清一次并检查最终MIP0。独立单NOP间隔实验也确认缓冲
排空机制；单/双发射均不再出现pending0的额外重入。全部失败和trace保留。
该序列仅适配固定CPU诊断，CPU侧应在正式SoC集成前处理CSR读资格；本批不修改CPU。
早期“外设写尚未完成”的推测已被波形排除，不作为最终根因或共享排序结论。

## 运行入口

```powershell
python scripts/video/run.py --suite cpu_axil
python scripts/soc/run_cpu_video.py --suite all
python scripts/video/build_pds.py --target cpu_native_axil --stage synth
python scripts/video/run.py --suite all
```

`cpu_native_axil`仅允许synth，8ns组件约束，不生成板卡位流。保留失败/变异和
工具/原文件/复制快照哈希。实际PDS运行
`build/video/pds/20261019T090954_423039Z`通过：64 LUT、132寄存器、0DRM/0APM，
8ns估计slow setup+5.870ns。原文件9项、复制快照5项及PDS执行文件哈希一致；
父审计从冻结清单重建Tcl，另绑定7项脚本/版本/日志/消息审查/报告/结果产物。
这是组件未布线估计，不替代CPU/SoC或外部I/O时序。

## 已完成验证

端点独立TB通过2120用例、全部2048tag、15种非零字节掩码、8组协调复位。
实现者拒绝12个实际编译变异；规格审查另拒绝6个，质量审查运行2126用例并
拒绝4个额外变异，包含1024～2048拍通道暂停和4096拍响应等待。计数属于各自
独立审查，不相加冒充不重复覆盖。

父任务实际`--suite all`位于`build/video/cpu_video_firmware/20261019T092739_970045Z`：
7项冻结/非法路径/配置漂移/副本篡改/生成头检查，6个真实CPU用例（单/双发射各自
轮询、中断和首accepted前失败）通过；断开的控制路径和实际DMA内存字节损坏均
返回2且无PASS。独立规格任务另实际运行`20261019T092837_016704Z`，并解析每次
native接纳/ACK、每轮2个精确load/store错误及ELF符号PC、实际中断进入和MRET MIP0。

成功帧逐字节覆盖raw1800、preview450、BGR NCHW396，共2646字节，保留stride/
plane间隙保护。EOF暂停101拍、最后input B暂停161拍均阻止提前完成。失败帧无
accepted、raw/preview均0，但已完成72个input预填零字节；全部B排空后才发布code03，
不能把失败槽当作INPUT_READY。质量审查另将真实MMIO VERSION返回值改错，真实CPU
报bad00001并以非零退出，证明固件控制判据有实际拒绝能力。

每轮CPU证据绑定26项原文件与副本、固定提交的33个Git blobs、9项工具/模型和
110项产物；生成的ELF/ROM/仿真命令文件在消费前后核验。源hash与复制hash须立即
相等，原A→副本B→原A的竞态已有隔离RED/GREEN；测试几何严格限制实际30×20、
上2/下1行补零。JSON重复键、陈旧生成头和固定Git对象缺失均拒绝。

ModelSim2020.4对正常finish和fatal的原始退出行为不能单独判断成败。入口使用
每次独立目录中、全部TB断言通过后才写完关闭的SRAM签名决定退出，再同时要求
原生退出0、PASS标记及主机签名/ELF核验；两类反例仍须实际非零拒绝。原始退出
码与日志保留，不把工具返回0当成功。机器可读来源和最终回归见
[cpu_video_control.json](evidence/cpu_video_control.json)。

最终完整Video回归`build/video/regression/20261019T090954_414639Z`退出0：34套件、
180项输入、239份仿真PASS日志；Python80项中79通过、1项因Windows符号链接权限
跳过。父任务逐项核对当前源文件、工具、复制快照和审查产物，并归档520份日志哈希。
规格与质量独立审查均通过，规格审查还将真实CPU采集的2646字节导出，与独立
Python/OpenCV参考逐字节对照。交付限定19个文件，31项其他路线文件保持起始哈希；
仅作本地提交，原三分支板级源与`704b076`一致。

## 后续边界

正式SoC需继续提供地址译码、生产ROM/SRAM、共享DDR fabric及写后读、槽所有权、
PLIC/CDC和受控多帧重用。CPU自身100MHz后布线未收敛，本组件综合不能替代CPU或
SoC时序。未进行新的Program/Verify或画面验收，不声称NPU推理或共享INPUT_READY。
