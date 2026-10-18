# RX像素分布诊断

现象：候选预览镜像已完成完整帧采集、CRC读回和无欠载扫描，但桌面及四角定位图都挤在窄条或缺角。现有统计无法判断错误是否发生在缩放之前。用户已授权持续实施、现场诊断和易失JTAG下载；本次在该范围内增加观测，不更改采集策略。

选择独立RX诊断镜像：沿用已验证RX的下降沿采样、几何监测、TX彩条和初始化，在geometry输出处统计完整好帧。相较再次调整等待帧数，这能直接观测输入；相较增加DDR整帧串口转储，资源和传输量更小。当前preview源码、构建入口、发布包及回滚路径不变。

每个完整好帧发布序号、像素数、非零RGB像素数及min/max坐标，四个象限中心RGB和逐R/G/B字节CRC32。黑帧合法：计数为0、边界为0xffff、取样及CRC仍发布。只有frame_start开始的完整好帧且计数等于宽×高才更新；坏帧/未闭合帧不发布。所有值经现有稳定总线snapshot通路跨到cfg域，不增加新CDC协议；一帧快照中序号和统计一致。

UART保留TRV1、32字节payload和XOR。类型8：4字节头(type,flags,version=1,reserved=0)，7个uint32为sequence,pixels,nonzero,x_bounds,y_bounds,q0,q1；bounds低16位min、高16位max。类型9：相同头，7个uint32为sequence,q2,q3,crc32,0,0,0。保留type1/3模式包，按完成发送循环1/3/8/9；每包内部一致，类型8/9须以同序号配对，不能跨帧拼接。

新增文件仅承担诊断：`rtl/video/video_rx_image_probe.sv`、`tb/video/tb_video_rx_image_probe.sv`、`fpga/pg2l100h/rtl/video_rx_image_probe_top.sv`、专用JSON及专用构建/读取脚本。原build_pds/package/program/read入口不修改，避免使当前preview包的来源绑定失效。构建冻结输入、厂商文件、约束及工具版本；内部时序通过后方可识别目标、Program/Verify。未验证外部AC或当前preview图像恢复。

验收：独立逐像素CRC/坐标oracle覆盖全彩、纯黑、局部亮区、坏帧、首末像素、连续好帧和中途复位；串口解码检查长度/XOR/版本/序号。现场保持四角图全屏，读取RX四象限及边界：若接收端已是窄条，继续查源/转换器；若接收端四象限正确，继续查缩放与扫描路径。诊断本身不能代替实际图像验收。
