# Video overlay 共享坐标运算验证

本轮沿用已批准的 Video LUT/125 MHz 收敛范围，只改 BOX 几何组合逻辑。
RAW/BOX/AVATAR、16 个框、每框 5 点、颜色优先级和十三级像素流水保持，
avatar 请求/缓存/alpha 混合路径不改。没有改变 ABI、公共配置或 FDC。

对一个像素，原实现为每个关键点分别计算 `point±radius`，框也有重复的
距离减法。新实现先共享计算像素侧上下界，再让所有坐标与它比较。带符号
13 位覆盖全部合法像素/参数产生的 −800..2847；记录坐标仍为 signed16，
不能截成屏幕范围位宽。框先裁切，再检查有效面积；退化框仍抑制其所有点。

| 同目标、同 PDS 2022.2-SP6.4 综合 | 改前 | 改后 | 变化 |
|---|---:|---:|---:|
| 独立 video_overlay LUT | 10637 | 4641 | −5996（56.4%） |
| 独立 video_overlay FF | 1645 | 1645 | 0 |
| 完整 video_record_probe LUT | 32881 | 26842 | −6039（18.4%） |
| 完整 video_record_probe FF | 44678 | 44677 | −1 |
| 完整 video_record_probe DRM | 69.5 | 69.5 | 0 |

PG2L100H 以 66600 LUT 为基数，完整扫描组件由 49.4% 降至 40.3%。完整组件
层级中的 overlay 为 11401→5424 LUT；层级值包含子模块，不与独立目标混加。
综合会在不同上下文作优化，因此两组 overlay 数字不能交叉计算收益。

改前独立综合：`build/video/pds/20261022T132429_985013Z`；改后独立综合：
`build/video/pds/20261022T133034_510968Z`。完整组件改前采用 static-AW 的
`build/video/pds/20261022T115009_858784Z`，改后为
`build/video/pds/20261022T133201_885026Z`。均使用同目标原有默认命令和约束，
保持固定扫描边界；不是 CPU/NPU 集成的最终 SoC 资源数。

`python scripts/video/test_overlay_geometry.py` 和 `python -O` 各通过 19 组
正向场景、181704 个输入事件及 6 个编译可执行的故障变体。固定
`2463d01adbcb468d4953a4d98628a8d4235035f4` 的旧 RTL，所有 15 个输出在
每个上升沿后 1 ns 以四态 `!==` 比较，包括 reset、消隐和 avatar 请求。
独立 Python 数值 oracle 检查 RGB、标志、地址和十三级对齐。

补充向量覆盖全部 80 点 lane、16 框、signed16 全部 65536 个坐标值（X/Y
分别扫描）、屏幕四边、裁切/退化框、point inclusive 与 box exclusive 边界，
参数对 (2,2)/(1,0)/(800,31)/(3,31)/(799,1)。qualification、dynamic、
avatar_edges、fault_reset、blanking 场景覆盖三种模式、非法模式、匹配失败、
素材响应失败及在途复位。另注入指定 X 坐标、valid，未穷举所有 X/Z 组合。
这是选定输入上的动态等价检查，不是形式证明。

故障变体覆盖点颜色、末列资格、主框优先级、点包含边界、框边缘及 signed
比较；每项必须成功编译并由 miter 拒绝。每个故障使用独立向量/输出目录，
防止覆盖正向的 pixels.log。只读独立审查已发现并修复模式覆盖和目录复用
两项问题；最终 ordinary/-O 在修复后重新运行。

旧的首次 overlay 外层回归因运行中补充测试脚本而被输入哈希门拒绝；不作为
成功证据。脚本冻结后的 overlay 十二场景完整回归通过。逐项证据和后续
集成回归/物理结果定位见 [机器摘要](evidence/overlay_geometry.json)。

record_pixels 的首次全尺寸用例在 900 秒 wall-clock 门限超时，15 个小场景
已完成，未出现 RTL 断言失败；另一份先前启动的 900 秒重试也超时，原记录
均保留。只将 FULL 用例预算对齐 renderer 的 1800 秒，小场景仍为 900 秒，
仿真时钟、仿真周期数、DUT 和检查不变。最终 16 场景完整通过，全尺寸
2440179 像素、960023 取样请求得到独立数值检查。

renderer 的 14 组读仲裁与 6 组显示用例、scanout 的 6 组交接与 3 组扫描
用例通过；全尺寸 scanout 检查 3360000 像素、5 次提交、2 次释放。它们的
外层 run.py 汇总因运行期间与自身无关的测试脚本变化被全局哈希门拒绝；
保留失败，不把外层改成 PASS。最终证据重新核验实际内层结果的全部输入/
工具/输出哈希，内层的相关依赖在运行前后保持，不能与外层状态混淆。

实际原生 C↔RTL MMIO 采显联动的 normal/bad_eof/corrupt 三场景也通过。
normal 检查 2880000 个像素、2 次真实采集、2 份显示记录、5 次反馈、1 次
释放，underflow=0；两个错误输入场景均保守阻止完成/显示记录。此内层结果
同样以冻结的相关输入、工具和输出哈希复核，外层全局哈希失败保留。

新旧布局/route 必须保留各自数据库身份，布线中不能替换 RTL。综合节省
LUT 不能代表 125 MHz 时序已闭合；最终 routed DB 和双 corner setup/hold/
recovery/removal 等完整报告取得前，timing_closed 保持 false。没有板卡、
JTAG/COM/Flash 操作，不迁入 CPU/NPU，也不改变当前板卡镜像。

同 seed4/performance、同约束、`report_place_timing` 估计连线模型的新布局
已完成（`build/video/overlay_geometry_place/20261022T133925_107915Z`）：

| 检查 | static-AW 改前 | 共享像素阈值改后 |
|---|---:|---:|
| slow core setup | −2.135 ns | −2.102 ns |
| slow pixel setup | +0.216 ns | +0.295 ns |
| slow core hold | −0.027 ns | −0.027 ns |
| slow core recovery | −0.954 ns | +0.785 ns |
| fast core setup | −1.306 ns | −1.565 ns |

core setup 仅改善 0.033 ns，fast setup 反而恶化 0.259 ns，不能将资源下降
写成时序收敛。新布局 slow/fast 的其他 hold/recovery/removal/最小脉宽汇总
也保留在原报告中。最差 slow setup 仍为扫描输出寄存器→`core_scan_o`，
两级、估计连线 3.498 ns；受限的关键路径列表随后主要是 reset 输入至内部
使能，不能据此宣称产品其余内部路径已全部满足。

严格 routed-report 解析器会拒绝该 placement 报告；未为接受估计值而放宽
解析器。新冻结布局以同 seed11 route 策略单独布线，定位
`build/video/overlay_geometry_delivery/latest_route.json`；旧 static-AW seed11
保留自己的数据库和进程。两者最终结果分别更新，未取得最终 routed DB/STA
前均不能签核。后续时序优化重点仍是扫描边界 I/O 和 reset/enable 网络。
