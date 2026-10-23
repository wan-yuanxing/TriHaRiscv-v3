# 连续三模式实施计划

> 在当前已授权 Video 分支顺序实施；使用测试先行、定向审查和交付验证。不开新用户任务，不切换共享分支。

1. **重复变化帧的模式组件测试**：新增 `tb/video/tb_video_live_mode_output.sv`，由独立源函数和整数 Alpha oracle 验证 pad RGB/同步/帧号。先将旧 `video_demo_mode_output` 作为对照，观察帧号冻结失败；再实现新模块。
2. **像素元数据导出**：修改 `rtl/video/video_live_engine.sv`，仅连接扫描器现有 output context。更新 `tb/video/tb_video_live_engine.sv` 的 wildcard 信号声明，保持旧 RAW 仿真。
3. **连续模式板级接入**：新增 `fpga/pg2l100h/rtl/video_live_mode_board_top.sv`、显式 project JSON/FDC，复用 RAW 板壳，接真实像素上下文和 KEY1，增加第四种 UART 包。新增 `tb/video/tb_video_live_mode_board.sv`，覆盖多帧、模式与复位，检查最终 pad 而非只看内部 raw。
4. **工具和协议**：新增 `scripts/video/test_live_modes.py`；将目标加入构建/打包/下载入口和回归套件，加入 `tb/video/test_live_mode_packets.py`。先验证旧 qualifier 会拒绝新模式包，再实现完整四包健康判断。
5. **检查与实体交付**：跑本批用例及受影响 RAW/模式回归；定向审查。实际目标以125MHz/40MHz综合、布线、生成位流与掩码，只有内部时序通过才打包。下载、Verify、持续串口和现场KEY1/KEY0验收；收尾更新台账、证据并只提交本批文件。

实际命令入口：

```powershell
python scripts/video/test_live_modes.py
python scripts/video/run.py --suite live_board
python scripts/video/run.py --suite mode_output
python scripts/video/build_pds.py --target video_live_mode_board --stage bitstream --seed-start 5 --seed-count 1 --pnr-mode performance
python scripts/video/package_board.py --target video_live_mode_board
python scripts/video/program_board.py --target video_live_mode_board --start-server
python scripts/video/read_board.py --port COM12 --seconds 60
```
