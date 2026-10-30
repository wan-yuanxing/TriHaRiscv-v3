# NPU首个真实算子闭环

承接用户批准的单算子MMIO→真实计算→DMA回读路线。本批在隔离工作树`D:/FPGA/TriHaRiscv-npu-operator`实现，基于主工程d079e757，不改独立CPU实验或Video开发文件。应用原生工作树入口因父目录非仓库不可用，已用Git建立分支npu/operator-loop；不是应用托管工作树。

## 验收范围

实现CPU逐算子、单通路普通/深度卷积。UINT8/SINT8输入、SINT8 Co16_K_lane权重、INT32 bias/累加、I32 multiplier/shift双字、I64乘积及有符号对称RNE、U8/S8/I16饱和输出；S8最小-127、I16最小-32767。支持1/3核、1/2步长、0/1对称padding，NCHW，输入W/H<=320、Ci/Co<=64；输出严格按卷积公式推导，此组合在kernel1/padding1/stride1时最多322，不另按320截断。DW要求Ci=Co，权重K=kernel²。

单通路优先验证真实整数行为，不把它称为64/128路完整NPU或性能达标。三个只读16B行缓存分别服务输入、权重和bias/requant；每输出元素带WSTRB写AXI128，逐B响应成功后才推进。参数/输入/输出地址锁存，输出不得与输入、权重、bias、requant区重叠。所有访问在0x82000000..0x87FFFFFF，基址16B对齐，派生范围用扩展位宽验证，不让溢出回绕。参数镜像与tensor地址遵循上一批候选，CPU不复制输入像素。

## 模块与共同接口

全部新RTL直接维护Verilog，四空格、ANSI端口、clk_i/rst_ni、u_*。

### npu_axi128_single

一个客户端事务到完整AXI128单拍INCR转换，SIZE=4、LEN=0、ID=0；固定16B对齐，每次完整128MiB逻辑窗口检查（0x80000000..0x87FFFFFF），WSTRB至少一位。不实现CDC；所有接口同一计算时钟。

客户端输入：req_valid_i, req_write_i, req_addr_i[31:0], req_wdata_i[127:0], req_wstrb_i[15:0]；输出req_ready_o。握手后下一拍起可返回rsp_valid_o（单拍脉冲）、rsp_rdata_o[127:0]、rsp_error_o。最多一个在途事务，客户端在握手前稳定请求。

AXI输出m_axi_arid_o[3:0]/araddr_o[31:0]/arlen_o[7:0]/arsize_o[2:0]/arburst_o[1:0]/arvalid_o/rready_o、aw对应同名尺寸、wdata_o[127:0]/wstrb_o[15:0]/wlast_o/wvalid_o/bready_o；输入对应ready_i，rid_i[3:0]/rdata_i[127:0]/rresp_i[1:0]/rlast_i/rvalid_i，bid_i[3:0]/bresp_i[1:0]/bvalid_i。

AW/W独立握手，稳定等待任意背压；响应ID/RESP/LAST错误必须报告并锁存fault_o，阻止新请求至协调复位。单拍R收到LAST=0时排空至LAST再报告错误，不提前复用未完成通路。不用固定等待当作完成；不设把合法背压认作超时的看门狗。fault_o既供状态也使MMIO拒绝后续START。

### npu_operator_mmio

同钟AXI-Lite控制，完整32位s_axi_awaddr_i/araddr_i；wdata32、wstrb4、bresp/rresp2、rdata32、标准valid/ready端口，无PROT。BASE=0x20000000，4KiB窗，字对齐；不合法地址DECERR，非法/只读写SLVERR。AW/W可任意先后，最多一个写响应和一个读响应，背压时保持稳定。

输入engine_busy_i、engine_done_i、engine_error_i、engine_error_code_i[7:0]、engine_total_cycles_i/engine_compute_cycles_i/engine_dma_wait_cycles_i[31:0]、platform_fault_i。输出start_o单拍、irq_o、frame_id_o/generation_o/op_tag_o[31:0]及以下cfg_*_o。

cfg_input_base_o/cfg_weight_base_o/cfg_bias_base_o/cfg_requant_base_o/cfg_output_base_o[31:0]；cfg_input_width_o/cfg_input_height_o/cfg_output_width_o/cfg_output_height_o/cfg_input_channels_o/cfg_output_channels_o[15:0]；cfg_kernel_o/cfg_stride_o/cfg_padding_o[1:0]；cfg_depthwise_o/cfg_input_signed_o；cfg_output_format_o[1:0]。shadow在接受START即冻结，active从接受时置位（不等engine_busy上升），直到engine_done；参数和身份仅非active且IRQ_PENDING=0可写。

