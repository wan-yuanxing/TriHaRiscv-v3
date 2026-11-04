# B03 MODEL 阵列与实际缓存验证结果

版本：v0.1；日期：2026-10-28。对应[[89_B03_MODEL阵列与实际缓存组合规格]]。**16×16阵列、实际A/B/P/O RAM及Q8组合的功能仿真通过**。真实首层12个切片由FPGA仿真完成MAC、跨K部分和写回/重载、量化及O读回。输入展开仍为主机单元刺激，未执行RTL ROI/gather、程序FETCH、DDR或完整首层；第86篇S1整体出口仍保持开放。

## 1. 本轮实际实现

新增三个RTL模块：`b03_model_mul_pair`使用一个真实SIMD APM得到同M的两个Co乘积；`b03_model_array16`组合128个此类原语及256个I32累加器；`b03_model_tile`连接真实bank、分块控制和冻结Q8。没有改变冻结Q8、POST、桥、旧数值资产或预训练权重，不安排训练。

| 实际层级 | 原语/工作 |
|---|---|
| 阵列单独top | 128个SIMD GTP_APM_E2；E0接受、E1乘积、E2加宽检查及原子累加 |
| 缓存组合top | 128 SIMD + 32 scalar，共160个GTP_APM_E2 |
| A/B/P/O | 各4个1024×32真实bank，共32个GTP_DRM18K_E1，即16 DRM36等效 |
| 请求边界 | 冻结reqreg与TDP，2个包含接受沿的共同CE推进沿后出现实际返回；控制在随后沿消费 |
| 输出 | 最终P双口读8Co→Q8→四bank双口byte-enable写O→公共host口实际RAM读回 |

两个top是分开的ModelSim进程，不能把128+160算成本单元部署需要288APM。本组合不含POST/ROI/控制RAM/DDR桥；第86篇192APM/90DRM仍是更大范围的部分候选账。8192bit累加器也不是完整FF统计。没有新PDS、布局布线或100MHz STA结论。

共同`advance`同时推进RAM请求/返回、阵列、Q8和O。run_ce0不消费host/done或Q8接口，Q8/O反压冻结整条局部链。reset/clear及故障清空优先，故障ABORT在CE0只清在途与O valid，不新发布完成；恢复run_ce后才产生错误响应。普通DDR握手不在本模块内。

## 2. 真正跨K写回和重载

真实首层K27按16+11执行。每块结束后先排空乘积，再向P发64组四字写请求，共256个I32；等真正写执行及请求排空，清零所有256个累加器。非末块随后从实际P读回64组四字，重载累加器，保留下一k序号继续运算。

最后一块也执行P写入、排空和清累加器；Q8只从实际P返回读取，不能从acc FF旁路。公开P写/重载事件逐字对照各块数学值，zero事件沿后检查完整8192bit acc为0。正常计算中bench未写P或层次修改累加器。

阵列溢出专项独立使用其公开load接口放入接近I32极值，再通过真实APM贡献验证INT33溢出。K≤128、U8×S8从0累加本身不会逼近I32上限，不能把普通模型案例充当溢出覆盖。

O按32M组保留byte-valid：两次相邻16M任务可填同一组；清valid不清RAM，未选中字节保留先前实际装载的哨兵。检测到错误时整组valid作废，不承诺回滚已经写入的物理字节。后续任务须重新建立有效输出。

## 3. 正式运行结果

正式目录`build/platform/b03_model_tile_v1`，两个进程都退出0、无超时。报告原字节归档`yunet/baseline/b03_model_tile_validation_v1.json`，SHA256：

`2432c622ab3d06abf2207cd8c4b8c051a71583616feeab90621b46e21690676f`

