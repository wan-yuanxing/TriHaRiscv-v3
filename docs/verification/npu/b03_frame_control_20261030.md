# B03 payload 控制准入（2026-10-30）

结果：`PASS_CONTROL_ONLY`。实际运行 `b03_frame_exec_payload` 父控制 RTL 的 lifetime 与 ACK/reset 回归，耗时 5.72 秒；没有执行本测试中的完整模型或 NMS。

```powershell
python scripts/npu/import_b03_tests.py
python -m unittest discover -s scripts/npu -p test_b03_frame_runner.py -v
python scripts/npu/run_b03_frame.py --suite control --output build/npu/b03_frame_control_20261030
```

输出目录 `build/npu/b03_frame_control_20261030/`：

- `result.json`：源文件、冻结副本、厂商库、工具及运行脚本哈希，结果范围和耗时。
- `tb_b03_payload_lifetime/{console.log,transcript.log,trace.vcd}`：六种父控制路径与四拍私有头写出。
- `tb_b03_payload_ack_reset/{console.log,transcript.log,trace.vcd}`：一个 compute edge 上 ACK 与 session reset 重叠。
- `header.hex`：128 字节私有结果头；Python 使用独立 `zlib.crc32` 校验头 CRC、身份、记录长度和 scope 字段。

两项仿真的日志均无 ERROR/FATAL/WARNING，编译摘要为 0 errors/0 warnings，且所需 PASS 标记存在。ACK 回归没有接受外部存储命令；lifetime 回归中成功 graph/POST 完成信号由 TB 显式注入，不能视作全模型执行证据。

`tb/npu/upstream/b03/` 保留提交 `558280b30219acdcf9f962acd6e907e0f680ab52` 的 4 个原始 TB/driver 与 11 个原生 session bridge 支持源文件，均未改字节。清单为 `config/npu_b03_test_sources.f`，这些支持源只参与测试，未加入 production 40 文件清单。

运行使用 `scripts/video/common.py` 发现的 ModelSim SE-64 2020.4，以及现有 PDS_2022.2-SP6.4 的 E1/APM/LUTRAM 仿真原语。`FrozenInputs` 在编译前冻结输入并在完成后同时检查源与副本；资产哈希和模拟输出检查由 runner 独立执行。

runner 的 11 项测试覆盖资产缺失/篡改、警告或错误日志、丢失 PASS、X 值 HEX、HEAD/record 差异、头 CRC、重算 CRC 后的错误身份、禁止覆盖既有运行以及 test-only 源导入和篡改。

真实 zero + pattern 两帧在 `build/npu/b03_frame_proxy_zero_pattern_20261030/` 完成，最终为 `PASS_TWO_FRAME_NATIVE_PROXY`，见 `b03_frame_proxy_20261030.md`。原生字节代理不构成共享 DDR/HMIC、物理时序或板卡证明。
