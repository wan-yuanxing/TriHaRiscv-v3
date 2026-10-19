# Video 采帧 MMIO 端点

基线`f3c456f`，设计/计划提交`bff38a2`。本批新增同core域的AXI4-Lite控制端点，
连接原`video_three_branch_capture`的请求、accepted/completion和故障接口。
已有HDMI/DDR/三分支板级RTL及目标保持原逻辑；没有迁入CPU工作树或执行新板测。

## ABI与软件交接

基址`0x20010000`，版本`00010000`，能力值7仅表示采帧命令、保持事件和IRQ。
`config/video_regs.json`定义46个寄存器；同源生成`video_regs.vh`和
`sw/include/video_regs.h`，版本指纹防止同版本改变偏移/字段/复位值。
原始JSON重复键在所有嵌套层拒绝，生成与`--check`均失败且不写输出。

软件先使能CONTROL，写slot/frame_id/version影子，再全字写0x20=1。
raw/preview/input地址由公共槽表计算，frame0及32bit回绕允许；软件仍须管理空闲槽。
AW和W独立缓存，AR锁存读值，B/R背压保持；WSTRB按字节生效。非法字段/RO写返回
SLVERR，未映射/未对齐/越界或未实现显示地址返回DECERR。

IRQ_PENDING位0/1/2为accepted/completion/fault。W1C消费邮箱有效位但保留记录，
新事件优先于同拍ACK；IRQ_MASK不丢事件。0x28/2c是frame摘要，0x144/184是完整记录
的frame别名。未知/重复/错身份事件置E1并请求取消；错误首因和历史结果保持。
合法失败可以早于首个accepted像素，成功才要求accepted。晚到故障通过sticky_fault
撤销实时健康，不篡改历史完成数据。

请求一旦提交保持至采集核接纳。当前仍是每个协调复位epoch一次采帧；没有局部
reset/rearm、显示命令、三槽allocator或跨master可见性承诺。ACK不释放槽、不清错误。
完整规则见[设计](../../superpowers/specs/2026-10-19-video-capture-mmio-design.md)和
[接口](../../interfaces/video.md)。

## 自动验证

端点TB以字面地址和独立期望检查351项，包含独立AW/W顺序、请求和响应背压、
字节掩码、非法/未知访问、请求锁存、事件/ACK竞态、中断掩码、首错优先级及复位。
真实core TB运行7场景×3种几何（10×10、30×20、40×30），使用实际三路写DMA、
仲裁器和字节内存，检查guard/stride空洞及独立像素参考。末尾input B暂停及EOF
暂停均阻止完成；失败B排空后才发布失败；首PIX前失败无accepted仍保留原始code03。
协调复位同时覆盖MMIO、core及事务模型，不以局部复位假装排空。

独立规格审查补充22486项边界检查，包含全部16384个对齐区域地址、255个
首PIX前失败码、身份破坏、未知数据、W1C和历史保持，并拒绝五个编译变异。
实现者另拒绝四个变异。ABI生成器12项检查通过；RV32I/ILP32 GCC已实际编译静态
偏移/掩码/输入布局断言，结果为ELF32 RISC-V对象；未执行CPU固件。

独立审查/父任务发现并修正：失败完成后迟到accepted被误接纳、JSON重复键静默覆盖，
以及独立config回归入口遗漏新JSON/头文件的输入哈希。均保留RED/GREEN；config入口
现先检查生成漂移，再运行Python测试。旧focused结果在runner更新后明确作为历史证据。
联测初始将core仲裁错误09误期望为writer06，以及“同拍”故障刺激早了一拍，均为
测试模型修正，保留原失败，不作为生产缺陷证明。

独立质量审查另运行4个随机种子共8708项通道检查，四种几何共28场景、146887字节
核验，拒绝4个总线变异。5个runner及11个builder隔离控制流用例验证失败返回、
PASS标记、跨套件哈希冲突，以及构建前后原文件/复制快照/生成文件漂移；这些用例
使用明确标记的工具替身，实际综合另由下文原生PDS结果证明。

审查复现hash后、copy前变化又恢复的源文件能逃过旧校验，现复制后立即比较哈希，
并在工具版本查询前、实际构建前和最终通过前复核原文件、编译副本及生成文件。
同时统一Windows清单键为`/`，clean正向用例及篡改用例均通过。旧完整回归
`20261019T080551_884741Z`为重启最终验证而主动取消，状态明确为cancelled，不计为通过。

最终完整回归`build/video/regression/20261019T082100_941564Z`通过：33套件、176项
输入、238份仿真PASS日志；Python80项中79通过、1项Windows符号链接权限跳过。
回归结束后再次核对全部输入，最终摘要另绑定所有运行日志的SHA256。
ABI/spec/quality最新审查分别复核63/26/30项当前依赖和246/259/354项产物哈希，
父任务再次逐项确认一致。数值测试源未变的旧审查保留原记录，builder差异另行复验。

## 综合与交付范围

`video_capture_mmio`仅允许组件synth，route/bitstream入口拒绝。当前8ns综合结果为
666 LUT、852寄存器、0 DRM、0 APM；slow setup估计余量+3.298ns。
这是未布线的估计，不是SoC/板级125MHz签核。最终原生综合位于
`build/video/pds/20261019T082100_941645Z`，原文件20项和编译副本16项哈希复核一致。
规格、ABI和质量审查均无剩余实质问题；机器可读汇总、完整回归及逐项哈希见
[capture_mmio.json](evidence/capture_mmio.json)。设计计划的逐步关闭以该摘要为准，
原计划字节保留用于审查输入绑定。

证据中的source_hashes为工具实际读取的工作区字节；新JSON的CRLF在Git中按项目
`.gitattributes`规范化为LF，另记提交blob的SHA256并逐字验证仅有换行转换。
RV32编译探针位于忽略的build目录，作为验证产物绑定，不纳入生产源码提交。

```powershell
python scripts/video/gen_regs.py --check
python scripts/video/run.py --suite capture_mmio
python scripts/video/run.py --suite all
python scripts/video/build_pds.py --target video_capture_mmio --stage synth
```

## 后续集成

CPU现有11bit tag原生数据接口仍须经正式适配器和不可缓存地址译码接到AXI4-Lite；
时钟不同时需要独立CDC边界。共享DMA经单一DDR桥的跨master写后读、CPU访问属性/
屏障、事件到统一三槽状态转换及显示释放ACK均待联调。当前邮箱不能独立宣布
完整SoC INPUT_READY或允许复用PROCESSING/DISPLAYING槽。

继续采多帧还需受控重用采集流水/入口和排空握手，不能用本端点反复写START或
单独复位邮箱来替代。真实CPU执行、NPU推理、共享仲裁带宽和新板测不属于本批证据。

本地交付限定18个Video文件，31项既有CPU/技术报告/规则文件按开始时哈希保留。
提交后再核验HEAD的字节/换行规范化身份、精确文件清单及空暂存区；不push或合并。
