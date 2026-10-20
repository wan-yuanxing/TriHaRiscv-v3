# F4b 同源显示 ABI、AXI-Lite 与 C 驱动

基线`05b1191`，设计见[display-mmio](../../superpowers/specs/2026-10-20-display-mmio-design.md)。
当前为独立组件，尚未连接实际CPU/fabric、像素域提交和全部引用退休生产者。

## 发布接口

`config/video_display.json`发布独立显示ABI1：子窗口`0x20011000..0x20011fff`，
640B/160字记录，前32字头部、随后16框×8字。`gen_display_abi.py`严格锁定
版本语义和JSON类型，生成`video_display.vh`及`video_display_abi.h`；旧采帧ABI1、
旧配置和头不变。最终fabric必须对显示子窗口单独译码，不能原样送进capture端点。

每个字为小端uint32，字0对应bus低32bit；xy为x低16/y高16，有符号端点。
`RAW_BASE/STRIDE`精确绑定对应公共帧槽/2400B，800×600固定几何。正式记录要求
RESULT_VALID且结果frame/generation一致，无脸标志必须与零框mask一致。所有保留字、
无效框、无效点和未启用素材字段要求零；最多16框、每框5点，矩形必须正面积，
跨边矩形由像素端裁剪。素材固定256×256 RGBA、stride1024/262144B，整个分配
须在`0x82600000..0x82800000`且16B对齐；64bit中间和避免地址回绕。

非空AVATAR要求主框、素材启用和匹配封存身份。素材ready=0保持pending/shadow租约，
ready发布后身份和内容必须保持至协调reset；modes输入是稳定构建能力。RAW/BOX无需
等待素材，合法无脸AVATAR也不访问素材。640B完整context交F4a，不是DDR指针。

shadow窗口为相对`0x100..0x37f`；控制和事件地址见公共JSON与主规格11.3。
`SUBMIT`全字1新帧/3同帧MODE，B OKAY仅表示本地冻结校验任务。校验检查头部后
逐框进行，完成前禁止改shadow/mode/seq；owner接纳后可以准备下条shadow，已公开
命令仍独立保持。MODE必须保持整条记录，仅mode/seq改变，不释放当前槽。

EVENTS位0/1/2/3为commit/release/reject/fault。ACK全字位0/1/2消费对应事件，
任何指定事件不存在则整次SLVERR，不消费其他位。release ACK才让F4a显示引用FREE；
不代表采集/NPU引用清除。fault只能协调reset清除。错误访问、RO写/WO读、未对齐、
越区、未知payload、忙命令均返回适当SLVERR/DECERR且不部分执行；普通RW支持WSTRB。

拒绝码：01未知记录；10版本/长度/帧槽/raw/几何；11 flags/结果身份；12框/点/保留；
13素材参数/范围；14模式能力/素材身份。F4a拒绝1..6仍按既有约定，E1/E2/E3为
sticky协议错误。已有命令和合法反馈继续排空，错误不会取消公开引用。

## 驱动与可复现入口

```powershell
python scripts/video/gen_display_abi.py --check
python scripts/video/test_display_driver.py
python scripts/video/run.py --suite display_mmio
python scripts/video/run.py --suite display_slots
python scripts/video/run.py --suite capture_mmio
python scripts/video/build_pds.py --target video_display_mmio --stage synth
```

C驱动使用显式read32/write32/fence回调，所有回调0表示本次I/O完成成功；平台负责
不可缓存映射、AXI错误和真实排序。提交先读版本/能力/忙状态，再按字序写640B、
mode/seq、执行fence，最后SUBMIT；任一回调失败不再发布。事件读使用局部完整副本，
中途失败不改变调用方结果，也不自动ACK。调用方处理完整身份后显式ACK，release的
fence/ACK必须由全局所有者正确安排。`init_record`产生有效无脸模板，只有调用方已
确认本帧后处理成功且无脸时才能直接提交；该模板不证明实际推理成功。

