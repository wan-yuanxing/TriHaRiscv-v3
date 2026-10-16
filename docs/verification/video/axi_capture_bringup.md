# AXI128 DDR 与单平面 DMA 验证

日期：2026-10-16。基线 `ff9284a`。本批目标为可复用 AXI128 桥、RGB888 打包和行式写 DMA，以及相同生产组件的合成 raw 图样端到端自检。真实 HDMI 帧 FIFO/CDC、preview/input 三分支、正式 CAPTURE_DONE 和 CPU fabric 不在本批完成范围。

## 文件与来源

- `rtl/video/axi128_hmic256.sv`：core 域 AXI128→native256，写后 masked readback 再 B。
- `rtl/video/rgb888_packer.sv`：24 bit RGB 按 R/G/B 字节打包，跨16 B拍保留 spill，行末 keep。
- `rtl/video/video_write_dma.sv`：带步长的单平面 descriptor、完整 burst 缓存、4 KiB/行边界、B 完成和错误排空。
- `rtl/video/video_axi_capture_bist.sv`：独立坐标图样源、地址/掩码 probes、raw 读回与 guard 检查。
- `fpga/pg2l100h/rtl/video_axi_capture_top.sv`：已板测 DDR 物理壳的独立目标，共用提取后的 `video_ddr_snapshot_cdc.sv`。native BIST 目标同样使用该 CDC，数字回归覆盖提取后的原目标。
- project/constraints 使用显式 filelist；新目标与 DDR BIST 同一组80个板级 bit-port、`I_ips_ddr_top` 层次和官方 FDC/RCF，没有导入旧 arbiter 或另一套 IP。

旧桥来源提交为 `95b6ed41b1de5d372c74dec3213c62193ebce5e4`，文件 SHA256 `1c040700408e981b91f3e0aa31adb50ad616db82b642f4dcd49dcd9668f9c969`。其地址/突发上限、只认 native 接纳的 B 及复位语义没有沿用。参考文件未修改，适配后由独立字节内存 oracle 验证。

## 当前数字证据

桥 canonical191例、独立354例通过，覆盖上下 lane、1..16拍、全部字节 strobe、17..256拍拒绝且不改缓存、窗口/4 KiB、ID/晚到数据、核验失败和故障命令保持；规格审查通过后质量审查也通过。

DMA canonical19例包括完整800×600 raw和400×300 preview，独立62例；packer canonical9行和独立131行通过。独立审查发现 RESULT 期间无主 B 没有保持故障、IDLE 无主 B 与 descriptor 同拍会吞请求，两者先由独立失败刺激复现，再补测试修复并复核。RGB 顺序、跨拍像素、39 B行/48 B步长的padding、错误/abort和VALID稳定分别检查。

端到端使用独立高效 byte-memory 模型，13×3/16×3异常测试以及完整800×600、1367×3跨4 KiB/尾字节通过；完整 raw 检查1,440,000字节、90,000拍。原生模型更新真实存储字节，读回期望来自独立 x/y/channel 计数器，不引用 writer 的 WDATA、打包器或源坐标寄存器。数字板级替身另检查 UART、无 core/无初始化、停钟后的旧 PASS 撤销、PLL丢失和协调 KEY0。

完整回归、最终 PDS 与物理结果在本批证据摘要中分别记录；组件通过不代替内部时序或板测。所有加密 IP 源仍由原哈希锁定生成器提供，保护库训练仿真的既有失败不改写。

首次集成布线的 core setup WNS 为 −0.195 ns，路径经过 native 读数据、masked readback 比较及写 WSTRB。读写阶段互斥，随后仅把写选通的即时故障条件按写阶段等价拆分，去除不必要的读数据反馈；状态机、错误优先级、命令和响应语义保持。旧/新模块四态 miter 检查231,072组，另一独立四态检查524,288组，桥 canonical191例及独立354例均通过。仍使用原125 MHz、额外0.2 ns margin及官方 FDC/RCF，不通过放宽约束或假路径消除违例；失败目录保留，不能用于下载。

## 最终构建与板测进度

`build/video/pds/20261016T120259_929949Z` 最终构建通过，内部多角时序为 All Constraints Met：core125 MHz setup WNS +0.087 ns，free27 MHz +32.027 ns、reset125 MHz +5.144 ns，慢/快角 hold/recovery/removal 均无违例。资源10919 LUT、10488寄存器、0 DRM；该裕量是本次具体布局布线结果，不能外推到新增共享负载后的 SoC。

