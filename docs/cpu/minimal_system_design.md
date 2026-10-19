# CPU最小片上系统设计（2026-10-19）

用户已选择CPU接入SRAM/总线后按实际系统边界验收。本设计在现有独立CPU工作树实现，不修改共享主工程，不变更现有核RTL和原裸核失败记录。

## 结构和地址

采用本地同步存储总线，而不是将224个CPU端口引出，或提前耦合尚未集成的DDR/Video。六级单发射核复位PC=0，8KiB只读启动窗口跳至0x10000的32KiB SRAM。SRAM统一保存代码/数据，64bit取指读口和带字节写使能的数据口，使用PDS原生块RAM推断，必须核对实际DRM映射。ROM/SRAM初始化文件由ELF生成，硬件和ModelSim使用同一镜像；不使用TB专用写入。RAM不因复位清空，BSS由启动程序清零。相同SRAM字的取指/写入冲突时阻止取指接纳，避免依赖厂商未定义双口冲突数据；FENCE.I后的后续取指可见已完成store。

地址权威为config/soc_map.json，生成Verilog/C/链接脚本。沿用v0.6：ROM 0x0/8KiB，SRAM 0x10000/32KiB，UART 0x10000000，系统信息0x20020000。保留Timer、GPIO、NPU、Video和DDR窗口；未实现访问明确错误完成，不作地址别名。当前固件预置SRAM，ROM跳转启动；尚不是UART动态装载器。

## 协议与观测

取指可连续接纳，每个接纳请求恰有下一周期valid/error。数据总线本地ROM/SRAM访问为单拍同步响应流水，可连续接纳并逐拍返回data/tag/error；accept独立于CPU请求strobes/ack，响应无反压。UART写单独锁存字节与tag，等待发送器接纳时阻止后续请求，保持顺序。SRAM字节写仅在接纳边沿发生一次，ROM写/未映射/混合读写及维护请求返回错误。无缓存，cacheable属性不创建别名或缓存；不声明FENCE可替代未来DDR完成协议。复位必须同时作用CPU、存储桥和UART，清在途valid/ack，不清SRAM。

UART仅实现TX：DATA+0低字节发送，STATUS+4 bit0可发送；写忙时在已接纳事务内等待，完成表示发送器接纳字节。100MHz/115200bps。系统ID+0只读，EXIT+4写完成状态/读回，CYCLE+8只读。EXIT为本阶段明确的调试接口，后续公共系统寄存器扩展须版本化。top只导出clk/reset/irq、串口TX、done和8位code，不导出CPU宽总线。输入输出仍max2/min0.5ns，setup/hold uncertainty 0.1/0.05ns；不加false path/MCP。此为实际片上系统边界物理验收，未带板级PLL/管脚，不能称板测或可直接烧录板卡。

## 验证与交付

先用自检总线测试观察RED，再实现。覆盖边界/字节/半字/高低64bit lane、背靠背取指、tag、ROM只读、未映射错误、UART忙等待、同时I/D、复位在途。独立期望值核对，不以DUT内部状态作oracle。固件从ROM实际启动并运行SRAM，包含data/BSS、栈、字节访问和错误trap；CoreMark同版本/编译参数重新测实际访存成本，非官方分数或板测。故意损坏数据应被拒绝。

PDS完整compile/synthesize/dev_map/pnr/report_timing，保留源/镜像/工具/约束及输出哈希；检查实际单发射配置和DRM，Slow/Fast setup/hold/MPW及performance一致才称100MHz通过。CPU-only沿用独立核映射，系统总量和存储/总线额外用量分别报告，不能把系统资源称CPU资源。


## 真实路径驱动的第二轮物理修正

首轮最终Slow setup −1.206ns；UART busy解码到pad和核内BTB到PC分别为−1.206/−1.202ns。UART串行输出改为直接连接现有移位寄存器最低位：stop/移入1使idle自然为1，不新增周期；原独立线级接收器检查启动/数据/停止/忙等待保持正确。CPU RTL不改。依据核内8.806ns布线/2.030ns逻辑延迟，将CPU层次约束到已知容量足够的完整时钟区(0,64,150,199)，ROM/SRAM保留外部合法位置；启用现有端口寄存器打包。此为有实测依据的物理对照，不提前声称时序改善；时序FDC字节不变，必须重新运行全流程。


## 本地访存等待修正

