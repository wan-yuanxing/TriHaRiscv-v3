# 检测5×5缩小实施计划

**Goal:** 交付与v0.6逐像素一致的独立5×5缩小RTL、整数参考、回归和组件综合证据。

**Architecture:** 同core域ready/valid流，5像素水平累加及5行块累计RAM，单输出寄存器；量化/补边/三分支发布不纳入本批。

**Execution:** 在既有video/windows-bringup分支顺序执行；用户已确认继续独立Video组件，保持主工程目录和明确文件提交。使用测试驱动、完成前验证及独立代码审查。

## 1. 先建立独立oracle和失败测试

- [ ] 新建`tb/video/tb_detect_downscale.sv`。参考像素函数定义黑/白、逐坐标梯度、棋盘、四角脉冲和按25个像素分摊指定总和。输出oracle对25个源坐标直接累加后`(sum+12)/25`，用输出索引导出块坐标。
- [ ] 对5×5穷举sum0..6375，对15×10/25×15与800×600逐输出自检；ready/valid停顿、四态、错误row_last、中途clear/reset和额外像素分别断言。输出受阻期间保存并比较payload。
- [ ] 使用Icarus编译缺失的`detect_downscale`实例，保存预期Unknown module失败到`build/video/detect_scale_red/`。

## 2. 实现RTL和整数参考

- [ ] 新建`rtl/video/detect_downscale.sv`。水平和11bit、RAM/读寄存器39bit、每通道总和13bit；相位4写累计或输出，最后行最后块关闭输入。输入未知或行标错误置fault，clear/reset清状态但不清RAM。
- [ ] 新建`scripts/video/detect_reference.py`，提供`downscale_rgb(data,width,height)`；校验尺寸和字节数，以嵌套5×5坐标定义RGB输出。新建`tb/video/test_detect_reference.py`，用常量、独立边界构造及非法尺寸/长度检查数学参考。
- [ ] 新增`scripts/video/run.py --suite detect_scale`，绑定所有实际RTL/TB/oracle输入哈希，纳入all；分别运行最小/多行/完整尺寸、穷举及异常测试，失败非零。
- [ ] 在独立build目录把舍入12改11、交换R/B、漏最后行，要求相同数学TB拒绝；不修改生产RTL作突变。

## 3. 组件综合与复核

- [ ] 新建`fpga/pg2l100h/project/video_detect_scale.json`，只列detect_downscale及其测试；新建8ns core时钟FDC。扩展build_pds的显式target枚举，继续禁止无管脚组件route/bitstream。
- [ ] 运行`python scripts/video/build_pds.py --target video_detect_scale --stage synth`，记录资源及RAM映射，明确无物理时序/板测结论。
- [ ] 运行完整Video回归并绑定新输入；代码审查关注5行累计、读写时序、全范围舍入、RAM重新初始化、fault和VALID保持，不接触JTAG/UART。
- [ ] 更新Video台账、接口/文件树、独立验证文档和小型证据。说明量化缺失依赖，保持板卡当前预览配置；仅提交明确Video文件。
