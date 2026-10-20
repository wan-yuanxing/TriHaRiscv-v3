# DDR wrapper 准入契约

状态：独立 `video_ddr_bist` 已通过真实校准、自检和 KEY0 后重测；本批新增 `axi128_hmic256` AXI128 桥核心及独立 AXI/DMA 验证目标。SoC fabric、多时钟接入和系统级共享仲裁仍待集成；物理验证以对应批次证据为准，不由组件仿真代替。

规格要求逻辑 128 bit AXI4 DMA、字节地址、INCR、最多 16 beat、4 KiB 拆分，首版每主端读/写各最多一个未完成事务。CPU 负责 fabric 地址、仲裁和排序，Video 负责厂商 DDR IP 与 native 封装。

所选 HMIC_S 参考接口为 256 bit 数据、28 bit 32-bit-word 地址，一拍 32 B、地址增加 8；无标准 WVALID、RREADY、B 通道。WSTRB 高有效。必须缓存完整 native 写命令的数据，并在读命令前为不能背压的返回预留空间。

旧工程 `targets/pango676/ddr/axi128_hmic256.sv` 的 lane/cache 结构作为来源参考，新接口按本工程重新验证；旧 CDC/arbiter 没有迁入。旧版 B 只表示 native 数据接纳，新版增加下述写后核验契约。

## AXI128 桥核心

`rtl/video/axi128_hmic256.sv` 的 `clk` 是 DDR core 用户时钟，当前为 125 MHz；所有上游 AXI 信号须已在此域。不同主逻辑时钟须在统一边界接入经过审查的 CDC，本桥不隐含异步采样。`rst_n` 必须与上游 master、桥缓存和 HMIC 协调，禁止单独复位桥后复用旧 native 事务。

接口为 32 bit **逻辑字节地址**、4 bit ID、128 bit 数据/16 byte strobes，支持 `0x80000000..0x87ffffff` 内的 16 B 对齐、SIZE=4、INCR、1..16 拍且不跨 4 KiB 的 burst。全范围检查后才减 `0x80000000`，向下按 32 B 对齐并转 native word 地址。桥一次拥有一个读或写事务，写优先处理同时提出的 AW/AR；W 可先提出，但桥收到 AW 后才接纳。上半 lane 开始的最大请求占 9 个 native 缓存项。

完整写 burst 收齐后才发 native AW，原始数据与有效字节掩码保持至验证结束。全部写拍接纳后，通过同一独占 native 端口读回全部覆盖范围；只核对本次 WSTRB 有效字节，成功才返回 B OKAY。所有主端必须由上游 fabric 进入这一个桥，不得另有 native 写端在写入与核验之间覆盖数据。OKAY 表示本端口观测到匹配的读回，不表示物理 DRAM 持久化、ECC 或任意旁路写端的可见性保证。

AXI 读数据完整缓存后才输出，RREADY 可任意背压。native AW+首 W、AR+首 R 同拍和连续返回均被验证；native 无 WVALID/RREADY/B 的差异不暴露给上游。

非法地址/参数写按 AWLEN 排空 W 后返回 DECERR，不写缓存或 DDR；非法读返回 ARLEN+1 个零数据 DECERR。WLAST 错误排空 advertised 数量后 SLVERR 并隔离。native ID/LAST/X、核验失配、native 看门狗或曾初始化后的失锁均保持 `fault/fault_code`，协调复位前禁止新任务。上游 WVALID 空隙及 B/R 背压不是 native 超时。

已经提出的 native VALID/地址/ID/长度在故障时继续保持；接纳后按 advertised 长度排空，写用零掩码、读丢弃，再完成相应 AXI 错误响应。native 永不恢复时只能协调复位；不承诺无条件有界错误响应。已完成并受阻的 B/R 保持原内容，不能因后续失锁改变。已接纳 AW 但 W 未收齐时仍接受其余 W；master 停发则同样需要协调复位。

当前 `video_axi_capture` 是该核心与单平面 DMA 的独立板测设计；它不替代 CPU 正式仲裁器，不提供显示水位/QoS 或多主端最大等待保证。详见 `docs/verification/video/axi_capture_bringup.md`。

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

## F4c3a Video局部共享端口

`video_shared_ddr`在原桥前增加采集写/显示读调度器；所有信号已经处于core域。
内部仅一个`axi128_hmic256`，写后读回核验期间不会插入其他native拥有者。
桥本身仍写优先，公平性由新增调度器的完整事务串行化提供；未修改桥字节。

普通竞争交替，urgent读配额默认4、可设1..16；有写等待时达到配额便服务写。
所有界限按对端持续前进下的已完成事务计。输入描述符接纳后注册保持，下游AW/AR
背压不撤回，写等AW握手才传W。owner在B握手或ARLEN+1次R握手后才释放，
响应背压及错误RLAST不能伪造退休。`port_drained`不包含像素缓存或全局所有权。

调度器首因码：1曾上线后失锁，2桥/外部memory_fault，3提前/无主B，4提前/无主R，
5错BID，6错RID，7错WLAST，8错RLAST，9未知描述符，10未知有效transport控制，
11未知B/R负载或已接纳W数据/掩码。错误锁止新grant，已接纳/公开事务继续排空。
wrapper统一fault_code以bit7标记桥错误，其余为调度器码；首个采样错误保持。
合法SLVERR/DECERR正常转发，不独立改变既有桥策略。

组件综合和数字联测见[共享端口验证](../verification/video/shared_video.md)。联测实际
raw扫描release后才复用三槽，urgent固定1；没有生产CPU/NPU fabric、实际水位、
跨master物理可见性或800×600并行吞吐证明，也没有本批新布线/板测。
