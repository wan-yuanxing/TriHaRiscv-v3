# F3c 前置：模式CDC与封存素材缓存

基线`248d538`，实施范围为[板级计划](../../superpowers/plans/2026-10-19-display-mode-board.md)
Tasks1..4。两组件是后续独立三模式目标的前置；本检查点尚未连接实体MODE、raw像素
流水或三模式板级顶层，没有新位流/板测。板卡仍保留F2静态全屏镜像。

## 组件行为

`display_mode_cdc`通过单在途toggle/mailbox保持整个mode/seq/frame/slot/generation/
参数化context，从core送到pixel。pixel接纳只进入等待，消费者在真正显示提交后
另发`pixel_commit`才返回ack；core反馈保持至ready，消费前禁止接新命令。反馈身份
来自仍受保护的core mailbox，不重新跨回宽bundle，不依据32bit序号相等判断新旧。
提前/重复pixel_commit置sticky协议故障，不形成正常反馈；协调复位清除双域事件。

`avatar_texture_cache`默认装载65536个RGBA8888字，共262144B。先接纳身份，再逐字
接纳流；只允许末字带last，完整且已定义的像素全部写入后才发布ready。错last或
未知字/身份使装载失败sticky，部分RAM不会成为可显示素材。装好后写口永久封存，
每次协调复位只有一次装载；不支持运行中替换或单域复位。RAM内容不依赖reset清零。

ready两级同步后pixel捕获稳定身份。每个请求在一个像素边沿读取同步RAM，并同时
注册valid/error；下一边沿前输出保持。非对齐、越界、身份错或未就绪在原响应槽
报告error，不滑动/丢弃请求，RGBA可未知，F3b负责退回原图。这是封存缓存，不是
DDR素材DMA或通用引用管理器；正式素材替换、全部引用退休和共享可见性由F4完善。

## 验证

```powershell
python scripts/video/run.py --suite mode_resources
python scripts/video/run.py --suite overlay
python scripts/video/run.py --suite mode_control
python -m unittest discover -s tb/video -p test_*.py
python scripts/video/build_pds.py --target video_mode_cdc --stage synth
python scripts/video/build_pds.py --target video_avatar_cache --stage synth
```

最终组件16场景：CDC5类及7/513bit和反向快慢时钟，缓存6类及1字/完整65536字。
覆盖payload背压、接纳/实际提交分离、反馈背压、seq回绕、三个在途阶段协调复位、
提前/重复commit、末字门槛、装载停顿/失败、全部65536字首末及全速读回、封存防写、
错身份/地址/未就绪和reset后新素材不借旧RAM。采样沿前保持断言另外拒绝组合零
延迟响应。提前反馈、提前ready及组合响应RED替身均被当前测试非零拒绝。

同时重跑F3b叠加12场景及F3a控制24场景，共52份仿真PASS日志；Python85项通过、
1项Windows符号链接权限跳过。未重跑完整all。冻结F3a完整37套件/198输入中，196
项原字节一致，run.py/build_pds.py两项仅扩展新入口；F3b与raw来源保持原样。
独立审查192个完整CDC事务、19个缓存边界响应通过，组合零延迟及额外一拍RAM读
延迟两项突变均非零失败；当前未解决实质发现为0。11个审查文件与86项证据产物
哈希已由父进程核对。独立审查与父哈希复核的明细见[evidence/mode_resources.json](evidence/mode_resources.json)。

## 综合与物理边界

MODE CDC综合9 LUT/470寄存器/0 DRM；core/pixel本域slow setup估计分别+6.038/
+22.656ns，稳定bundle的6ns约束估计余量+5.224ns，本域hold+0.619ns。
素材缓存综合98 LUT/186寄存器/64 DRM36K；本域slow setup估计core+3.991、pixel
+21.793ns，6ns身份bundle+5.224ns，本域hold最低+0.619ns。两者均0 APM。

约束保留8ns core、25ns pixel，只对标量第一级作异步例外，宽bundle仍受6ns限制。
当前没有布局布线；PDS综合提示忽略ASYNC_REG属性，后续须以存活网表端点、级间
路径和实际物理时序核对同步结构与放置，不能依赖属性文本宣称物理CDC闭合。
组件目标只支持synth，尚不构成可下载文件或外部HDMI AC签核。

## 硬件管脚核对

官方硬件指导手册2.1.3.4.1，PDF物理第50页/印刷第46页，按键电路为A3V3上拉
10k、0.1μF滤波、按下接地；表列KEY1=C23、KEY0=C22。官方按键例程FDC的C23、
3.3V、LVCMOS33属性一致；来源哈希与该页渲染保存于`build/video/mode_key_audit/`。
这只是资料交叉核对，实体去抖/切换仍须后续板级验收。

下一步执行计划Task5的独立板级衔接，再做Task6实际Program/Verify、三模式及KEY0
验收。公共地址、正式显示MMIO、NPU模型和CPU工作树未变。
