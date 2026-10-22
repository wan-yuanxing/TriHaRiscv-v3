# Video 组件时序基线

本批延续用户已批准的 125 MHz 时序收敛方向。先分清组件边界与内部路径，
只在有关键路径证据时修改 RTL。允许内部增加 1～2 拍的授权保留，本批不必使用。

`video_control_decode`、`video_display_record`、`video_record_pipeline` 的端口
用于内部连接，不能把自动插入的 FPGA I/O 缓冲当作最终系统边界。保留原来的
默认综合，另给这三个目标增加显式 `--synth-timing pads|component` 诊断选项。
两种模式使用同一显式文件清单、快照和 FDC，均设置 `-max_path 20 -nworst 1`；
PDS 按时钟/检查类别分组输出，总路径数可以超过 20。component 仅增加 PDS
原生 `-disable_io_insertion`。

诊断必须提取声明时钟、setup/hold/recovery/removal/pulse-width 汇总和原始
路径端点。缺表、空 setup、时钟周期改变或未知 critical/error 使构建失败。
汇总覆盖所有约束路径，路径清单是上述数量上限内的关键路径，不提供未经验证
的寄存器筛选选项。常规路径与精确时钟对汇总比较；datapath_only 报告不含时钟
边沿信息，显式只核验捕获时钟组的保守 WNS 下界，不声称精确时钟对核验。PDS Tcl 对象
句柄不能直接作为 synthesize 的字符串选择器；探索期间该失败结果必须保留。

`status=pass` 只表示综合和诊断完整；`timing_closed` 与物理验证标志保持 false。
setup 通过不能掩盖 hold/removal 失败。单 slow corner 与空 fast 表必须显式记录。
不放宽频率、I/O budget、稳定束 6 ns 或现有 CDC 例外，不触碰 ABI、CPU/NPU、
驱动或所有权规则。保留其他路线工作树变化，本批不操作板卡。

验收为：解析器拒绝缺损/矛盾报告；默认命令保持兼容；诊断不能用于板级目标
或 route/bitstream；真实三目标诊断绑定源/工具/脚本/报告哈希，并有独立审查。
这批只建立可信综合基线，实际 PNR 与系统时序仍是后续工作。
