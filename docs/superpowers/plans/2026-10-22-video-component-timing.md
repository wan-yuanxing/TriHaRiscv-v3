# Video Component Timing Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 给三个内部 Video 目标建立可复现、不会误报物理闭合的综合时序基线。

**Architecture:** `pds_timing.py` 负责诊断命令和严格报告解析；`build_pds.py`
只增加参数、命令和结果钩子。沿用既有显式输入、快照、生成检查和诊断拒绝流程。

**Tech Stack:** Windows、Python unittest、PDS 2022.2-SP6.4。

## Task 1: 测试与实现

Files: create `scripts/video/pds_timing.py`, `tb/video/test_pds_timing.py`;
modify `scripts/video/build_pds.py`，保持钩子外 CRLF 字节。

- [x] 先写失败测试：默认 `synthesize -ads`；component 必须带
  `-disable_io_insertion -max_path 20 -nworst 1`；拒绝板级目标和非 synth。
- [x] 用完整的双时钟单 slow corner 样例检验全部 5 类汇总、空 fast 表、
  setup 正而 hold 负、路径端点；删除表、改变时钟、空 setup、汇总矛盾均须拒绝。
- [x] 运行 `python -m unittest discover -s tb/video -p test_pds_timing.py`，
  确认失败原因为功能缺失，再实现 `synthesis_command` 与 `parse_synthesis_timing`。
- [x] 仅加入诊断参数、上述两个调用、诊断结果及工具哈希复核钩子；
  将解析器本身加入输入哈希。默认路径保持原命令。
- [x] 普通与 `python -O` 运行上述测试及既有 `test_pds_*.py`；
  不以 Python assert 实现接受门槛。

## Task 2: 真实工具验证与交付

- [x] 三个目标运行 `python scripts/video/build_pds.py --target TARGET
  --stage synth --synth-timing component`；译码器再运行 pads 对照。
  记录同源 pipeline pads/component 探索结果和完整 120 寄存器筛选的有限结论。
- [x] 复核每个诊断的源快照、时钟、全部约束适用、日志、原始 SNR、工具和结果哈希。
  setup/hold/removal 各自报告；不将单 slow corner 综合标为 PNR 通过。
- [x] 独立审查脚本、测试和证据，修复实质问题。
- [x] 新增 `docs/verification/video/component_timing.md` 及机器证据，
  追加 Video STATUS。只提交本批文件；STATUS 使用 index projection 保留 NPU 追加。
- [x] 提交后审计提交范围和受保护工作树。后续 PNR/内部边界优化独立验收。
