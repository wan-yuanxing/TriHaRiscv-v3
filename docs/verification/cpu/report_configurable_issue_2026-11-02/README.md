# 可配置单/双发射CPU文档依据

本目录保存技术文档中配置说明、双发射CoreMark板测、资源和时序的来源。

## 原图与数值

| 配置 | 原图（相对于技术文档目录） | 完整周期数 | CoreMark/MHz（串口显示） | CPU核LUT |
| --- | --- | ---: | ---: | ---: |
| 双发射、SRAM、Cache关闭 | `figure/cpu-dualissue-sram-coremark-uart-original.png` | 1,221,660,558 | 4.092789 | 9677 |
| 双发射、私有DDR、Cache开启 | `figure/cpu-dualissue-cache-ddr-coremark-uart-original.png` | 1,586,210,467 | 3.152166 | 9707 |

原图来自用户附件，按字节保存，未裁剪或修改。两组均为六级、100 MHz、5000次迭代、GCC 15.2.0、RV32IM/Zicsr、ILP32、`-O2`；CRC正确，`errors=0`、`short=0`并输出BOARD_PASS。

运行时长按完整周期数除以100,000,000计算，CoreMark按5000除以运行时长计算。正文分数保留串口显示的六位截断小数，完整复算值及原图SHA-256见 `benchmark-index.json`。

DDR截图为1,586,210,467周期，已有独立串口记录为1,586,210,466周期。正文使用截图值；原记录保持原样，未将两个运行合并成同一次捕获。

## 支撑材料

以下文件从 `D:/FPGA/TriHaRiscv-cpu-dualissue-windows` 按原字节归档，原路径与SHA-256登记于 `benchmark-index.json`。

| 文件 | 用途 |
| --- | --- |
| `dualissue_board_coremark_deployment_20261101.json` | SRAM板测、CPU核资源、后布线时序和下载验证记录 |
| `coremark_dual_cache_board_20261102.json` | Cache＋DDR板测、下载验证和对应发布包 |
| `coremark_dual_cache_bitstream_20261101.json` | Cache＋DDR实际布线结果及CPU时钟域多工艺角时序；该文件本身为打包阶段记录 |
| `ddr-board-manifest.json` | 实际DDR板测包的资源和布线目录；与上述时序记录指向同一布线构建 |
| `dual_issue_cache_parameter_matrix_20261102.json` | 单/双发射×Cache开/关的四组CPU测试、四组SoC测试，以及三组综合映射检查 |
| `document-audit.json` | 最终文档及源码哈希、编译检查与来源核验结果 |

参数矩阵中的八组功能测试和三组映射结果均已核对原始 `result.json` 的SHA-256。它们是既有验证结果，本次没有重新运行RTL仿真、PDS或板测。单发射旧跑分、板上采样和数字WB观测IPC在技术文档中分别标注配置；未据双发射CoreMark推算退休IPC或最高频率。

CPU结构依据文件及其哈希同样保存于 `benchmark-index.json`。主工程中的RTL未在本次文档任务中修改。
