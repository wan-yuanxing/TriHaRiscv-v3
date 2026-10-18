# 预览KEY0与HDMI链路复位分离

用户已授权持续修复Video、Windows构建和易失Program/Verify。本设计在现有KEY0重采验收范围内实施；不写Flash，不推送，不改独立技术报告。

## 证据与目标

历史版RX诊断一次KEY0后约75秒没有像素时钟；同镜像重新Program/Verify恢复。下一次单次KEY0在输入时序已合格时先收到全黑帧，完整好帧128/129的CRC为5243da6a/aebe097e，直到188才恢复参考33bac95a。证明128个好时序帧并不保证外部画面已恢复。独立RX目标未包含preview，故不把此观测等同于同一preview帧的精确时间证明。

当前KEY0同时复位采集/DDR和HDMI转换器，导致重新写EDID及链路初始化；官方固定来源的HDMI reset仅跟随PLL上电启动（其KEY0信号实际未被使用）。目标是让KEY0重新校准DDR、清空旧任务及安全重采，同时保持已启动HDMI转换器及其I2C控制器运行。上电或实际HDMI PLL失锁仍重新初始化链路。初次连接、断源、拔插不承诺无缝恢复。

## 选择

采用预览专用时钟复位模块，限制KEY0作用范围。增加固定等待无法覆盖无时钟失败，且不能保证任意源端恢复时间；基于RGB/CRC筛选会错误拒绝合法黑帧；要求每次外部拔插不能满足按键重采目标。

新增`video_preview_clock_reset`，保留原`clocks.pll`层级、40/10MHz、pixel/cfg两级同步释放、tx启动1ms计数。pixel_reset_n/cfg_reset_n仍由KEY0与locked共同异步置低、各域同步释放。独立link_release由locked异步置低、cfg域同步释放；tx_reset_n和1ms计数只由locked/link_release决定，KEY0不能清它们。HDMI TX/RX初始化继续使用rstn_out及原TX完成先于RX的共享I2C顺序。

只替换preview目标中的时钟复位模块；原`video_clock_reset`及独立RX诊断的来源绑定保持不变。DDR、入口FIFO、显示bank、core复位及任务所有权继续由原协调KEY0路径处理。128帧门控、125MHz、6ns束约束和5秒超时不变。纯黑帧仍合法，画面内容不参与准入。

冷启动依赖生成GPLL在配置完成后先给出未锁定状态，与原工程用locked启动一致；数字模型必须覆盖初始locked=0、失锁再锁定以及KEY0按住跨越首次锁定。link_release两级本地路径保持时序检查，不增加全域false path；物理审计应检查实际复位及recovery/removal约束。

## 验证与交付

先让独立时钟复位测试在旧模块上因KEY0拉低已初始化HDMI reset而失败；再实现新模块，同一测试检查上电、KEY0短/长/重复按键、停时钟释放和PLL失锁重启。板级数字替身验证KEY0保持HDMI reset、协调清理DDR/入口/显示、重采CRC及原错误恢复。数字替身不代表真实转换器恢复。

所有相关回归及新的PDS八类内部时序/实际CDC约束检查通过后，独立复核当前输入及bit/mask。单独打包、易失Program/Verify；四角图首次完整、实体KEY0后完整，以及真实桌面重采分别记录。内部CRC通过不能代替用户画面确认。外部AC时序未签核；未通过实体画面验收前V020d保持open。
