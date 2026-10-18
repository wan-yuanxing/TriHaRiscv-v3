# 检测输入通道、补行与C8格式组件设计

基线09fd86d。用户已确认NPU清单尚未提供、先推进独立Video组件，并授权继续BGR/补边/C8接口阶段。本设计沿用v0.6第6.3节，不引入临时量化尺度，不发布正式INPUT_READY/CAPTURE_DONE。

## 分层选择

| 方案 | 影响 | 选择 |
|---|---|---|
| raw BGR/补行与量化后C8打包分开 | 量化处于正确的中间位置，模型参数未到也能验证几何/字节布局 | 采用 |
| 把未量化的0..255像素直接当INT8打包 | 会误建正式张量，负值/饱和及量化零值错误 | 不采用 |
| 等完整NPU交付再开始全部格式逻辑 | 无法独立推进已冻结的布局部分 | 不采用 |

## detect_input_pad

新增`rtl/video/detect_input_pad.sv`。单core域、ready/valid，默认160×120 RGB888输入，输出160×128 raw BGR，底部8行原始零像素。`s_rgb[23:16/15:8/7:0]`分别R/G/B；`m_bgr[23:16/15:8/7:0]`分别B/G/R，转换为真实字节交换。每个输出附row_last、frame_last、padding三个标志；padding只表示原始零补行，不代替量化零值。

宽1..2048，有效高1..2048，存储高在有效高..2048，允许零补行。一次clear/reset只处理一帧。一个输出寄存器，受阻保持，消费可与新源像素接纳或下一补行像素生成同拍。输入计数按接纳推进，补行计数按输出项生成推进；末项生成后停住，额外输入置fault。

未知RGB、未知/错误row_last在被接纳时置sticky fault；无效payload不发布。补行阶段额外输入也置fault并停止新生成。fault不能撤销已公开的VALID；协调clear/reset可取消输出及帧状态。只在握手时解释payload，blocked未知值不能误触发fault。

## detect_c8_pack

新增`rtl/video/detect_c8_pack.sv`。请求`req_valid/req_ready/req_zero[7:0]`锁存外部提供的逐张量量化零值，无默认尺度/零值。请求被接纳后才接收` s_q_bgr[23:16/15:8/7:0]`的B/G/R三个量化字节及row_last/frame_last/padding元数据。元数据必须匹配本帧坐标，补行三个有效通道必须等于请求零值；数据只按8bit编码搬运，不解释或计算量化尺度。

每像素内存8字节依次B,G,R,zero,zero,zero,zero,zero。两像素打为一个128bit beat，先像素位于低64bit，通道0位于最低字节。偶数宽行keep=ffff；奇数宽尾拍keep=00ff，高64bit清0且无效，不跨行混装。默认160×128得到163840有效字节、10240拍；行1280字节。输出含row_last/frame_last，保持至ready。

输入/请求未知值及错误元数据置fault，停止接纳；已公开输出保持。最后一拍消费后才置本地done；fault撤销done。此done只表示打包流已退休，不代表DMA写响应完成或正式INPUT_READY。clear/reset恢复等待新请求，可取消半拍或已公开beat。

## 验证边界

先写会因缺模块失败的自校验测试，再实现。独立oracle从坐标和规范字节序计算，覆盖默认全尺寸、奇数宽/单像素/零补行、所有通道字节值与非零量化零值、长背压/同时握手、四态payload与元数据、过量输入、半拍/末拍及补行时取消。

联测用明确标记的测试量化模型连接5×5 scaler→pad→测试量化→C8→既有video_write_dma，并用字节内存核对有效区、padding、stride保护、写响应延迟和最终成功。测试模型只证明接口/布局，不能成为真实模型尺度或板测依据。添加独立input_format套件、显式组件综合目标、资源和估计时序记录；不改已验收板级HDMI/DDR源码及125MHz/6ns/5秒约束。
