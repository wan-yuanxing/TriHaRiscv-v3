# NPU合拢准备：CPU算子表、地址与资源检查

日期：2026-10-21。承接用户批准的“方案收敛→最小算子闭环→完整推理/视频”路线。本批范围是可重复的主机准备工具和合拢契约，下一批再实现最小算子RTL。用户本轮明确：最终功能保留五点关键点，bbox仅作中间验证。

## 选择与边界

沿用主规格v0.6：CPU逐算子启动，NPU内遍历tile，整图所有权由CPU帧池保持。外部79算子程序仅作为离线模型包；由准备工具提取为C常量表，硬件无需整图取指。直接采用外部图控制器会改变主规格和驱动；自行重新制作全部算子参数会重复现有数值交付。推荐离线适配，可保留原程序身份和整数定义。

本批C表包含原始算子记录、张量/参数元数据和重定位地址，**不是OP_PARAMS寄存器编码或可运行NPU驱动**。必须在真实算子端点定义后完成字段到MMIO映射、CPU执行、DMA和错误路径验证。原始Sigmoid等算子不删改，CPU后处理不得重复执行模型包已有运算。

当前bbox数值包只允许中间验证；最终交付必须有kps_8/16/32及相应量化、逐层参考、地址和资源重新验收。不能把缺失关键点填零后报告最终功能完成。

## 地址与装载

主公共配置`config/video_cfg.json`继续提供三个输入槽：0x82800000/0x82850000/0x828A0000，各320KiB、张量307200B，直接绑定上游生产地址。新`config/npu_integration_fixture.json`只保存本批主机候选布局，不发布为板级ABI。

CPU私有0x80000000–0x81FFFFFF、共享0x82000000–0x87FFFFFF；本批DDR窗口128MiB。完整覆盖并互斥检查主规格九个共享大区，三帧槽/输入槽从Video配置读取且核对主规格分配。

输出候选槽A/B/C：0x82900000/0x82920000/0x82940000，每槽128KiB。当前九头按256B对齐紧凑排列，尾部保留；未来关键点须按实际包重新检查，67200B只是未对齐的16值/位置INT16算术下限。

权重/数值参数镜像放0x82B00000，CPU算子表装载候选区从0x82B20000开始。内部张量在0x83300000起按原model_offset保持布局；外部input/九头替换为对应槽地址，原内部洞保留，不据此宣称内存生命周期优化。参数地址按`weights_base + model_offset - parameter_image_model_offset`转换，避免把模型参数偷偷放入主规格中间张量区。

这个转换是**CPU算子表新适配格式**，不能原样交给外部任务ABI：外部任务ABI仅绑定input/heads，其参数仍按workspace+model_offset解析。外部descriptor、CMD_ID和图级控制器保持诊断用途，不安装成主工程寄存器定义。

表以自描述小端`npu_cpu_table.bin`供未来装载器写入候选DDR区，生成C头默认通过该基址指针读取。表超过8KiB Boot ROM，不得默认嵌入ROM；只有定义`TRIHA_NPU_EMBED_HOST_TABLE`才嵌入常量数组，用于本批编译/字节一致性验证，尚未提供真实板级装载器。

## 身份、完成与总线

正式任务沿用(frame, generation, op_tag)，均u32，单帧逐算子。软件表索引与operator ticket不是CMD_ID。若后续使用外部诊断descriptor，可将frame零扩展到u64、generation映射epoch，但必须拒绝非零frame_hi、旧generation及不匹配ticket；回绕前停止接纳，完成协调排空后更换未复用generation。当前C帧池只检查generation不同，长期epoch不复用仍需上层实现。

CPU/NPU实际共用100MHz计算域；AXI128/HMIC256桥仍在125MHz，唯一HMIC owner。NPU本地256bit在计算侧转换为AXI128后经过统一CDC接入共享fabric。CDC/仲裁不能靠本批地址表或软件延时证明。

INPUT_READY须晚于三分支全部写完成；单算子DONE须晚于所有输出成功响应；整图RESULT_READY还须CPU后处理完成。现桥读回匹配只证明同一独占native通路所见，跨master交接、错误排空和协调复位必须另做RTL/实物验证。

## 资源方案

按现有证据读取Video73.5DRM、其中头像cache64DRM；NPU控制预算保守使用100.5DRM（规划值），不能把原语探针相加。CPU已验证dc00f80核为0DRM/4APM；ROM8KiB+SRAM32KiB另按32bit有效载荷4KiB/DRM预算10DRM，当前集成候选无I/D cache。fabric/CDC额外预留8DRM，后续以实际清单替换。

- 原样叠加：73.5+100.5=174，超过155，未计CPU外设。
- RAW准备场景：暂减去64DRM头像缓存，另加CPU10与fabric8，合计128，算术余27。
- 最终头像候选：在RAW预算上给DDR素材缓存上限16DRM，合计144，算术余11；必须实现按需DDR读取并验证显示行截止时间，才可替换64DRM缓存。

减项只是规划场景，尚无已实现RAW合并顶层；NPU LUT/FF/布线、RAM端口/碎片、全系统带宽仍未知。任何正余量都不得设置hardware_ready=true。模型扩展五点后重新预算，不能继承当前bbox候选的通过状态。

CPU侧现有100MHz通过证据位于独立工作树`docs/verification/cpu/operand_hazard.json`，对应dc00f80；主工程CPU未合入，当前CPU工作区另有未完成load-return实验。本批只读取已发布证据，不复制实验源码，也不据文档推断当前板卡镜像。

## 工具与验收

Windows/Python标准库入口`python scripts/npu/prepare_integration.py --npu-root ../npu_zgtc --program ../npu_zgtc/build/integration_audit/20261020/program.bin --parameters ../npu_zgtc/build/integration_audit/20261020/parameter_image.bin`。读取提交清单和数值资产、校验模型/程序/参数SHA256，解析小端定长记录，验证原始布局、ID/依赖顺序、地址范围和参数所有者。输入/产物记录SHA256，独立新目录保留失败结果，禁止覆盖已有成功目录。

生成三槽完整地址JSON、离线C表和参数镜像、分阶段资源场景及开放门槛。正常准备退出0只表示主机准备成功；`--require-hardware-ready`在未通过真实工程门槛时退出2。损坏资产、重叠/越界、字段非法等退出1。

先写能失败的测试，再实现。正例验证三槽、全部张量/参数/79算子及ARM无关的RV32I头文件编译；负例覆盖损坏二进制、地址重叠/越界、输入格式、输出容量和ID/依赖等。独立读取生成C/JSON比对、检查旧工作区文件未受本批影响。该验收不包含硬件推理、物理DDR或板卡下载。