| 检查 | 实际结果 |
|---|---|
| 原始console与transcript | 两个job的两种完整日志均0错误/0警告，各编译与退出summary也均0/0 |
| 真实进程墙钟 | array 3.212秒；tile 8.362秒 |
| 阵列 | 379个TB周期；223受理=219退休+4清空，pending0；最长128拍连续issue |
| 阵列案例 | 9正常、12错误，clear/reset各2个乘积在途位置；17次CE保持检查 |
| 组合数值 | 22组向量，其中12个真实tile，共3072个真实首层输出值 |
| 组合任务 | 63提交=49完成响应+14清除/复位取消，最终pending0 |
| 完成分类 | 31成功、14前门非法拒绝、4运行故障；错误响应也计入49完成，不能全部称成功 |
| 公共装载往返 | 2872受理/2872响应；2个非法host请求，含mask0同址写冲突；同址双读合法 |
| 真实P事件 | 13120组四字写=52480字；10432组四字重载=41728字；205次清累加器 |
| Q8 | 990组实际退休，包括故障/取消流程中的观察；不能当990张图像 |
| 实际O与守卫回读 | TB核3840个O数据字；另720个A/B/P/O守卫字，均一致 |
| 控制压力 | CE暂停2680周期、O反压86周期、host响应保持302次、done保持147次 |
| 复位/清除 | 各7个选择阶段入口，恢复任务正常；不等于穷尽各bank任意在途槽或每个时钟相位 |

四组真实输入为zero/full255/pattern/calibration_image_000，各取空间起点0、12800、25584的16M tile；使用真实checked参数及冻结tensor184对照。主机只准备A/B和参数，FPGA实际执行全部MAC/P/Q8/O；这一证据强于第88篇由host计算部分和后仅测试Q8，但仍不是FPGA完成图像取数或完整层。

通用向量包含K1/16/17/27/128/126、不同chunk（含K128/chunk1压力）、M/Co尾、奇Co、非4对齐x、正负半值与饱和。K17/128只代表tile核心，不代表profile1合法卷积。上/左padding的真实A值由host展开；下/右padding、1×1/3×3/stride地址生成尚无RTL gather证据。

运行故障实际注入：阵列leaf缺valid、最终P读返回缺valid、Q8活动bias溢出、Co5的Q8返回mask被破坏。故障锁存身份、阻断成功/O valid，之后新tag任务可重新运行。仅force控制有效/掩码端点；没有force乘积、部分和、量化值或RAM数据来制造成功。

## 4. 独立公开VCD回放

`replay_b03_model_tile_wave.py`从正式VCD的实际host装载和START重建输入、参数及RAM字节模型，独立用Python整数乘加和Fraction ties-to-even计算每块期望。它不读取bench expected总线或向量golden，核对真实P执行/返回、清零后的全部acc、Q8完整product/rounded及实际host O读回。

正式报告`build/platform/b03_model_tile_wave_replay_v1/b03_model_tile_public_replay_v1.json`原字节归档到baseline，SHA256：

`30156b72187938b46ef28071abe2e3387f49867fd62b594c207bc70e485d3bbe`

63任务/49响应/14取消、2872装载往返、P写13120组/重载10432组、205次zero及990组Q8均与原始仿真一致。独立回放核对4100个O读word，包含额外O哨兵读取，所以不等于TB单列的3840个O数据字；720个守卫字还包含A/B/P的读，不能直接相加。

31个成功任务合计6796个有效输出byte。全部运行中实际O写共7644byte，包括后来被取消任务已写出的部分字节；后者不计入成功输出。VCD共45544个上升沿，含比TB计数多出的初始化沿。

独立回放覆盖组合公开路径及4类运行故障隔离；阵列单独top的全部故障算术仍以其正式自检bench证据为准，未虚报为全部再次独立回放。

## 5. 实际仿真图

以下图片取自本次正式两个top的VCD及独立回放；PNG/manifest绑定实际报告、源码和原始输入。图1的阵列单元和组合单元时间轴分窗，不能拼成同一次运行。

![实际16×16阵列与真实tile路径](仿真截图/b03_model_tile_v1/01_actual_array_and_tile_path.png)

