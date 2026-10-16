# DDR wrapper 准入契约

状态：独立 `video_ddr_bist` 已通过真实校准、自检和 KEY0 后重测，**正式 AXI128 ddr_wrapper 尚未实现**。证据见 `docs/verification/video/evidence/rx_ddr_bringup.json`；此文不提供跨主端可见性或带宽保证。

规格要求逻辑 128 bit AXI4 DMA、字节地址、INCR、最多 16 beat、4 KiB 拆分，首版每主端读/写各最多一个未完成事务。CPU 负责 fabric 地址、仲裁和排序，Video 负责厂商 DDR IP 与 native 封装。

所选 HMIC_S 参考接口为 256 bit 数据、28 bit 32-bit-word 地址，一拍 32 B、地址增加 8；无标准 WVALID、RREADY、B 通道。WSTRB 高有效。必须缓存完整 native 写命令的数据，并在读命令前为不能背压的返回预留空间。

复用候选：旧工程 `targets/pango676/ddr/axi128_hmic256.sv`、CDC 和相应测试。其合成 B 响应只表示最后 native 数据接纳，不能直接解释为物理 DRAM 错误检测或跨主端可见性已证明。

V015 的必要验证：

1. 原生字地址/AXI 字节地址、低/高 128 bit lane、WSTRB、尾拍、4 KiB 与非法地址。
2. 最后写拍和响应长等待，同主端及另一主端随后的同址读。
3. `ddr_init_done` 前不接纳访问；失锁/校准失败时不继续正常任务。
4. 在途事务不能由局部复位假装取消；协调排空或控制器/主端共同重初始化。
5. 真实校准、BIST、数据/地址模式压力；记录无法检测的物理错误范围。
6. 多主端访问、显示水位优先及最大服务等待，不能只测平均吞吐。

实际容量、频率和器件参数以核对后的板卡/IP 为准；软件仍只访问 v0.6 规划并已验证的地址窗口。FDC/RCF 的层次重绑定和 PHY/PLL 反馈结构必须单独审查。

独立 BIST 的配置为 N3/N2 差分 125 MHz、core 125 MHz、DDR 500 MHz、物理 1 GiB。覆盖低/高各 1 MiB、29 个地址哨兵、8 种全数据模式与 38 个掩码阶段；默认完成 3,014,685 个 256-bit 读比较。高窗口字节偏移为 `0x3ff00000`。它是破坏性测试，未遍历全部 1 GiB，也未证明 AXI128 lane、fabric 或跨主端排序。

每个命令先用 17 拍生成并写满 16 项缓存、预取首拍，再发 AW/AR；缓存使用 LUT RAM，模式生成和读输出各有寄存级。写数据与读期望值均已预备，支持 AW 同拍最早 WREADY、返回不能背压、4 KiB 拆分及 ID/LAST/超时检查。这是有限功能自检，不作为峰值带宽测量。BIST 和控制器通过 KEY0 协调复位；初始化丢失保持失败，不能靠清状态继续旧事务。独立 27 MHz 监测域报告初始化超时、PLL/初始化丢失、PHY/align 错误及 core 停钟，任何错误撤销 PASS。

沿用 `TRV1` 37 字节 UART 包，type 2 的 payload：byte1 flags 的 bit0..4 为 init/busy/done/error/allPLL；byte2 phase、byte3 errorcode；bytes4..7 比较数；8..11 首错 native **32-bit-word 地址**；12..15 首错 256-bit XOR 的**低 32 位**；16..19 低窗口字节偏移；20..23 高窗口字节偏移；24..27 窗口 beat 数；28..31 独立时基 heartbeat。低 32 位 XOR 为零不能排除高 lane 出错。板级保持错误 E0/E1/E2/E3/E4 分别表示 init 超时、init/PLL 丢失、PHY 初始化失败、align、快照停滞；native 错误码见组件源文件。

保护库已通过 ModelSim 编译/展开，但本机厂商 GPLL 模型在 76 ns 因除零中止，未得到真实训练仿真通过。便携板级 TB 使用明确标记的数字 IP 替身，仅验证 wrapper、复位、CDC、UART 与 BIST 控制。
