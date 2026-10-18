# 固定5:2双线性缩小RTL验证

基线e71b148，实施计划989462a，遵循用户选择的既有NPU320路线。本批组件默认800×600→320×240 RGB888有效图像；BGR、上下40行、NCHW写入和正式三分支仍分别实施。

## 数值与协议

`detect_bilinear`使用ready/valid单帧接口，每轴尺寸为5..2045内5的倍数，输出为2/5。输入行/列相位0/1和3/4两对参与插值，2号相位仍校验输入几何及未知值。同步行RAM保存每输出列三通道10bit水平和；默认320×30=9600bit逻辑容量，top行覆盖后才在bottom行读取，RAM及读寄存器不复位。

水平权重在偶输出列为1/3，奇列3/1；垂直偶行为1/3、奇行3/1。每通道执行`(floor(wtop*Htop/4)+floor(wbottom*Hbottom/4)+2)//4`，保持OpenCV4.11的分步取整。水平、垂直与输出流水用移位/加法，不使用乘法算子。

ready只在流水/输出槽有容量时成立。输入未知RGB或错误/未知row_last在被接纳时置sticky fault，包含未参与插值的行列；blocked未知payload不解释。末输入后关闭新帧，额外s_valid置fault。fault取消尚未公开的运算，已公开的VALID/数据保持至消费；clear/reset协调取消整帧，重采覆盖RAM后再读。组件没有DMA完成或INPUT_READY语义。

## 定向证据

- 正确RED：`build/video/bilinear_red/20261018T094909_773617Z`，当时模块缺失，Unknown module按预期返回非零。之前草稿RED仍留原目录，不作为当前测试哈希记录。
- 定向回归：`build/video/regression/20261018T095033_934803Z`，47个当前输入，十组仿真通过。合法尺寸5×5、15×10、25×15、800×600、2045×5、5×2045，每组六幅图；另有最小/15×10的异常和取消场景。
- 每个5×5相位覆盖RGB各通道X、Z、row_last X/错位；每组150次异常，加末项fault保持，共151次。另覆盖blocked未知值、部分行、两个流水阶段及受阻输出的clear/异步reset、新帧覆盖旧RAM和96拍级背压。
- 全尺寸六幅RTL有效RGB转储由`tb/video/check_bilinear_dump.py`在软件中转换BGR、补40行并构造NCHW，与先前冻结的六份OpenCV4.11 SHA256匹配，总计1843200张量字节。**补行/NCHW由检查脚本重建，不表示相应硬件已实现。**
- `build/video/bilinear_mutations/20261018T095129_055513Z`拒绝四种错误：单次舍入、水平相位交换、水平和提前截断、行RAM奇列地址丢失；均编译成功后由数值断言拒绝，未用编译错误/超时冒充。
- 组件目标的route/bitstream调用均在PDS启动前以exit2拒绝，`bilinear_component_guard/20261018T095616_388789Z`确认未创建PDS运行目录。

## 组件综合

`build/video/pds/20261018T095033_909863Z`通过，PDS2022.2-SP6.4：246 LUT、134普通寄存器、一个GTP_DRM18K_E1（0.5 DRM36K等价）、0 APM。8ns core时钟下综合估计setup+4.025ns、hold+0.706ns，289个setup端点；源和SNR哈希绑定。本组件没有板级管脚，综合估计不替代布线时序、外部AC或板测。

完整Video回归`regression/20261018T095231_804185Z`通过29套件/145当前输入，123份仿真PASS日志及63项Python（62通过/1个Windows跳过）已核对。最终独立审查无发现，23种合法几何/67帧、165项异常取消、14种非法几何及4项控制突变通过；父会话复核158项来源/夹具/日志哈希。小型证据见[detect_bilinear.json](evidence/detect_bilinear.json)。

```powershell
python scripts/video/run.py --suite detect_bilinear
python scripts/video/build_pds.py --target video_detect_bilinear --stage synth
python scripts/video/run.py --suite all
```

本轮不下载板卡、不改变既有HDMI/DDR位流，125MHz、6ns束和5秒超时维持原范围。下一批接入BGR/40行补边、NCHW行缓存/DMA及公共输入槽配置。
