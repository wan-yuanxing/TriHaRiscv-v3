# NPU技术文档仿真图与验证记录

技术文档附录C使用本目录归档的来源记录与10幅ModelSim Wave原生窗口截图。正文按测试对象、配置、观察过程和结果组织，图片保存于 `docs/technical-report/figure/npu-simulation/`。

## 来源

- 仓库：<https://github.com/keep-s/npu_zgtc>
- 固定提交：`3523d030ded5fc67f3324c54d8a1f1419ac90768`
- 来源目录：`word/triha-npu/`
- 上游文档与测试说明：`source-documents/`
- 每图原始来源记录：`provenance/`
- 本工程图片、源图SHA256与裁剪范围：`manifest.json`

此次工作整理已有仿真资料，没有重新运行RTL仿真、综合、布局布线或板测。原始VCD路径和SHA256按上游记录保存；VCD本体不在本次交付中。本次核对了下载对象的Git blob校验值、PNG的SHA256及原生窗口中的信号。

## 图片处理

`dense-accumulate.png`保留原图 `npu_dense_accumulate.png` 的上半幅，像素范围为 `[0, 0, 1516, 709]`，不缩放、不重绘信号。完整源图另存于 `originals/`。下半幅属于跨K分块保存与回装的组合测试，与正文的完整K归约数据通路不同，因此不用于本次说明。

其余9幅PNG与上游源图字节一致。上下窗口拼接来自上游原始交付，每个窗口的来源、时间范围及像素位置均见JSON记录。双窗口采用各自原始时间轴。

| 本工程图片 | 上游图片 | 正文使用范围 |
| --- | --- | --- |
| `dense-accumulate.png` | `npu_dense_accumulate.png`上窗 | M=16组件的K输入、提交与第0路累加器 |
| `dw16-tail-channel.png` | `dw16_case7.png` | Q4空间层17通道用例与层级计数 |
| `quantization.png` | `npu_q_rne.png` | 八物理通路量化单元的数值规则与保持行为 |
| `input-gather.png` | `npu_input_gather.png` | 驻留行命中和独立gather用例 |
| `output-mask.png` | `npu_output_mask.png` | 16×16缓存组合测试的尾部字节保护 |
| `dma-completion.png` | `npu_dma_retirement.png` | 独立桥、HMIC和DDR3器件模型的同端口功能读写 |
| `layer-mmio.png` | `01_layer_mmio_actual_vcd.png` | 单算子MMIO完成等待和故障响应 |
| `fifo-clear.png` | `03_fifo_payload_epoch_actual_vcd.png` | 载荷有效位适配的清空和重装载 |
| `vector-quantization.png` | `vector_q_requests.png` | Q4向量用例的原始状态编码 |
| `pool-resize.png` | `npu_pool_resize.png` | 空间层与块DMA的MaxPool/Resize末行完成 |

## 测试配置与统计范围

1. 当前文档的板级配置为M=2、单量化通路；组件图包含M=16、Q4和八物理量化通路，正文按各图测试配置表述。相应周期不作为当前板级配置的延迟或吞吐。
2. 第90篇的阵列回归记录223次接收、219次提交、4次清空，最终pending为0；缓存组合回归中的3840个O数据字与720个保护区数据字是整个回归集合的统计，不是7×9尾块单例的规模。
3. `o_valid`为512位有效字节位图。图中不含由位图置位数推导的计数曲线；向量图只有实际记录的状态和完成信号，不把推导的valid/ready当作直接观测。
4. 向量回归存在两套数据：第97篇的 `b03_vector_compact_fresh_v1` 为八通道量化配置，14例、150092 B；第107篇的 `b03_vector_quant_tdm4_dev02` 为Q4时分配置，9例、149212 B。上游主说明在Q4图附近引用14例总量，技术文档按两个原始记录分列，避免混用配置。
5. MaxPool、Resize和DW16图来自 `b03_layer_dma_release_dev01`，采用实际空间层、块DMA及片上原语，桥端为字节存储模型。数值结果依据上游主说明和第107篇记录。
6. 第46篇的HMIC器件模型运行包含24个本地突发、101写拍、101读拍和3232次字节比较。原始日志记录267条连接或端口警告与84条运行时警告；运行时警告为4条初始复位/CKE提示及80条写校准tWLS/tWLH提示，模型初始化等待沿用100倍加速。附录保留警告信息，只列示同一桥端口的功能比较，不据此认定板级时序或跨主机可见性。
7. 单算子MMIO的464项检查、FIFO适配的3202888项检查依据上游主说明第10.1节。截图展示选定时窗，完整检查数量来自对应回归记录，不能由截图独立计数得到。

## 证据位置

`source-documents/upstream-README.md`与 `upstream-sources_manifest.json`保留上游提交内容。第46、88、90、96、97和107篇测试说明按原文件名保存，用于核对桥传输、量化、阵列、输入复用、向量回归及Q4配置。原图元数据中的VCD哈希由上游给出，本次未重新计算原始VCD哈希。
