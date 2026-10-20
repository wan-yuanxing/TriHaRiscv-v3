# F4a 显示引用三槽组件

基线 `511e6b5`。设计见[显示槽所有者](../../superpowers/specs/2026-10-20-display-slot-owner-design.md)。
本批只验证独立core域组件，当前已验收三模式板级RTL、配置与实际镜像未修改。

## 协议

`display_slot_owner` 运行在同一core时钟域，默认128bit参数化context。`submit_valid/ready`
在接纳边沿冻结mode_only、slot、frame、generation、raw base/stride、mode、seq及data。
新帧要求显示侧FREE槽、非零frame、公共A/B/C精确raw基址及2400B stride；MODE要求与
active的slot/frame/generation/raw/data完全相同，只改变mode和seq。mode只接受0/1/2。
调用方事先检查同帧结果、框、素材能力与范围，并负责新生命周期的身份新鲜度和时间顺序；
不得在仍可能有旧反馈时复用同一slot/frame/generation。context本身不是正式显示ABI。

独立拒绝通道保持`reject_code/seq`，原因1未知字段、2slot/frame非法、3raw布局非法、
4mode非法、5目标槽非FREE、6MODE上下文不匹配。拒绝不置协议错误，不改变已有引用。
被拒绝seq若含未知位则原样保留，原因1仍明确；它不能作为合法身份反馈。

完整`cmd_*`持续至下游接纳，随后等待匹配slot/frame/generation/mode/seq的实际feedback。
接纳命令不能提前更新active。成功后保持commit事件并更新完整active字段；新帧使旧槽
RETIRING，MODE保留ACTIVE槽且不产生release。提交事件被取走前停止新提交。

`retire_*`是下游“所有旧DMA、预取、bank和末端像素都已退出”的证明，必须精确匹配
RETIRING槽。它可以与切换到下一帧的匹配feedback同拍到达。随后进入WAIT_ACK，
保持release身份到上层ready，才将该槽标记FREE。该ready必须由真正的全局引用所有者
驱动，不能固定当作采集重用许可。已有release被背压时下一退休证明必须等待。

无在途已接纳命令的feedback报E1，错身份feedback报E2，提前/错身份/重复退休报E3。
首次协议错误sticky，停止新submit，保留已公开命令并继续排空合法反馈/退休/事件。
同拍错误优先级feedback高于retire。所有valid生产者在背压时保持payload；准备好才
采样，blocked输入不解释。复位必须与DDR/消费者协调，不能局部清状态假装取消引用。

`slot_free[2:0]`仅汇总显示引用，不是全局allocator。新命令和反馈/退休不在同拍接纳；
事件ACK后允许一个周期空隙。submits/commits/releases/rejected是32bit模计数，不用
序号大小推断完成，模式更新的重复seq或32bit回绕仍需真实feedback。

## 仿真与综合

```powershell
python scripts/video/run.py --suite display_slots
python scripts/video/run.py --suite mode_control
python -m unittest discover -s tb/video -p 'test_*.py'
python scripts/video/build_pds.py --target video_display_slot_owner --stage synth
```

13场景通过：11个定向/压力场景及7/513bit两种context的96轮三槽轮换。
覆盖接纳与commit分离、三模式不释放、三槽同时持有、延后退休与ACK、commit/退休同拍、
全部事件背压、错误/重复反馈、未知元数据、布局和身份拒绝、协调复位及序号回绕。
生产者接纳后立即复用/翻转输入，测试逐字段比对冻结命令；宽context高位也有非零数据。
记分板只观察公共接口，按实际release ACK删除引用，不读取DUT状态。

空行为接口在最初“接纳必须保留槽”断言实际RED。五个变异（commit提前释放、
MODE释放、MODE错误进入RETIRING、retire未ACK就FREE、忽略seq）均非零失败并命中指定断言。
Python102项，101通过、1项Windows符号链接权限跳过；既有mode_control24场景通过。
新增组件的route/bitstream被入口拒绝，且不覆盖既有综合成功指针。

PDS实际综合目录`build/video/pds/20261020T025114_888053Z`：478LUT、963FF、0DRM/APM。
8ns下slow reg→reg估计setup +2.369ns、hold +0.671ns。未给组件I/O添加板级延迟或
管脚约束，不以此证明外部路径或SoC整体时序；没有布线/下载。常量探测环警告的
实际网表核查与独立审查结论由[机器证据](evidence/display_slots.json)记录。

早期invalid-width测试复用了通用TB，其零次重复表达式在展开时先失败，不能计为DUT
参数防护成功；失败目录已保留。改用最小独立harness后，DUT自身的非法宽度fatal被观察到。

## 集成边界

独立审查通过：42组独立运行、304916项公开断言、9个有效错误变异及最终13场景复跑均通过，无未关闭发现。综合网表3389节点/3630边全部拓扑移除，0组合环/多驱动/锁存器；四条constant-probe警告保留，工具内部探测原因未据此推断。一个未实际改变状态的早期MODE变异实验保留原PASS日志，但不计入9个有效变异。来源/产物与旧板测证据经父审计逐项哈希核对；本批计划以精确本地提交收尾。
正式显示ABI/MMIO与驱动、全局采集/NPU引用、采集多帧rearm、实际像素/素材退休生产者、
共享fabric的写后读可见性与显示服务截止时间均待后续集成。该组件未接入板上F3c镜像，
不产生新的板级验收，也不证明连续视频或真实NPU功能。
