# F4c2a 采集核多帧重武装验证

日期：2026-10-20。基线：`013632f`。本批为可选采集组件，未操作板卡、串口或JTAG。

## 已实现的行为

入口和三分支核增加默认关闭的`ENABLE_REARM`。默认实例及旧采帧ABI1仍为单次。
显式开启时，上一帧good EOF、raw/preview/input数量与CRC合格、全部写响应退休、
accepted及成功completion消费后，核才允许下一CPU选槽请求；还须FIFO输出无残留、
writer可接描述符、仲裁器空闲及链路健康。调用方先复制整记录，再握手消费。

新请求同步清理空闲packer、preview/bilinear及每帧统计，然后发新描述符，待input
上padding写完再arm。入口健康STOPPED接收新arm，清理源端坐标/CRC/计数后等完整
新帧首；重arm与frame_start同拍时跳过该源帧。FIFO指针和DMA复位不按帧重置。
CPU全局三槽与显示/NPU引用资格继续由`video_frame_pool`负责。

失败、离线或采样到的晚到abort/overflow/source_fault锁止后续工作。已发布的成功
记录不撤回；尚无新job的IDLE健康错不制造旧frame_id的第二个完成。错误恢复仍要求
可信的协调排空和新代际，不允许通过新请求清错或复位在途AXI。

## 数字验证

```powershell
python scripts/video/run.py --suite capture_rearm
python scripts/video/run.py --suite three_capture
python scripts/video/run.py --suite capture_ingress
python scripts/video/run.py --suite capture_mmio
python scripts/video/run.py --suite frame_pool
python -m unittest discover -s tb/video -p test_*.py
```

新套件20场景，共109个完整成功帧。接真实双时钟ingress、Gray FIFO、流寄存器、
两路缩小、三个writer及仲裁器，AXI从端为有背压/延迟响应的数字模型。每帧换源图
和槽，独立坐标公式逐字节核验raw、2×2 preview、5:2整数双线性BGR NCHW、零补行，
检查stride空隙、槽地址、重复写、CRC、数量与完整记录稳定性。

| 场景 | 检查内容 |
|---|---|
| normal/minimum/ratio | 7/10/7帧，三槽循环、最小几何、非整数异步时钟比、FIFO多轮回绕 |
| case1/2 | accepted保持到所有写退休后；合法下一请求跨成功完成消费排队 |
| case3/4 | 成功后离线不撤回记录；第二次arm前停止像素时钟并恢复 |
| case10/11/12 | 分别在已公开AW/W/待B阶段abort，稳定保持并排空 |
| case13/14/15 | 接收模式错误、错误BRESP和无源超时，失败消费后仍禁止重用 |
| case20..25 | DONE/IDLE的单周期abort/overflow/source_fault均粘滞锁止，无第二完成 |
| full | 800×600、40MHz像素/125MHz核，三帧、6,321,600有效字节精确核验 |

`three_capture`48份、`capture_ingress`9份、旧`capture_mmio`2份和实际C到显示RTL
`frame_pool`1份仿真日志通过。Python106项中105通过，1项Windows符号链接权限跳过。
未重跑全部`all`套件；旧板级默认实例不因参数增加而自动启用多帧。

原始RED先用未修改生产RTL成功采完第一帧，再因第二请求被阻止而失败，见
`build/video/capture_rearm_red/result.json`。七项独立变异分别破坏预处理clear、CRC
清零、完成事件消费、入口重arm、源坐标清零、全部写退休及晚到错误粘滞，均由
指定行为断言检出。临时变异源码和日志位于忽略的`build/video/capture_rearm_mutations/`。

独立审查复现六个晚到错误脉冲被忽略的RED；修复仅扩展启用多帧时的分类，并在
IDLE健康错时避免重复完成，六项GREEN及同拍排队请求对错误的拒绝均通过。另检验
成功发布边沿错误、残留m_valid、源端首arm/重arm碰帧首、EOF等待时停像素时钟、
已退休accepted背压和默认关闭时仍单帧。最终审查无未关闭发现，原始证据由机器
摘要绑定，不把审查者的独立场景重复计入上面的20场景。

## 综合估计

```powershell
python scripts/video/build_pds.py --target video_capture_rearm --stage synth
```

PDS 2022.2-SP6.4综合的是固定默认几何、显式开启rearm的**核wrapper**，不含入口
双时钟FIFO、真实HDMI/DDR或板级管脚。4273 LUT、2876寄存器、1.5 DRM36K、2 APM、
0锁存器。8ns core约束下寄存器路径估计setup +1.578ns、hold +0.428ns。
边界I/O未约束，806个组件逻辑端口不是可落板的外部管脚需求或时序签核。

编译保留既有函数临时变量、不可达case、常量timer及constant-probe loop警告。
独立人工锥检查表明新增req_ready/job_clear路径未形成组合反馈：请求就绪依赖
已注册控制/writer状态、仲裁器状态及外部健康/输入；job_clear只去预处理，不反向
进入DMA请求READY。编译器没有给出具体probe环路径；本结论是源码锥审查，未作
完整层次网表图证明，不将警告消失或组件综合解释为物理闭合。

## 交付边界与下一步

精确来源、结果、工具、RED/GREEN、独立审查和产物哈希见
[机器摘要](evidence/capture_rearm.json)。399个其他已跟踪文件、29个其他路线已有
文件和两项原有删除保持；runner/builder移除新增入口后与基线逐字节相同。

没有新采集MMIO命令、生产CPU执行、共享fabric/DDR仲裁与跨master写可见性、真实
像素/素材退休生产者、连续视频或NPU推理。未布局布线、未下载、未Flash固化，
也未扩大既有板测结论。下一批将CPU槽预留/整记录消费接到版本化采集控制接口，
再与显示引用和共享DDR排序一起做多帧系统联测。
