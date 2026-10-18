# YuNet 320 BGR NCHW 行式 DMA

实施计划为 c8bbaf6，沿用已接受的320输入设计。本批组件
`detect_nchw_dma`接收320×240有效RGB888，上下各写40行零，按B/G/R三平面
产生320×320 UINT8张量，共307200B。每平面102400B，偏移为0、0x19000、
0x32000；不除255，不增加量化。

## 实现与边界

组件仅缓存一行WIDTH×24bit RGB，默认7680bit。同步RAM不复位，每行完整
覆盖后才读。逐行先收集RGB，再按B、G、R顺序读取同一行并提交三个独立行
描述符；padding直接生成零，不访问旧行RAM。每16个单通道字节组成128bit
流，行尾仅置连续低位keep，不写stride和plane间隙。

复用既有`video_write_dma`，保留最多16拍burst、4KiB拆分、AW/W保持和B退休
语义。新组件不改变桥、共享预览、125MHz/6ns束或既有5秒超时。只有全部行的
成功写响应才产生本地成功；结果保持到消费。abort/offline/故障停止收数，
排空已公开事务；错误需协调复位后再用，成功结果消费后可重新请求。

参数允许宽和有效高1..2048、非负上下补行且总高1..2048，row stride为16B
倍数、至少WIDTH且最多65536B；plane stride为16B倍数、至少row stride×总高
且最多128MiB。请求的最终总线拍必须完全位于0x80000000..0x88000000逻辑DDR
窗口。参数检查独立限制每项padding，避免有符号求和溢出。

## 验证内容

正式套件包含五种几何（宽1/3/16/17/320，零/不对称/40+40补行），每种六帧；
33个控制场景覆盖长AW/W/B和结果背压、末B暂停、错误/未知行末、未知RGB、
blocked未知payload、abort/online丢失、SLVERR/BID、未知/越界描述符、成功
无复位重用，以及stray B后再遇总线错误仍保留首因。13组非法参数在time0
拒绝，其中包括两组32bit高度溢出。

真实`detect_bilinear`与新DMA串联处理六幅800×600源图。测试从实际AW/WSTRB/
WDATA构建字节内存并检查guard、重复写、padding、平面和响应计数，再按NCHW
地址直接转储307200B；`check_nchw_dump.py`仅解码十六进制字节及计算SHA256，
不在软件中重排、补边或转换颜色。六份身份以先前冻结的OpenCV4.11结果为准。

独立审查复现并修复三项P2：STRAY B误报OFFLINE、非法padding求和溢出、
先到达的DMA错误被后到取消覆盖。正式
测试先RED复现再修复，旧失败快照保留；修复后的审查及完整回归结果、输入和
原始日志哈希由[机器证据](evidence/nchw_dma.json)绑定。

## 公共配置

`config/video_cfg.json`现定义UINT8/BGR/NCHW、scale1/zero0、预处理版本1，
并由同一生成器输出RTL与C常量。三槽分别为0x82800000、0x82850000、
0x828A0000，每槽分配320KiB、有效张量300KiB；原1MiB区末64KiB保留。
这次统一常量不等于CPU译码、槽所有权或NPU共享主端已接通。历史160/C8组件
保留其原验收范围；旧已验收板级目标未接入新input分支。

```powershell
python scripts/video/gen_config.py --check
python scripts/video/run.py --suite nchw_dma
python scripts/video/build_pds.py --target video_nchw_dma --stage synth
python scripts/video/run.py --suite all
```

`video_nchw_dma`只允许组件综合。综合资源及8ns估计时序见机器证据，不是
布线、外部AC或上板验收。本批没有JTAG/UART/Flash操作；尚未实现good EOF
与raw/preview/input三分支汇合、正式INPUT_READY、CPU fabric可见性及槽生命周期。

## 最终结果

最终完整回归`build/video/regression/20261018T110502_923511Z`通过30套件/151当前输入，162份仿真PASS日志及63项Python（62通过/1个Windows条件跳过）。独立复审79/79通过，父会话复核184项哈希。组件综合1223LUT/791FF、72个分布式RAM LUT、1个DRM18K、0APM，8ns估计setup+2.109ns/hold+0.428ns，2070个端点；这些是综合估计。