阵列连续接受k向量，E2退休并更新累加器；下半窗为真实校准图中间tile的分块控制与实际计数。

![实际P写回清零及重载](仿真截图/b03_model_tile_v1/02_actual_P_spill_zero_reload.png)

选取非零真实部分和，显示P写完成、清累加器及真实读回重载；下半窗核最后一组重载排空后再进入下一K块。

![实际Q8输出与O RAM回读](仿真截图/b03_model_tile_v1/03_actual_Q8_O_and_readback.png)

尾Co案例检查byte-enable与O valid；下半窗为实际公共host读RAM响应。完整字节和守卫比较以原始日志/独立回放为准，图只展示选择窗口。

![共同CE反压及故障隔离](仿真截图/b03_model_tile_v1/04_actual_CE_and_fault_isolation.png)

展示真实暂停、运行错误与失败隔离。阶段入口复位的有限覆盖和完整统计另见本篇表格，不能仅凭一张图外推所有物理故障场景。四张正式图已逐张实际打开确认可读，目视记录另存同目录visual_review_v1.json。

## 6. 开发记录、复现与下一步

独立静态审查提出两项补强并在正式运行前落实：Q8返回除了error/tag还核完整预期Co mask，防止尾通道少写/多写；ABORT内部清空不受CE，但CE0不提前发布done。其他正常缓存时序与地址路径经审查及正式运行核对。静态评审原文保留其当时“尚无组合仿真”状态，正式结果以本篇和所绑定报告为准。

dev01为实际阵列独立通过，dev02加入正常组合通过，dev03补运行控制/故障通过，正式v1再加入阵列控制等待及同沿错误优先级检查。旧目录、快照与日志均保留，开发PASS不替代正式选定版本。独立回放和绘图的开发目录也保留；开发回看旧运行时可绑定其精确编译快照，正式模式仍严格核对当前源与正式快照一致。

528项旧冻结源及正式owned、厂商模型、向量和源资产均在运行前后核SHA。关键RTL身份：

| 文件 | SHA256 |
|---|---|
| b03_model_mul_pair.v | `14739c0daa6888df9abfbb0364cc3fb7d258fedf75977e5f9c10236d9cb3da55` |
| b03_model_array16.v | `1de67789866c472b1bf9349247f97c087f8839dec89366e5131767a8479f0aeb` |
| b03_model_tile.v | `609aac10c14614f2aa2416a75b30ecb806a4d196d53feb7b64cd1f26f41b6cf7` |

在工程根目录复现，输出目录必须不存在：

```powershell
.\jiaoben\zgtc\run_b03_model_tile_checks.ps1 -OutputDir build/platform/b03_model_tile_recheck01
& 'D:\anaconda3\envs\npu-cifar\python.exe' -X utf8 yunet/python/replay_b03_model_tile_wave.py --build-dir build/platform/b03_model_tile_recheck01 --output-dir build/platform/b03_model_tile_replay_recheck01
.\jiaoben\zgtc\render_b03_model_tile_wave.ps1 -BuildDir build/platform/b03_model_tile_recheck01 -ReplayReport build/platform/b03_model_tile_replay_recheck01/b03_model_tile_public_replay_v1.json -OutputDir build/platform/b03_model_tile_figures_recheck01 -Development
```

下一项先收敛程序驱动与真实输入路径的接口：480B诊断程序/128B提交的FETCH与检查、参数准入、ROI→A的硬件gather、唯一受监督桥及O输出DMA。将本次局部单元接入真实地址和程序驱动，补尚缺的几何/故障在途覆盖，再做完整首层代理及有界HMIC验证。保持外部输入地址可重定位，不增加CPU像素复制，不把测试host预展开搬进正式运行。

本轮未做ROI/gather、DDR、PDS、完整首层/整网或上板。S1_complete、M01/G2、memory_scope/结果发布和30fps仍未放行，原P41 HMIC两条ERROR及总FAIL保持。没有新增B03下载位流。