首版控制器在RAM输出之后另寄存返回数据并插入响应空泡，CoreMark多约30%周期。先加入单拍响应断言观察旧控制器RED，再复用同步RAM本身的输出寄存器，使data/tag/error对齐于接纳边沿；连续写/读32字独立oracle与tag检查通过。删除原32位地址、32位写数据、读状态/字节控制及三态FSM，仅为慢UART保留8位payload/等待位。没有给CPU新增流水级，没有改变存储地址或引入组合ack反馈。必须以新CoreMark和物理结果评估其实际收益。


## 预测查询反馈的逻辑修正

第二轮真实核内最差路径PC[7]→BTB比较→全表命中归约→fallback向量选择→全表最高优先掩码→数据选择→PC[24]，Slow setup −0.478ns，15级，逻辑2.362ns/布线7.782ns。改为两个匹配集合分别求最高优先掩码，再按原if条件选择结果，避免在命中归约之后串接另一套优先归约。仍复用同一独热AND/OR数据选择器，不增加预测流水级/历史状态/CPU周期，也不缩小表。

等价关系：任意二态匹配集合E/U，原highest(E if any(E) else U if upper-allowed else E)等于highest(E) if any(E) else highest(U) if upper-allowed else highest(E)。匹配由原过程if产生，未知比较仍按非命中；fallback仍为过程if，保持PC[2]的原X语义。reset/重复tag/最高编号优先/upper-word/BHT/RAS/LFSR逐拍组件对照与真实坏输出负例必须通过；整核按序WB/store/异常与三seed、CoreMark两模式回归后才能用于物理验收。syn_keep仅保留两个组合掩码的边界，无新增状态。原vendor保持字节，派生清单更新SHA。


## 第四轮仅局部前端布局

第三轮仅剩三个RAS index CE和一个BTB训练CE违例，WNS−0.183ns。前端综合4264LUT/3811FF，无DRM/APM；将其放在同一CPU时钟区左侧48/64列（0,47,150,199），名义LUT容量约8400，保留约一半余量。执行部分仍受原完整CPU区域约束且不排斥与前端共用剩余容量，RAM/ROM保持可用区域。原生报告需确认子区域展开，实际最终setup/hold/MPW判定；不能用容量估计或布局估计代替时序。该轮RTL、初始化镜像、10ns时序预算及PDS seed1与第三轮一致，仅改变局部区域约束，不预先声称频率收益。


## 完整tag比较的共享与分组

seed1/seed2均剩约0.18ns反馈违例，PC查询高扇出/32位carry比较反复进入关键路径；工具扇出复制和前端局部区域未形成更好结果。保持完整32bit tag和原预测器策略：精确PC与upper-word查询共享[31:3]的29bit比较，分别比较[2:0]；写入命中仍检查完整32bit。查询高位和写tag比较按三bit一组（恰好六个比较输入）进入LUT，再归约组结果，syn_keep防止重新串为整字carry链。无新增状态、无地址截断、无额外预测周期。

四态等价：组结果按AND归约与原logical equality相同，任意已知不等组为0，其余未知则X；原过程if仍把未知比较当非命中。新增直接oracle覆盖全部32个位的相等、不等、X、Z和已知不等伴X，29/32两种宽度共160组/320输出检查；原完整BTB/BHT/RAS/LFSR逐拍对照和真实坏输出拒绝仍需通过。整核三seed、系统访问异常和同一SRAM CoreMark复测，再完整物理实现；不将比较级数或资源估计当100MHz通过。


## RAS逐条目早期写地址

比较树物理仍由RAS动态写地址/条目CE限制，保留完整tag继续共享两查询相同的[31:3]与[1:0]共31bit，仅bit2独立判断。没有把低位当常量，PC不截断。原分组等值oracle扩展29/31/32三宽度，共160输入组/480输出检查。

RAS把已确认call的real_index+1和预测call的候选索引提前计算，对各条目独立判断后再由原晚到push控制使能。特别保留已确认return与预测call同时发生的原优先顺序：使用已确认return索引、写预测return-PC载荷；新增定向重叠用例，原版先PASS，再改写。指针更新仍用原if链，payload表达式不变，保持四态if语义和每个栈条目/指针逐拍一致。删除旧动态写入和无用循环变量，不新增寄存器或周期。最终仍由完整物理报告判定，当前不能称100MHz通过。
