# B03 两帧真实推理与主工程内存服务入口

`build/npu/b03_frame_proxy_zero_pattern_20261030/result.json` 为 **PASS_TWO_FRAME_NATIVE_PROXY**，ModelSim SE-64 2020.4 实际耗时 **478.71 秒**。

```powershell
python scripts/npu/run_b03_frame.py --suite frames --cases zero pattern --output build/npu/b03_frame_proxy_zero_pattern_20261030 --timeout 7200
```

输出目录只能新建；重跑应另选路径。源输入由 `FrozenInputs` 在运行前冻结，完成后再次验证原件和副本。TB/driver 与 native bridge 支持源来自固定提交 `558280b30219acdcf9f962acd6e907e0f680ab52`，原字节未改。

| case | 实际算子/参数预检 | frame/model/post cycles | ROI | POST table CRC 命令 |
| --- | --- | --- | ---: | ---: |
| zero | 79 / 79 | 9,578,629 / 9,063,082 / 4,632 | 0 | 3,072 |
| pattern | 79 / 79 | 9,051,521 / 9,046,798 / 4,635 | 0 | 0 |

两帧均通过完整 HEAD824 字节比较、records 比较、Python 独立 header/records CRC 校验及私有头身份/scope 检查。最终 global commands/dones 为 240,709/240,709；316 次 layer op/epoch lease 与 2 次 task lease 均通过。原始 `console.log`、`transcript.log` 为 0 errors/0 warnings，选定信号存在于 `trace.vcd`。

此测试实际执行 MODEL、FPGA POST、CDC FIFO 与 session bridge。只上传 program、参数、真实输入、POST 表和 HEAD padding；golden 只作为比较，不注入模型输出或中间张量。native HMIC/UI 是字节内存代理，没有物理 DDR3 模型；没有覆盖主工程共享仲裁、板测、五点或 30fps。六图资产仍只有三个合成帧就绪，本批仅执行 zero 与 pattern。

为连接主工程检测显示链，新增 `rtl/soc/npu_service_axi128.v`：接收 B03 256-bit CMD/W/R/DONE，限制 DDR-relative `[0x02000000,0x08000000)`，恰好加一次 `0x80000000`；低 128-bit 先发，INCR/SIZE4/固定 AXI ID0，每子事务最多 16 AXI beats，跨 4KiB 拆分。健康信号只门控新命令，已发 VALID 不撤回；全部已广告事务退休后才能报告 DONE，错误锁 fault 等待 coordinated reset。无新增在途强杀 timeout。

```powershell
python scripts/soc/run_npu_service.py --output build/npu/b03_frame_axi_service_20261030_02
```

独立字节 scoreboard **33 checks PASS**：AW20/B20/AR19，W-before-AW16，AW-before-W15，跨页4次；覆盖 1/8/16 拍、随机背压、任意与全零 WSTRB、错误 ID/RESP/LAST、范围/长度拒绝、healthy掉落、在途abort和DONE保持。该服务尚待应用wrapper与共享DDR端口集成，不能由本组件测试直接声明检测显示链已完成。

测试与工具记录：`scripts/npu/test_b03_frame_runner.py` 11 项 PASS；控制准入见 `b03_frame_control_20261030.md`；服务原始日志和源哈希位于上述 `_02/result.json`。没有提交或推送。