可下载包为 `build/video/releases/video_axi_capture_f1535f12e7d3`，位流 SHA256 `f1535f12e7d3ce07fa3c144122e1d31b6fa460ae13f6a97eec44304f90315328`，校验掩码 `abca3915c7c77fbc8f9e3c583205c9bc4c321934af701d97fe3a81eb2f505da4`。恢复用 RX 已按当前构建脚本重新构建、打包并完成本轮下载/校验，位流 `46d80ec8eed2735ccf3aea79647eefd0a6a724fe3395998db17a8e02a1bd7880`。

20:10 首次下载在器件识别前失败，默认与500 kHz扫描均没有找到FPGA，USB Cable II仍可枚举。失败记录为 `board_program/20261016T121021_342085Z` 和 `jtag_scan/20261016T121054_322906Z`，均未执行成功的Program/Verify。随后只读串口 `board_serial/20261016T121133_087757Z` 收到原RX的type1/3包，但当时输入模式不合格。用户再次断电重插J12两端并上电后，同一下载入口恢复识别 `PG2L100H / 0x00602899`；仍没有通过电气测量定位具体接点，未写Flash。

## 物理结果与复位重测

- AXI/DMA Program/Verify：`build/video/board_program/20261016T122034_433798Z`，下载的是上述 `f1535f12e7d3…` 位流，目标识别与两步操作均成功。
- 初始12秒：`build/video/board_serial/20261016T122058_274896Z`，12个type4包全部flags21、phaseA5、错误码0、首错字段0；实际/期望均90000拍、1440000字节、base87300000，全部PLL锁定。
- 稳态60秒：`build/video/board_serial/20261016T122126_647692Z`，60包无错，heartbeat73→191。该记录是完成状态持续监测；自检在每次协调复位后执行一轮，不把每个UART包算作一次新帧写入或吞吐测量。
- KEY0：用户确认短按一次。`build/video/board_serial/20261016T122253_540658Z` 采集到heartbeat329→1，之后17个新包全部重新完成90000拍检查、错误码0、全部PLL锁定；证明重新校准及同一路径重新写入/核验成功。
- 恢复RX：`build/video/board_program/20261016T122412_291781Z` Program/Verify成功；`build/video/board_serial/20261016T122434_498418Z` 的5个type1快照全部模式合格，800×600、1056×628及同步/porch正确，像素40,000,100–40,000,200 Hz，坏帧0、好帧395→998。用户随后确认显示器已恢复稳定彩条；当前运行此RX镜像。

源码/报告/原始串口哈希与摘要位于 `docs/verification/video/evidence/axi_capture_bringup.json`。软件实现提交为 `c928706`。本轮证明合成raw图样经生产packer/DMA/AXI桥在物理DDR写后读及KEY0重测；不表示PC的HDMI内容已经进入DDR，也不代表三分支CAPTURE_DONE或外部AC时序已签核。

## 独立板测边界

只使用规格预留测试区 `[0x87300000,0x87500000)`。raw 位于 `[0x87300000,0x8745f900)`，尾部32 B guard 在后续对齐地址，lane/mask probe 为 `0x874fff00`；不在 base 以下写 lower guard。初始 probes 覆盖上下128 lane、零mask、交替mask和首末字节mask，完成 raw 后独立逐字节回读，再确认 guard。

默认图样为 `R=x[7:0]^0x93`、`G=y[7:0]^0x65`、`B=(x[7:0]+y[7:0]+0xb7)&255`。这是可背压的合成图样，实际 PC HDMI 内容还没有写入 DDR。裸 raw 自检完成不发布三分支 CAPTURE_DONE，也不提供回滚；测试会覆盖该独占区域。

UART 保留 TRV1/37字节/115200 8N1、小端和 XOR，使用独立 type4：payload byte1 flags init/busy/done/error/allPLL，byte2 phase（完成A5），byte3 error；4..7实际检查128-bit拍数；8..11首错native word；12..15首错XOR低32；16..19逻辑测试base；20..23raw有效字节数；24..27期望拍数；28..31独立heartbeat。合格需要两个不同heartbeat的完整PASS包，默认90000拍/1440000B/0x87300000全部匹配。

## 原生命令

```powershell
python scripts/video/run.py --suite all
python scripts/video/build_pds.py --target video_axi_capture --stage bitstream
python scripts/video/package_board.py --target video_axi_capture
python scripts/video/program_board.py --target video_axi_capture --start-server
python scripts/video/read_board.py --port COM12 --seconds 12
python scripts/video/program_board.py --target video_rx_board --start-server
```

新目标暂停 HDMI 输出，完成后恢复已校验的 RX 镜像。构建脚本改变后原下载包会因来源新鲜度检查失效，恢复用 RX 包须先重新构建和打包。外部 HDMI/DDR AC 签核、异步物理输入 FIFO 容量及长期带宽/争用测试仍分别开展。
