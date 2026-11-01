# CPU 分支交付

GitHub分支为`cpu`，保留总工程目录结构。本地发布分支为`cpu-github`，因为已有
`cpu/...`分支时Git不能创建同名本地`cpu`引用。既有CPU开发分支、主工程集成分支、
NPU和Video工作树保持不变，本次没有合并到main。

## 当前版本

- Verilog、RV32IM/Zicsr、六级顺序双发射，可在综合前用`DUAL_ISSUE=0`选择单发射。
- 本次板级目标固定`DUAL_ISSUE=1`、100MHz、32KiB片上SRAM，无Cache/DDR。
- 实际板级Slow/Fast setup +0.220/+3.768ns，hold +0.162/+0.104ns，
  最小脉宽 +3.655/+4.202ns，复位检查全部通过，原IO/hold约束保持。
- GCC15.2/-O2，真实5000次CoreMark与KEY0重跑两次相同：409.278990 CoreMark、
  4.092789 CoreMark/MHz、0.042293 CoreMark/LUTs；CPU-only9677 LUT、4968 FF、
  4 APM，752 RAM-LUT已含于LUT。无官方提交声明。

本次将已验收的冻结源逐字节放回`rtl/cpu`、`rtl/soc`、板级和软件原有目录。
22个CPU文件与v83清单一致，46项实际板级PNR输入与通过运行一致；没有重新设计RTL。
来源/许可文件保留原样。保留指定文件的原换行字节，避免Git转换使验收哈希失效。
发布前从标准目录重新运行真实PLL模型及完整板级短预检，均通过；1229829周期、
473739次配对、计时窗口WB/store轨迹均与原通过包一致。重新编译的ROM/SRAM镜像、
5000次固件所有加载段及入口完全相同，ELF容器的非加载内容不同，不冒充文件字节相同。

源码身份核对：

```powershell
python scripts/cpu/check_cpu_release.py
```

对应清单为`docs/verification/cpu/cpu_branch_source_manifest_20261101.json`；
实际板测/时序、GPIO及失败排查见
[上板记录](DUAL_ISSUE_BOARD_COREMARK_2026-11-01.md)和
[机器验收摘要](../verification/cpu/dualissue_board_coremark_deployment_20261101.json)。
最初95MHz/HIGH PLL实物不锁，已撤销其运行准入；95MHz创建器使用实测能锁定的
OPTIMIZED模式，当前交付与板上保留版本为100MHz/HIGH。

## Windows 构建入口

沿用已安装的ModelSim、PDS和RISC-V GCC，不引入新的HDL生成器或WSL。
工具路径见`config/cpu_toolchain.json`及现有工具发现逻辑。厂商PDS安装、原语模型
和板卡参考资料需在构建机器本地可用；生成厂商IP、日志、波形、位流和固件二进制
仍放在被忽略的`build/`，不纳入源码仓库。

以下命令中的`<...目录>`使用上一步实际打印的运行目录：

```powershell
# 真实PLL模型验证
python scripts/soc/run_board.py --test clocks

# 首次构建：生成实际固件并运行短预检，用于建立本机CPU面积测量输入
python scripts/soc/run_dual_board.py --test coremark
python scripts/soc/measure_cpu_area.py --firmware-directory <首次CoreMark目录> --clock-directory <clocks目录>

# 绑定本次实际CPU-only LUT数，再构建最终5000次固件并验证短测
python scripts/soc/run_dual_board.py --test coremark --cpu-area-directory <cpu-area目录>

# 当前通过版原生物理配方：注册LED、乘法器X1/Y2区域、4轮时序修复
pwsh -NoProfile -File scripts/soc/run_dual_board100_repair4_route.ps1 -FirmwareRunDirectory <带面积CoreMark目录> -ClockRunDirectory <clocks目录> -FirmwareTest coremark -PlacementSeed 1
python scripts/soc/review_board.py <board-route目录>
python scripts/soc/package_dual_board.py <board-route目录>
```

首次无面积分母的预检不用于最终CoreMark/LUTs或物理发布；最终运行器要求软件分母
与实际本轮CPU层次综合一致，否则拒绝生成位流。发布和Program/Verify继续分别验收。
现有单发射和早期冻结包工具作为历史测试入口保留；本分支双发射板级入口使用以上
`run_dual_board*`命令。单发射切换需重新仿真、综合、时序和测分，不沿用双发射成绩。

硬件经用户授权后，可用`python scripts/soc/program_board.py <程序包目录>`执行易失
下载/回读校验；串口为COM12、115200、8N1、无流控，短按KEY0重新跑分。
