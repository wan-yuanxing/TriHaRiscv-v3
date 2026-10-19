# CPU最小片上系统设计（2026-10-19）

用户已选择CPU接入SRAM/总线后按实际系统边界验收。本设计在现有独立CPU工作树实现，不修改共享主工程，不变更现有核RTL和原裸核失败记录。

## 结构和地址

采用本地同步存储总线，而不是将224个CPU端口引出，或提前耦合尚未集成的DDR/Video。六级单发射核复位PC=0，8KiB只读启动窗口跳至0x10000的32KiB SRAM。SRAM统一保存代码/数据，64bit取指读口和带字节写使能的数据口，使用PDS原生块RAM推断，必须核对实际DRM映射。ROM/SRAM初始化文件由ELF生成，硬件和ModelSim使用同一镜像；不使用TB专用写入。RAM不因复位清空，BSS由启动程序清零。相同SRAM字的取指/写入冲突时阻止取指接纳，避免依赖厂商未定义双口冲突数据；FENCE.I后的后续取指可见已完成store。

地址权威为config/soc_map.json，生成Verilog/C/链接脚本。沿用v0.6：ROM 0x0/8KiB，SRAM 0x10000/32KiB，UART 0x10000000，系统信息0x20020000。保留Timer、GPIO、NPU、Video和DDR窗口；未实现访问明确错误完成，不作地址别名。当前固件预置SRAM，ROM跳转启动；尚不是UART动态装载器。

## 协议与观测

取指可连续接纳，每个接纳请求恰有下一周期valid/error。数据总线只保留一个未完成请求，accept独立于CPU请求strobes/ack；完整payload和tag接纳时锁存，响应期间不接纳第二请求。SRAM字节写仅在接纳边沿发生一次，ROM写/未映射/混合读写及维护请求返回错误。无缓存，cacheable属性不创建别名或缓存；不声明FENCE可替代未来DDR完成协议。复位必须同时作用CPU、存储桥和UART，清在途valid/ack，不清SRAM。

UART仅实现TX：DATA+0低字节发送，STATUS+4 bit0可发送；写忙时在已接纳事务内等待，完成表示发送器接纳字节。100MHz/115200bps。系统ID+0只读，EXIT+4写完成状态/读回，CYCLE+8只读。EXIT为本阶段明确的调试接口，后续公共系统寄存器扩展须版本化。top只导出clk/reset/irq、串口TX、done和8位code，不导出CPU宽总线。输入输出仍max2/min0.5ns，setup/hold uncertainty 0.1/0.05ns；不加false path/MCP。此为实际片上系统边界物理验收，未带板级PLL/管脚，不能称板测或可直接烧录板卡。

## 验证与交付

先用自检总线测试观察RED，再实现。覆盖边界/字节/半字/高低64bit lane、背靠背取指、tag、ROM只读、未映射错误、UART忙等待、同时I/D、复位在途。独立期望值核对，不以DUT内部状态作oracle。固件从ROM实际启动并运行SRAM，包含data/BSS、栈、字节访问和错误trap；CoreMark同版本/编译参数重新测实际访存成本，非官方分数或板测。故意损坏数据应被拒绝。

PDS完整compile/synthesize/dev_map/pnr/report_timing，保留源/镜像/工具/约束及输出哈希；检查实际单发射配置和DRM，Slow/Fast setup/hold/MPW及performance一致才称100MHz通过。CPU-only沿用独立核映射，系统总量和存储/总线额外用量分别报告，不能把系统资源称CPU资源。
