# F1 raw 全屏扫描组件实施计划

**Goal:** 实现800×600原分辨率RGB888扫描，首像素完整、DMA可排空、帧提交与旧槽释放正确。

**Architecture:** 新增独立`raw_display`，复用现有显示协议与AXI子集，保留旧双窗源文件。采用双时钟双bank行RAM，首行就绪后在输出帧起点提交；同帧模式更新属于F3，本组件F1只接完整新帧记录。

**Tech Stack:** Windows原生Python/Icarus/PDS，SystemVerilog，128bit AXI读取，8ns core/25ns pixel组件估计。

基线`53fd5ca`。使用当前`video/windows-bringup`工作区；CPU工作树及31项既有其他路线文件保持起始内容。内联实施，完成后作独立代码审查，不创建新的任务聊天。

## 文件职责

- Create `rtl/video/raw_display.sv`：`FRAME_WIDTH=800/FRAME_HEIGHT=600`，复用record/commit/release/AXI接口。
- Create `tb/video/tb_raw_display.sv`：地址派生字节内存、整扫描帧像素oracle、背压/故障/释放检查。
- Create `fpga/pg2l100h/project/video_raw_display.json` 与 `constraints/video_raw_display.fdc`：仅组件综合，显式源/测试/约束。
- Modify `scripts/video/run.py`：`raw_display`套件及all；绑定源、工具与仿真产物。
- Modify `scripts/video/build_pds.py`：仅synth目标，复用源/副本哈希检查。
- Modify `docs/video/README.md`、`STATUS.md`、`docs/interfaces/video.md`；Create `docs/verification/video/raw_display.md` 与 `evidence/raw_display.json`：实际结果与边界。

## Task 1：独立测试及RED

- [ ] 先从已验证字节BFM/光栅时序检查建立raw测试，输出几何改为单幅、有效区从`(0,0)`开始；整帧缓冲在扫描结束后按已发布frame_id比对，避免core提交事件同步延迟漏检首像素。
- [ ] 使用build内的旧preview适配夹具运行，编译须成功且因行为不满足新全屏检查而非零失败；保存RED命令、输入哈希和原始日志。
- [ ] 测试小几何及full：正常/首行延后/欠载，RID/RRESP/RLAST错误及未知，DDR失效、AR/R超时后排空、协调复位恢复、非法描述符、事件长背压和计数回绕。

像素oracle只由内存地址生成：

```systemverilog
address = base + row*stride + col*3;
expected = {memory_byte(address), memory_byte(address+1), memory_byte(address+2)};
```

运行RED：`python -X utf8 build/video/raw_display_red.py`。预期编译0、实际vvp非零、包含首行/像素或旧几何拒绝的明确失败；不能将缺模块/语法错误记为RED。

## Task 2：raw组件与GREEN

- [ ] 新模块将源坐标改为`pixel_x/pixel_y`，单幅范围`x<FRAME_WIDTH,y<FRAME_HEIGHT`，末列仅一次消费。
- [ ] 在P_PREFETCH满足安全起扫条件时，同拍让bank0首像素进入RAM流水；该拍也参与末列消费，使1×1边界可退休。
- [ ] 保持原DMA公开VALID、advertised长度排空、4KiB/16beat拆分、地址上界、事件保持、协调复位和RAM无异步reset。
- [ ] 参数只供测试几何缩小，限制1..800×1..600；默认生产几何800×600。非法/未知地址、stride、frame_id、slot及slot3在AXI前拒绝。
- [ ] 对未知RDATA与坏响应锁存故障并排空，输出确定背景；故障不计完成扫描。
- [ ] 运行定向TB全部场景，先修正失败，再做结构检查；不修改旧preview源码来迁就新实现。

起扫关键条件为首行身份/epoch匹配、首行已就绪、安全帧起点及前次事件已退休。该条件既用于状态转移，也用于当拍像素有效及末列消费，避免首像素少一拍。

## Task 3：入口与组件综合

- [ ] 显式manifest绑定`raw_display.sv`和TB；FDC定义core8ns/pixel25ns，仅切明确scalar首级跨域D，bundle路径按6ns约束；组件外部输入/输出及板级AC不作闭合结论。
- [ ] 将`--suite raw_display`纳入all，小/奇数宽/1×1/full几何和时钟比扫描；每个仿真要求非零失败传播及唯一PASS标记，工具/产物哈希运行后复核。
- [ ] `python scripts/video/run.py --suite raw_display`须PASS。
- [ ] `python scripts/video/build_pds.py --target video_raw_display --stage synth`记录资源、估计slack及全部源/副本/工具/日志；route/bitstream必须拒绝。

## Task 4：审查与交付

- [ ] 独立审查首像素、bank退休、公开AR/R排空、CDC束稳定、旧槽释放及测试拒绝能力；发现问题先复现再修正。
- [ ] 加入实际编译的首像素/地址或提前bank归还变异，证明像素/所有权检查会拒绝错误实现。
- [ ] 跑`python scripts/video/run.py --suite all`，绑定最终源码与仿真日志；已通过后不重复无关长回归。
- [ ] 更新接口/验证/台账，精确暂存本批文件、小范围本地提交并核对无关31项未变。

F1不含MODE/框/头像、显示MMIO、共享DDR可见性、连续采集或新板测。下一阶段F2复用三分支采帧目标接raw扫描，取得完整四角/桌面及KEY0实际图像证据。
