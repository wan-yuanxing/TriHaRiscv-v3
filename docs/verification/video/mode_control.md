# F3a 去抖与模式控制组件验证

基线`31e1936`，依据已批准[全屏设计](../../superpowers/specs/2026-10-19-fullscreen-display-design.md)。
本批提供两个独立core组件：按键同步/去抖，以及请求模式、能力/同帧资格、合并、
命令保持和实际提交反馈。F2静态全屏RTL、旧双窗及公共配置保持原字节。

## 行为与边界

去抖默认125MHz、20ms、低有效，按下/释放均为连续2500000个同步样本；门槛使用
64bit常量向上取整，1001Hz/20ms为21周期。20ms从两级同步之后计数；长按不重复，
短释放不重武装。未知样本不触发事件或改变稳定状态。复位视为释放，复位后持续
按住可在资格满后触发一次。

模式控制接纳0=RAW、1=BOX、2=AVATAR，3走保持的拒绝通道。合格请求独立于实际
活动状态；命令背压及等待提交期间，其完整上下文不变。后续请求只更新最后期望
并合并尚未发出的中间值。反馈匹配mode/seq/frame/slot/generation后才发布active；
错反馈保留等待项并报告sticky错误。结果必须同frame；无脸AVATAR可为空叠加。

上下文宽度参数不是显示ABI。调用方负责地址/框/素材校验和generation不可变；
下游负责像素域CDC、完整记录安全帧边界提交及全部引用退休后释放原槽。本组件
不直接修改像素、不读取DDR、不提供slot释放接口，也未接入当前板卡MODE键。

## 验证入口

```powershell
python scripts/video/run.py --suite mode_control
python scripts/video/run.py --suite all
python -m unittest discover -s tb/video -p test_*.py
python scripts/video/build_pds.py --target video_button_debounce --stage synth
python scripts/video/build_pds.py --target video_mode_control --stage synth
```

当前24个仿真场景已通过：去抖5个参数/极性组合，含真实250万周期门槛；控制17个
场景及7/513bit上下文两项。覆盖能力缺失、错帧/资源等待、无脸、长请求合并、命令
背压、上下文变化、非法模式、错反馈、在途/未接纳reset、32bit序号回绕等。
RED替身分别因省略稳定区间、未实际提交就发布活动记录失败，日志保存在
`build/video/mode_control_red/`，替身不进入正式filelist。

独立审查复现了完整32bit回绕后请求序号与旧提交/旧在途命令数值相同的情况：
仅比较序号会误把未提交请求视为已完成，并遗漏合并计数。现在用独立dirty和
命令覆盖标记追踪完成性，新请求与旧反馈同拍也不会被清除。新增case14/15/16；
前两项在冻结旧RTL上明确失败，当前通过，原RED与修复证据分别保留在
`build/video/mode_control_alias_red/`和`build/video/mode_control_review/`。

两个组件已综合：去抖30LUT/26寄存器、模式317LUT/658寄存器，均0DRM/0APM。
8ns约束下估计slow setup分别+5.131/+4.080ns；仅异步按钮至首级设置false-path，
本地第二级和去抖状态仍受时钟约束。没有布局布线或外部I/O签核。组件目标明确
拒绝route/bitstream，不能作为板级下载文件。

当前固定输入的完整回归通过37套件/198输入/337份仿真PASS日志，包含本次24个组件场景；
Python85通过、1项Windows符号链接权限跳过。独立审查的77项修复复核和针对性突变
均通过，原发现及关闭证据完整保留，无剩余实质发现。父核对11项审查来源、529项
审查产物及40项保留文件；新组件的PDS输入和源快照均与当前字节一致。
汇总见[evidence/mode_control.json](evidence/mode_control.json)。
此前被审查问题中断的完整回归保留为aborted，不作为成功证据。本次结果来自
`build/video/regression/20261019T134922_419299Z/result.json`。
下一批F3b实现框/可选五点及单头像最近邻/Alpha像素，F3c再核对实际MODE管脚、
接入CDC及独立板级三模式。正式显示MMIO/共享DDR属于F4。
