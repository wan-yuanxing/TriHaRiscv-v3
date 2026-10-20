# F4c1 CPU统一三槽与整图生命周期

基线`9f39ee0`，设计见[frame-pool](../../superpowers/specs/2026-10-20-frame-pool-design.md)。
本批新增CPU侧C组件，生产Video RTL、旧采帧/显示ABI和板级目标保持字节；没有新增
PDS构建、CPU执行、DDR共享可见性或现场板测。

## 统一所有者

`video_frame_pool.h/.c`由单一CPU主循环串行调用，IRQ只排队。三槽地址继续来自
公共video_cfg：raw A/B/C为0x82000000/0x82200000/0x82400000，preview+0x160000，
320KiB input A/B/C为0x82800000/0x82850000/0x828a0000，实际张量307200B。
分配返回完整身份和对应地址/stride/预处理版本，轮询仅选FREE槽；至多一个采集，
没有空槽时不覆盖并保持输出参数原值。frame_id在epoch内全局递增且非零，耗尽后
停止，必须协调清空并更换generation；不会把数值回绕解释成新的旧事件资格。

正常阶段为FREE→CAPTURING→READY→PROCESSING→READY_DISPLAY→DISPLAY_PENDING→
DISPLAYING→RETIRING→FREE。DISPLAY_PENDING是软件对已预留显示记录的细分，
不改变任何硬件寄存器或采帧ABI。READY/READY_DISPLAY可在尚无引用时显式丢弃，
保存身份与原因；其余状态不能借丢弃绕过消费者。

CAPTURE_DONE调用者必须已核对同帧三分支、good EOF/计数及全部写响应；失败完成也
要求相关写已排空。graph_begin选择最早READY并锁定唯一frame_owner，算子间IDLE
不能接另一帧；最后算子完成后仍要等后处理发布及共享工作区无消费者，才清整图锁。
无脸也要经过实际处理资格，不从空模板推断推理成功。

软件32bit算子ticket首值任意，同图后续必须加一（模32bit），支持UINT32_MAX→0，
但issued到UINT32_MAX前后不允许整个标签空间循环。拒绝重复/跳号begin，保持原租约；
done必须精确匹配frame/generation/slot及ticket。真实NPU的tag位宽和寄存器映射仍
由后续适配层冻结，这个CPU内部规则不是新的NPU硬件ABI。

## 显示和错误

present先持有全局显示引用，再调用既有video_display_submit写完整640B记录。
返回OK只是发布校验任务；实际commit快照必须匹配唯一在途身份、mode/seq及
mode_only。同帧MODE继续持有当前槽，不增加新帧commit计数。新帧必须比当前已
commit的frame_id更新；旧READY_DISPLAY可以记录原因后丢弃，不能倒退显示。

poll_display完整验证commit/release/reject快照，再调用平台fence和ACK；只有ACK
成功才改active/pending/FREE。允许同快照中先提交新帧、再释放旧active；也允许多个
旧槽在RETIRING等待分批确认。新帧被拒绝返回READY_DISPLAY，同帧MODE拒绝保留原图。
发布或ACK报错可能是设备已执行但软件没收到成功，故保守保持引用并进入恢复，不
回滚成FREE，不自动重试。错误身份/重复/提前事件不ACK、不推进其他帧。

首错阻止新分配、计算和显示，但合法晚到反馈仍可排空。invalid只撤销数据资格，
内部租约阶段仍保持，不能靠“INVALID”抹掉在途访问。recover仅消费完整的capture/
compute/display/mailbox协调清空证明及不同generation；单独清软件、NPU IDLE或
DMA busy=0均不够。测试验证证明消费规则；实际证明、不可缓存映射、跨master可见性
和物理fence必须由正式平台集成后验收。

统计按epoch饱和：no_free是分配失败尝试次数，并非实际HDMI丢帧数；display_commits
只统计新的实际commit，不等于RGB流水末端SHOW_FRAME_FIRST或真实有效输出fps。
MODE、拒绝、释放、丢弃及首错另计，不混入推理或有效输出计数。

## 运行与证据

```powershell
python scripts/video/test_frame_pool.py
python scripts/video/run.py --suite frame_pool
python scripts/video/run.py --suite display_mmio
python scripts/video/run.py --suite display_slots
python scripts/video/run.py --suite capture_mmio
python -X utf8 -m unittest discover -s tb/video -p 'test_*.py'
```

使用既有MinGW GCC6.2实际运行11场景，180次发布/读取/ACK回调失败逐次注入，
含“设备执行后返回失败”的保守引用测试。1000帧有独立held mask的延迟退休压力
检查无活槽覆写，整图算子间隙/后处理锁、frame/generation/tag、MODE、拒绝和恢复
均自校验。xPack GCC15.2实际编译RV32I/ILP32对象，nm检查无malloc/memset/memcpy/
printf依赖。RV32I对象仍引用libgcc的__umodsi3及三个既有显示驱动函数，正式固件
链接和RISC-V CPU/总线运行仍需另验。

真实C输出81次读、1149次写、15次fence调用及6次实际命令、2次退休证明、1次拒绝
驱动记录。SV回放使用既有video_display_mmio/guard/owner，逐字核对完整记录及读值，
含独立AW/W与B/R背压、三次MODE、错误版本拒绝后重试、commit/release合并及延后
释放。采帧/NPU完成是合成资格事件；显示端点才是本次实际RTL联测对象。

旧显示MMIO10场景、显示owner13场景、采帧MMIO两组及Python105通过/1项Windows
符号链接权限跳过。11个策略变异均在指定原生断言失败，未以编译失败代替检出。

空实现最初在分配身份处实际RED。后续发现同图tag可复用，旧done可能匹配新算子；
先保存reuse和标签计数耗尽RED，再加顺序/issued规则到GREEN。原始RED源码及失败
日志均保存。回放初版触发已安装Icarus的case(string)内部崩溃，最小string_scan/
string_case/packed_case对照证明来源；改为定长ASCII操作字后通过，未改生产RTL。

独立审查8组/65153次检查、183个MODE回调失败点和3类不确定写入通过；另以
70读/985写/5命令/2退休/1拒绝的实际C记录回放生产RTL，覆盖两个旧槽同时RETIRING、
反序释放、MODE拒绝、MODE+旧槽释放同快照及错误后合法反馈排空。两项独立标签
变异均被指定断言检出，当前无未关闭发现。19条审查命令、56项审查产物及164项
外部引用由交付审计核验；243项旧冻结来源和31项其他路线文件保持字节。

机器摘要[evidence/frame_pool.json](evidence/frame_pool.json)绑定当前来源、工具、原生/
RTL、变异、独立审查和保留字节。后续F4c2实现采集受控rearm、CPU/fabric显示子译码、
共享DDR仲裁与实际commit/全部引用退休生产者，再验收多主争用和连续采集。真实NPU
模型执行、输出槽ABI及tag映射仍需独立交接。
