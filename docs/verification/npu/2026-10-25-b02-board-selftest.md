# B02原始发布位流上板验收

2026-10-25。用户指定从GitHub获取最新NPU工程并验证B02。已fetch并完整导出605文件快照，提交 `b7ce46a4ddb13c152b3b107e4bb988a5fe5f0b8b`；本地外部工作树保留178c3ad及既有台账，最新源码位于 `D:/FPGA/TriHaRiscv-npu-operator/build/npu/b02_20261025/upstream`。

**B02首次下载和一次实体KEY0重启，两轮串口均为VERIFIED_PASS，16项全PASS；用户确认首次及复位后4F/5F通过灯态。** 本次使用远端原始发布位流，没有本机改RTL、重建或改约束。

## 下载身份及核验范围

- 位流：`b02_board_top.sbit`，3791112B，SHA256 `33c8ca921095677fdc7cb34fcbc56ade7db75e15cdaa224c76e3b60f2e666be9`。
- UART实际身份：BUILD=42303231，USERCODE=4E505533，CONFIG=42303201，VECTORS=56454331；两轮均匹配发布manifest。
- 包内7个声明文件SHA全部匹配，四份发布验证摘要SHA与manifest一致，其可取得的自有源码哈希一致。84个源端口/84唯一LOC检查通过，原B01的83端口配置相同，新增UART TX=C24/3.3V，与主工程官方UART接法一致。
- 上游所列约束PDS已通过，compute100MHz/UI125MHz slow setup分别+0.081/+0.087ns；这是上游构建证据，本轮未重跑PDS。上游真实HMIC模型验证只覆盖优化前00～06，此次实体测试单独登记。
- 远端没有同构建smsk，本次按B02操作卡执行原始sbit的SRAM Program及下载后扫描DONE=1，**未执行配置读回Verify**，也未借用其他位流掩码。功能验收使用带CRC和身份检查的实际UART报告。未写Flash。
- 已核验并保留 `video_mode_board_8274194d1c69` 恢复包的sbit/smsk。

## 实际串口与现场结果

COM12（CP210x），115200/8N1/无流控。首次在下载前打开原始字节记录；全量raw日志保留。验收切片从下载完成后收到的新BEGIN开始，到完整END结束，切片起点与哈希已记录，避免把下载前可能存在的程序状态混入验收。首次切片7个完整快照，损坏/不完整记录0。

KEY0复测先确认用户按住且8灯全灭，再开启全新文件，提示松开后完整记录；没有再次JTAG下载。该原始日志直接解析，8个完整快照，损坏/不完整记录0。两轮均在首次最终结果后继续记录至少10秒，并停在完整END边界；发布解析器CLI另行重放均退出0。

| 项目 | 首次启动 | 实体KEY0重启 |
|---|---|---|
| executed / passed | FFFF / FFFF | FFFF / FFFF |
| failed / blocked | 0000 / 0000 | 0000 / 0000 |
| protocol_error / stale_events | false / 0 | false / 0 |
| epoch | 00～08为1，09～0E为3，0F为4 | 相同 |
| CASE06实际UI读 / 写字节 | 151034112 / 151034112 | 151034112 / 151034112 |
| CASE07有效输入echo | 307200B | 307200B |
| 最终灯态 | 用户“与上述通过灯态一致” | 用户“已松开，恢复上述通过灯态” |

## 16项覆盖

| CASE | 发布测试内容 | 首次 | KEY0 |
|---|---|---|---|
| 00 | 时钟锁定、DDR校准、双域ARM及独立监护启动 | PASS | PASS |
| 01 | 冻结B00 RAM六模式3072次检查、APM16组双路乘累加 | PASS | PASS |
| 02 | 各1～16拍写读；不同CMD_ID/client，逐拍数据、LAST与DONE身份核对 | PASS | PASS |
| 03 | DONE背压保持32周期，未确认前拒绝下一命令，状态与身份稳定 | PASS | PASS |
| 04 | 各1～16拍生产者间隙，完整包收齐后发AW，逐拍数据/LAST核对 | PASS | PASS |
| 05 | 各1～16拍消费者长停顿及周期停顿，RX预留，消费完才DONE | PASS | PASS |
| 06 | 长度1～16九模式小探针共4352B，再跑默认16MiB九模式；含部分/零掩码、4KiB拆分与首错详情 | PASS | PASS |
| 07 | 307200B输入echo、保护区与CRC32=be958c95；实际总线读写各307264B | PASS | PASS |
| 08 | 交替读写与生产/消费/DONE混合停顿，无丢失或重复 | PASS | PASS |
| 09 | 半包整会话取消；双向AW仲裁阻断时abort并合法解封排空；AW已承诺后abort；错LAST隔离并核对status2/reason1；新epoch正常读写 | PASS | PASS |
| 0A | 最小普通1×1卷积，覆盖非整通道及跨K累加、bias与输出掩码 | PASS | PASS |
| 0B | 最小普通3×3卷积与pad1，完整结果回读 | PASS | PASS |
| 0C | DW3×3、stride1/2、padding及输出回读 | PASS | PASS |
| 0D | ReLU、带符号RNE/饱和，437个数值及非法参数边界 | PASS | PASS |
| 0E | 三个真实原生窗口，字节、突发、等待、FIFO水位与本地计数交叉核对 | PASS | PASS |
| 0F | 32组真实普通/DW小卷积；第16组后整会话恢复，新epoch完成后16组 | PASS | PASS |

每轮的32组小卷积回归及三次计划恢复属于该固件自动流程；不能把它们算作用户按键次数。用户本次实体KEY0复测为1次。首次原始结果目录 `D:\FPGA\TriHaRiscv-npu-operator\build\npu\b02_20261025\trial_20261025T125403_452585Z`；KEY0目录 `D:\FPGA\TriHaRiscv-npu-operator\build\npu\b02_20261025\key0_20261025T125720_326249Z`。

本结果证明该B02平台、小算子、16MiB独占DDR和复位路径在本板的功能。完整YuNet、最终五点INT8、生产CPU/Video共享fabric、完整物理CDC/外部DDR时序、全容量与30fps仍不由本次关闭；原B01十分钟观察没有新增明确反馈，维持原证据身份。

机器摘要见 [b02_board_selftest_20261025.json](evidence/b02_board_selftest_20261025.json)。原始UART、解析JSON、Program日志、源码快照和用户反馈均按SHA绑定；主工程现有NPU文件保持原样，台账仅追加，无提交或推送。
