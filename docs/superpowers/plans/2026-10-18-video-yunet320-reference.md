# YuNet 320 输入整数参考实施计划

> **For agentic workers:** Use superpowers:executing-plans inline. 本批只实现已选320路线的数值参考，后续RTL与DMA按设计文档分批验收。

**Goal:** 从800×600 RGB888生成与既有OpenCV4.11处理一致的307200B UINT8 BGR NCHW输入。

**Architecture:** 纯Python标准库按固定四分之一插值权重/分步取整计算有效320×240，输出时写入上下各40行零的三平面。OpenCV只用于隔离构造golden，不成为正常Video脚本依赖。

**Tech Stack:** Windows、Python、unittest、SHA256；来源外部NPU 4fc0fc8和官方opencv-python4.11.0.86 wheel。

## 文件与步骤

- [ ] 新建`tb/video/test_yunet_input_reference.py`，测试API `preprocess_rgb800x600(rgb: bytes) -> bytes`。输入不足/过长、bytearray/None等拒绝；六个固定源模式与已冻结NCHW SHA256比较。单独检查B/G/R、0..255、首末有效行、上下40行及平面长度。
- [ ] 在实现缺失时执行`python tb/video/test_yunet_input_reference.py`，保存缺模块RED及非零退出码；语法错误不算功能RED。
- [ ] 新建`scripts/video/yunet_input_reference.py`，限定输入为1440000B的bytes，每输出单通道使用设计中的H0/H1分步公式，通道索引RGB的2/1/0分别写B/G/R平面；返回307200B，其他像素初始化为0。
- [ ] 执行同一unittest获得PASS。源图模式独立按`(37*x+19*y+83*c+((x*y)>>3)+seed*(7*(x%7)+13*(y%11)+29*c))%256`构造，seed取0/1/7；另有零、全255、固定RGB(211,93,17)。它们的预期哈希来自4.11 probe，不调用待测函数生成。
- [ ] 用错误单次舍入、RGB/BGR未交换、平面交错和上下补边偏移四个隔离突变运行测试，均须失败；保存来源和被测源码哈希。
- [ ] 执行`python -m unittest discover -s tb/video -p test_*.py`及`python scripts/video/gen_config.py --check`。本批不改现有回归入口或RTL，核对现有实现哈希；新测试被Python discovery自动发现。
- [ ] 更新`docs/video/README.md`、`docs/video/STATUS.md`及新验证记录/小型证据，精确提交本批文件。单列OpenCV数值验证、RTL/综合/板测状态；下一批进入固定比例RTL。

## 源码计算约定

```python
sx = (10*x+3)//4
sy = (10*y+3)//4
wx = 3 if x%2 == 0 else 1
wy = 3 if y%2 == 0 else 1
h0 = (4-wx)*p00 + wx*p01
h1 = (4-wx)*p10 + wx*p11
q = ((4-wy)*h0//4 + wy*h1//4 + 2)//4
destination = channel*102400 + (y+40)*320 + x
```

输入类型/长度先校验；输出循环有效y=0..239、x=0..319、channel=0..2。像素p的源字节地址为`(sy*800+sx)*3+(2-channel)`，相邻列+3，相邻行+2400。首源坐标为0/1，末源坐标为798/799、598/599，无越界或重复边界填充。
