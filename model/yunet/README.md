# YuNet B03 运行资产

`upstream/b03_558280b/package_manifest.json` 是上游提交
`558280b30219acdcf9f962acd6e907e0f680ab52` 中
`yunet/reports/b03_runtime_v1/package_manifest.json` 的原字节副本。
SHA-256 为 `d1305ad11d4997cf79e3646af2f31a5306b75d751210505de9a80fd0a259bbd0`。
其中的上游 `passed: true` 是历史记录；当前本地恢复状态必须读取新审计报告。

在主工程运行：

```powershell
python scripts/npu/prepare_b03_assets.py --output build/npu/b03_assets_new --npu-root D:/FPGA/npu_zgtc
python scripts/npu/audit_b03_assets.py --assets build/npu/b03_assets_new/assets --manifest model/yunet/upstream/b03_558280b/package_manifest.json --output build/npu/b03_assets_new/audit.json
python -m unittest discover -s scripts/npu -p test_b03_assets.py -v
```

恢复器以完整 Git commit ID 导出 Python 依赖闭包和数值清单；不会读取源仓库工作区中的 Python 实现，不会切换或修改源仓库。旧 format1 程序和参数必须先满足冻结 SHA，再复制到独立目录。数值执行使用现有 NPU Python 环境，也可用 `--python` 指定已安装解释器。`--search-root` 可重复指定额外资产目录，按字节哈希寻找旧资产。

恢复目录只能新建，不能覆盖。全部 68 项历史字节一致才返回 0；缺失返回 2（`PARTIAL`），不匹配或执行失败返回 1（`FAIL`）。Windows PowerShell 的命令包装层可能把非零结果统一显示为 1，JSON 内状态仍为权威。

`assets/` 仅保存符合原始哈希的文件；新主机参考结果保存在同级 `host_reference.json` 和 `recovery_report.json`，不替代含历史耗时的 `compile_report.json` 或各 case 的 `manifest.json`。主机资产身份、参考执行、RTL 仿真、物理 DDR、PDS 和板测是独立证据。

2026-10-30 的恢复结果见 `docs/verification/npu/b03_assets_20261030.md`。目前三个核心二进制和 zero/full255/pattern 三帧可用；三个自然图像帧缺失。后续提供满足历史 SHA 的自然图像 `input.bin` 可继续恢复；WIDER 帧还需要原始 `task.bin` 来固定 letterbox 几何。不会用新图像或新随机输入冒充原六帧。