START只在非active、无completion待ACK、engine_busy=0、platform_fault=0接受；拒绝返回SLVERR且不改变活跃任务。DONE或ERROR产生对应sticky IRQ bit，W1C清除，同拍新事件优先。支持poll/irq，状态读不清事件。CONTROL不支持异步abort，严重DMA错误要求统一复位。

寄存器由config/npu_regs.json统一生成rtl/npu/include/npu_regs.vh与sw/include/npu_regs.h。ID_VERSION=0x4E500001；CAPS=0x00010003（Dense/DW、1lane）；CONTROL=0x08；STATUS=0x0C（bit0空闲、1busy、2done、3error、4platform_fault）；IRQ_STATUS=0x10、IRQ_ENABLE=0x14、ERROR_CODE=0x18、OP_TAG=0x1C、FRAME_ID=0x20、TOTAL/COMPUTE/DMA_WAIT_CYCLES=0x24/28/2C、GENERATION=0x30。

参数：INPUT_BASE=0x100、WEIGHT_BASE=0x104、BIAS_BASE=0x108、REQUANT_BASE=0x10C、OUTPUT_BASE=0x110、INPUT_WH=0x114（宽low16/高high16）、CHANNELS=0x118（Ci low16/Co high16）、OUTPUT_WH=0x11C、KSP=0x120（kernel[1:0]、stride[9:8]、padding[17:16]、DW[24]）、FORMAT=0x124（input_signed[0]、output_format[9:8]：1U8/2S8/3I16）。未定义位写非零拒绝；普通shadow支持WSTRB合并，CONTROL START要求全字写值1，IRQ_STATUS支持W1C有效字节。

### npu_scalar_conv与顶层

root负责npu_scalar_conv：start_i及上述cfg_*_i，busy_o、done_o（成功/失败共同单拍）、error_o（失败保持至下一START）、error_code_o[7:0]、total_cycles_o/compute_cycles_o/dma_wait_cycles_o[31:0]。命令输入npu_axi128_single相同接口但引擎输出mem_req_valid_o/mem_req_write_o/mem_req_addr_o[31:0]/mem_req_wdata_o[127:0]/mem_req_wstrb_o[15:0]，输入mem_req_ready_i/mem_rsp_valid_i/mem_rsp_rdata_i[127:0]/mem_rsp_error_i。所有配置在start锁存。

配置错误code1、累加溢出2、数值shift错误3、存储响应错误4。拒绝非法配置时不得产生DMA。INT32加法采用33位溢出检查；64位重定标按绝对值舍入、tie选偶，再恢复符号与饱和。不增加零点偏移。shift从参数第二I32取0..63，非法使整算子失败。缓存每个START失效，禁止跨任务保留旧输入/参数。

npu_operator_top组合三模块。CPU native AXI-Lite适配器新增可配置MMIO前缀，默认0x2001保持Video行为，NPU实例用0x2000；旧cpu_axil回归必须通过。

## 验证与交付

先写独立Python整数oracle与自校验TB，再实现。DMA模块TB覆盖AW/W先后、AR/R/B随机延迟/背压、ID/RESP/LAST错、非法地址/空WSTRB、错误锁存和协调复位；MMIO TB覆盖AW/W先后、读写响应保持、partial write/只读/未知/越界、start锁存、busy拒绝、W1C、identity和platform_fault。

算子数值覆盖Dense/DW、U8/S8、各输出格式、尾通道、padding/stride、正负tie/饱和、bias和INT32溢出、非法参数/alias/越界、DMA错误及复位后重跑。最后冻结已验证CPU提交dc00f80，从Git blob导出到build仿真副本，运行RV32I固件：真实MMIO启动→真实卷积→AXI DDR字节模型→CPU逐元素读回，含poll与IRQ场景。独立预置oracle数据为比对依据；不得在TB直接向完成状态塞golden。

周期计数饱和在0xFFFFFFFF，CPU不得把饱和值视为精确周期测量。接口544位过多，组件PDS用542个扫描边界寄存器保持全部非时钟/复位输入可控制、所有输出可观察，分别报告包含该诊断边界的资源与100MHz时序，不声称实际SoC外部总线时序。

组件/CPU联测与PDS实现分别报告。100MHz组件布局布线可验证时，运行独立目标；真实DDR IP、125MHz/100MHz CDC、全系统fabric可见性、CPU主工程正式合入、完整网络、五点INT8、板测及fps保持开放。任何仿真模型不称为物理DDR或上板推理，本批不自动JTAG/Flash操作。
