# TriHaRiscv 总工程工作约定

## 权威来源与范围

- 当前主工程是本目录 `TriHaRiscv-main`。规格依据为 `docs/TriHaRiscv_SoC_Design_Spec_v0.6.md`。
- `D:/FPGA/TriHaRiscv-v3` 及独立 CPU 工程仅为来源/验证记录，不能把它们的旧应用、地址、格式或路径规则带入总工程。
- 用户当前已授权开始 Video 路线实施，优先 Windows 原生开发、参考例程复用和尽快上板。旧 README 的“暂不迁移”历史状态已结束；复用仍须逐项验证。
- 现有 `docs/technical-report/` 修改属于独立工作，遵守其局部 AGENTS，不覆盖、不连带提交。

## 目录与责任

- CPU：`rtl/cpu/`、`rtl/soc/`、`sw/drivers/`、`sw/runtime/`，负责正式互连、地址属性、固件和统一帧状态。
- NPU：`rtl/npu/`、`model/yunet/`，负责模型清单、真实量化参数、整数参考及算子。
- Video：`rtl/video/`、`tb/video/`、`scripts/video/`、`fpga/pg2l100h/` 中 Video 文件及后续 `assets/avatars/`。
- `config/` 保存公共权威配置；生成 RTL/C 定义不分别手改，修改后运行生成器和 `--check`。
- `fpga/.../project/` 保存显式目标/filelist，禁止递归收集所有 RTL 作为正式构建输入。
- 原始厂商包不修改；选中文件按版本/哈希提取到 `build/video/vendor/`。IP 实例配置/来源清单纳入版本，生成库/网表/临时工程不纳入版本。
- 所有波形、日志、PDS 输出、临时转储统一进入已忽略的 `build/`；文档保留小型证据摘要和原始结果定位。
- 不提前创建大量空目录；实现与对应测试同时落到职责目录。

## Windows 工具与命令

默认入口是 PowerShell + Python 3.11 及以上，不要求 WSL、bash、make 或 Linux 路径转换。

```powershell
python scripts/video/doctor.py
python scripts/video/gen_config.py --check
python scripts/video/prepare_reference.py --reference hdmi
python scripts/video/prepare_reference.py --reference ddr
python scripts/video/run.py --suite all
python scripts/video/build_pds.py --target video_timing --stage synth
```

工具通过 PATH、`TRIHA_IVERILOG`、`TRIHA_VVP`、`TRIHA_PDS_SHELL`、`TRIHA_VSIM`、`TRIHA_TAR` 及已安装默认位置发现；工具覆盖变量填写可执行文件路径。板卡包可通过 `TRIHA_BOARD_ROOT` 或命令参数指定。Python 文本文件显式用 UTF-8，不依赖 Windows 默认代码页。

## 验证与交付

- 新硬件行为先建立可失败的自校验测试，再实现；数值 oracle 依据规格独立定义。
- 失败返回非零。新运行先使旧成功标志失效，构建使用独立目录；保存输入哈希、工具版本和结果。
- 分别报告组件仿真、综合、布局布线、物理时序、板测；不得以其中一项替代另一项。
- `video_timing` 是便携时序/彩条组件，尚无 HDMI/PLL/DDR/板级管脚。它的综合成功不能用于下载或宣称板卡已点亮。
- Video 不自行假定 NPU 量化尺度或 CPU 的总线写可见性；未冻结契约在接口文档和任务表中明确记录。
- 每批更新 `docs/video/STATUS.md`，列出本批证据、未完成项、依赖及下一步。
- Git 保留小范围可审查变更，禁止 `git add .` 连带其他路线修改；不在并行任务使用的共享目录反复切换分支。当前 Video 分支为 `video/windows-bringup`。
