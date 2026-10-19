# CPU片上系统接口 v1

当前目标为`triha_minimal_soc`，顶层采用外部提供的100MHz同钟clk/reset/irq和UART TX、done/code。板级PLL、管脚和下载是后续独立目标。地址权威为`config/soc_map.json`，运行`python scripts/soc/gen_config.py --check`核对生成定义。

| 地址 | 实现与完成语义 |
|---|---|
| 0x00000000–0x00001fff | 启动只读窗口；跳至SRAM入口，写访问返回错误 |
| 0x00010000–0x00017fff | 32KiB同步统一SRAM，代码/数据，字节写使能 |
| 0x10000000 | UART TX DATA，低字节有效；完成表示发送器接纳，不表示停止位已发送完 |
| 0x10000004 | UART只读STATUS，bit0为发送器可接纳 |
| 0x20020000 | 系统只读ID，0x54524801 |
| 0x20020004 | 调试EXIT，写低字节置done并保存code；读bit8=done、bit7:0=code |
| 0x20020008 | 同钟32位周期计数器，只读，复位清零 |

UART为8N1，100MHz除数868，约115207bps。UART只支持TX，无RX装载协议。系统EXIT不是正式NPU/Video任务完成寄存器。其他地址，包括保留Timer/NPU/Video/DDR窗口，均错误完成；没有地址截断别名。

取指每拍可接纳一个64bit对齐字读取，接纳后下一周期valid/error与数据配对，valid无反压。数据口地址为LSU已对齐的32bit字地址；本地存储可逐拍接纳，ack/error/tag与同步读数据同拍返回，返回没有反压。UART写锁存一个完整字节及tag，在等待发送器时阻止新请求，因此后续访问不能越过它。不存在从ack组合生成accept的回路。

SRAM写只在接纳边沿发生一次；数据端口读前写输出在store完成时不作为读数据使用。I口与D口同一64bit字写冲突时抑制I接纳，避免使用厂商双口冲突的不确定返回；已接纳的旧取指不能被追溯修改，软件修改代码后需FENCE.I。没有缓存，取指flush/invalidate不需要清理存储副本；数据cache-maintenance请求明确错误完成。

reset必须协调作用于CPU、本地fabric和UART；它清除在途valid/ack和UART等待，保留SRAM内容，启动程序负责清BSS。当前ROM和SRAM由同一构建的初始化镜像装入，不支持运行中独立重置CPU并继续旧UART/DDR事务。外部irq按当前同钟接口接入，板级异步中断必须另加同步边界。

| 验证入口 | 范围 |
|---|---|
| `python scripts/soc/run.py --test memory` | 总线协议、lane、边界、tag、串口、连续读写和复位 |
| `python scripts/soc/run.py --test runtime` | 真正ROM→SRAM启动、data/BSS和UART |
| `python scripts/soc/run.py --test coremark` | 同版本5次短RTL测量，保留不足10秒警告 |
| `python scripts/soc/run_access_faults.py <runtime目录>` | 整核取指/读/写访问异常，经真实串口核对 |
| `pwsh -File scripts/soc/run_sram_native.ps1 -FirmwareRunDirectory <固件目录>` | 实际DRM综合网表、原生模型、全地址/lane及损坏负例 |
| `pwsh -File scripts/soc/run_route.ps1 -FirmwareRunDirectory <固件目录> -PhysicalProfile compact` | 完整PDS系统100MHz多corner物理实现 |

每次运行独立保存输入/镜像/工具/输出哈希，终态由`scripts/soc/review_route.py`复读核验。CPU资源单列，SRAM/ROM/总线/UART和IO另列；不能把系统总量称CPU-only。组件仿真、整核RTL、综合网表仿真、后布线STA和板测各自报告。