现有Vivado附带MinGW GCC6.2实际编译/执行驱动自检，逐一注入每个I/O回调失败；
真实驱动产生163条写事务，通过AXI-Lite回放到实际RTL并校验完整命令和实际反馈。
xPack GCC15.2交叉编译为RV32I/ILP32对象；没有运行RISC-V CPU，也没有验证物理fence。
工具可用`TRIHA_HOST_CC`和`TRIHA_RISCV_GCC`覆盖，无WSL或新工具安装。

## 验证状态与边界

数字10场景通过：三模式、完整记录/16框/五点、素材/代际/边界拒绝、未就绪pending、
独立AW/W、B/R背压、strobe/错误访问、shadow复用、ACK原子失败、首错排空、
协调reset与真实C写事务回放。旧display_slots13场景、采帧MMIO两组数字联测通过；
Python106项，105通过/1项Windows符号链接权限跳过。五个关键RTL变异均被实际断言检出。

首轮取字函数隐式引用外部record，Icarus连续赋值未随record变更更新，导致素材头
校验错误；失败日志保留。改为显式record参数后全部场景通过，不以替换模型绕过。
最初C工具缺少进程内运行库路径导致编译失败；补充子进程PATH后实际执行，未改系统PATH。

交付审计发现新显示JSON为CRLF，而仓库检出规则为LF；原始字节hash生成的头在
重新检出后会漂移。先加入配置LF断言并实际失败，再仅将新JSON规范为LF并重生成
两个头，JSON对象与全部宏定义相同，仅注释hash改变。受影响数字/驱动、Python、
五变异和综合均重新验证；旧采帧JSON/ABI保持原字节。保存RED/GREEN及前后副本，
提交时另核对新配置/生成头的原字节Git对象与clean过滤对象一致。

## 综合与等价优化

首轮构建`build/video/pds/20261020T035943_562996Z`虽完成综合，但8ns约束下setup
估计为-51.451ns，不能视为时序通过。5120bit完整context不等比较被映射为约2560级
线性进位链；保留该次报告和原始源码。仅把F4a的比较拆成32bit组并保留组边界，再
OR归约，不增加周期或改变协议。44组逐周期对照覆盖7/128/513/5120bit并比较43个
对外信号；独立190522组四态向量另验已知差异与X/Z共存、相等加X及拒绝优先级。

最终综合`build/video/pds/20261020T041944_395036Z`：10853 LUT、16038寄存器、
0 DRM/APM、0锁存器；core8ns寄存器路径估计setup +1.591ns、hold +0.671ns。
PDS明确把`syn_keep`转换为`PAP_KEEP`。这仅是组件综合估计，未做I/O时序、布线或
新板测；组件目标拒绝route/bitstream，既有板级镜像保持。56项其他冻结来源字节
一致；F4a owner是唯一有明确前后hash及等价证据的来源例外。

## 独立审查与交付

独立审查新增1595组逐字段校验、7个MMIO场景、441次C回调失败和256组ACK组合；
实际原生C产生的含框事务再次回放到RTL，7个针对性变异均由指定断言检出。独立审查
无未关闭发现，两项修复均保留前后证据；57条命令、114项审查产物、244项冻结文件及
当前来源/工具/外部引用hash由交付审计逐项核对。

最终映射网表保留160个比较分组，159组16个carry单元、1组10个，组内最长16；
整个owner直接carry链最长50。仅owner模块的13937节点/14625边保守组合图检查
无环或多驱动；双输出LUT依赖按已安装厂商模型的INIT逐输出确定，不能扩大为完整
分层顶层图证明。12条常量探测loop提示、未约束I/O/管脚数量及高扇出提示均保留
说明；本目标仅组件综合，不能据此签核板级实现。

机器摘要见[evidence/display_mmio.json](evidence/display_mmio.json)，绑定正式三套件、
Python、C原生执行/RV32I编译、变异、综合、审查及新配置检出字节检查。仅本地交付
25个文件，31项其他路线文件保持起始字节；不将旧板测证据改记为本批板测。

## 集成边界

共享DDR/CPU正式集成、实际像素提交、全部引用退休证明、连续视频、真实NPU及新
板测仍未完成。当前板上仍为已验收F3c镜像。F4c将继续实现统一三槽状态/分配、
CPU/fabric子译码和跨master写后读，再接实际commit/retirement生产者；显示侧FREE
不得被上层误当成全局可重用。
