# 同帧 raw / preview / YuNet input 三分支采集核心

基线29655b2，计划f02e9fc。`video_three_branch_capture`复用已验收的RGB packer、
2×2 preview scaler、固定5:2 bilinear scaler、单平面DMA和NCHW行式DMA，
同一份48bit PIX/EOF流生成800×600 RGB、400×300 RGB和320×320 UINT8 BGR NCHW。
本批新增`axi_write_arbiter3`，保留旧双分支板级目标及其物理验收记录。

## 请求、事件与地址

一次协调复位只接纳一份slot/frame_id/preprocess_version请求。只有三路写入
描述符均已接纳后才翻转arm；首个合法PIX被三路原子接收时发布accepted事件。
该事件对应入口选中的帧首，经FIFO/流水延迟到达core，不是新增物理SOF时间戳。
请求线后续变化或重复VALID不改变锁存记录。未知元数据、slot3、错误版本和
非法静态几何产生code08，禁止arm及AXI写入。预处理版本固定1。

公共JSON及生成RTL/C现同时定义：

| slot | raw | preview | input |
|---|---|---|---|
| A | 0x82000000 | 0x82160000 | 0x82800000 |
| B | 0x82200000 | 0x82360000 | 0x82850000 |
| C | 0x82400000 | 0x82560000 | 0x828A0000 |

帧槽2MiB、preview偏移0x160000；input每槽320KiB，默认有效张量300KiB。
默认raw/preview行步长2400/1200B；NCHW每行320B、每平面102400B，补40+40行零。
所有最终总线拍均须处于分配区内。参数化小尺寸仅供组件验证，实际NPU契约
仍为默认320×320；本批没有CPU译码、MMIO、帧槽分配器或跨master可见性实现。

成功completion同时要求：accepted事件已消费、480000/120000/76800像素及行末
计数精确、good EOF且源CRC与core独立累积raw CRC相符、三路成功result的tag和
有效字节数正确、全部B响应与仲裁所有权退休。它不是单独INPUT_WRITE_DONE。
accepted和completion均保持至ready；结果一经发布，晚到abort/offline/异常B
不能撤销或改写它，live sticky error仍可变化。accepted在全部写入完成后继续
受阻时停止采集计时，不能把软件事件背压误报为采集超时。

## 取消与仲裁

无故障PIX只在raw、preview和input三路都能接收时消费；相应数据只推进一次。
错误源词可被消费并丢弃，但整帧失败。新像素和新描述符在检测故障时停止；
DMA取消使用注册error，检测沿已有合法缓存字仍可能进入写DMA，随后一起排空。
这打断READY→payload校验→abort→READY的组合反馈；故障帧的部分写入不能使用。

仲裁器注册owner后才公开AW，从AW一直锁定至合法B退休；三主按round-robin
轮转。早B记录错误但不能释放owner，持续早B在AW/WLAST完成后可排空。无主B
被消费且不传给任一master；BID/BRESP按四态检查。fault不门控owner选择，
已在各DMA公开的待选AW在取消后仍须逐一得到仲裁并排空。

error立即锁存首因并驱动cancel；失败completion还须等所有已请求writer和
仲裁口退休。`port_drained`为live状态，不能从error或busy推断端口已空闲；
已发布历史completion也不保证其后出现的新异常响应已经排空。默认超时仍为
625000000个125MHz周期（5s），不能用超时撤销已公开AW/W/B；故障排空可继续
等待外部响应。开始下一任务必须协调复位入口FIFO、scaler、packer、DMA及端口。

## 验证

正式套件检查三种小几何的A/B/C三槽、28类控制场景、14种非法参数处理和
一个完整800×600图。实际AW/WSTRB/WDATA构造raw、preview、input字节内存，
检查独立数值oracle、全部有效字节覆盖、重复写、guard/stride、4KiB边界及
成功响应字节计数。全尺寸input直接转储307200B，与冻结OpenCV4.11图3的
SHA256 `959f1f661aaccc3194e33a9b2916e87d477a6fe752287f004324977016733c09`比较；
软件不重排或补边。

独立审查通过规格符合性和代码质量两阶段：另一幅20×30图、3/4补行、17个
控制模式、26种非法元数据/极端几何，88条命令均符合预期。五种mutant均成功
编译并由指定断言拒绝；无timeout或编译失败冒充mutation通过。仲裁器自身的
独立TB另拒绝七种mutant。父会话复核224项集成审查哈希，并独立运行仲裁证据
审计。未发现需修复的生产缺陷。

初始missing-module RED保留；早期强制坏input RGB复现的反馈问题以host timeout
记录为故障，修复后的同场景正常返回code0a，未把该timeout计作正向PASS。
早期suite因PDS要求显式端口而输入哈希变化，已保留为stale失败；最终冻结结果
及原始定位见[机器证据](evidence/three_capture.json)。

```powershell
python scripts/video/gen_config.py --check
python scripts/video/run.py --suite three_capture
python scripts/video/build_pds.py --target video_three_capture --stage synth
python scripts/video/run.py --suite all
```

本批为组件仿真和综合，无route/bitstream/Program/Verify/UART/Flash操作。
125MHz及原6ns CDC束约束不变。共享CPU/NPU fabric可见性、正式MMIO就绪事件、
三槽生命周期、入口FIFO容量/物理HDMI吞吐、布线及上板验收均须独立完成。

## 最终冻结结果

最终冻结回归`build/video/regression/20261018T115540_354215Z`通过31套件/159当前输入，209份仿真PASS日志；Python63项中62通过/1个Windows条件跳过。组件综合3959LUT/2825FF（含216个分布式RAM LUT）、3个DRM18K、2APM，8ns估计setup+0.596ns/hold+0.428ns，7113个端点；两个APM分别位于复用的raw/preview DMA。该结果不是布线或物理吞吐验收。
