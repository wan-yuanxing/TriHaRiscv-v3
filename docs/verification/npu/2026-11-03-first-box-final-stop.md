# 最小主脸框版本停止记录


### 2026-11-03 21:01 最后一次布线超时，按用户要求停止

CSR 首版固定 seed4 布线触及既定 90 分钟上限，回执耗时 5405.21 秒（含停止清理）。
最后完成第 161 轮，仍有 11933 条未布线网络，近期迭代在约 1.2 万条附近波动。
监督器已停止其 PDS 进程树；独立核查无 PDS/Python/ModelSim/vvp 工程进程，active_runs 为空。
489 项冻结输入逐一 SHA-256 复核一致。没有本轮 routed DB、最终 STA 或新位流；
本次结论是布线未完成并超时，不能将先前版本的时序结果当成本轮验收。

用户“这一版再失败就停止”的条件已触发，工程推进已停止，无下一次运行。
备用像素候选仍未采用，不启动仿真、综合、放置、布线或后台任务，不操作板卡。
先前真实六段模型加载/CPU/NPU/两帧主脸框功能仿真证据保留；最小上板交付未完成。
原始回执/日志不改写；最终核验见
`build/video/pds/face_first_box_csr_route_20261103/final_review.json`。
预整理包仅保留输入，`RELEASE_STATUS.json` 标记未发布。

证据 SHA-256：

- `build/video/pds/face_first_box_csr_route_20261103/receipt.json`：`48b2df0dd6bba32861912efae70e142d310f57b049aaff085cc2b38a7b8fcc3e`
- `build/video/pds/face_first_box_csr_route_20261103/build.log`：`989cddeb52fde03ef5911aef682bf6c9a9457a557b0ae02b6a458603198f7fff`
- `build/video/pds/face_first_box_csr_route_20261103/runtime.jsonl`：`9d65968ce80681f2b610675ffa8890e3552a44145f3b25ecff5a9bc0bce6e666`
- `build/video/pds/face_first_box_csr_route_20261103/timeout_process_stop.log`：`355600c2147e2119d738f6164a32f36c2c0e749aa5eb6f88504b606e71f94047`
