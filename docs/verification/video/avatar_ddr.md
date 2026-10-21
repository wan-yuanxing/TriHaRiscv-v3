# F4c4b DDR素材装载与封存版本

2026-10-21，基线`770dfde`，Windows原生。新增`avatar_ddr_cache`，以AXI128读客户端
向原`avatar_texture_cache`供数，旧生产RTL、ABI及C库不改。机器绑定见
[avatar_ddr.json](evidence/avatar_ddr.json)。无本批COM/JTAG、下载、Flash或板测。

## 接口与完成边界

core端`load_valid/ready`锁存base/bytes/asset_id/generation/expected_crc。默认
256×256 RGBA8888/262144B，16B对齐，完整范围限于0x82600000..0x827fffff；
TEXELS仅为测试提供4..65536且4的倍数。CRC是本地装载描述符，不改变640B显示ABI。
调用者须提供正确CRC，并保持源DDR在整次读取期间不可变、已完成写后读可见性。

固定AXI ID9、16B拍、INCR、最多16拍和一笔在途，按4KiB及末尾拆分。单拍128bit
暂存后逐字节计算CRC32/ISO-HDLC，按内存递增R/G/B/A转换为cache高至低RGBA。
最后texel须先比较CRC才允许写入，失败时cache未装满，不公布素材ready。
`checked_bytes`计参与CRC的字节，不是总线排空字节或成功cache写入字节。

最后texel真实写入是完成证明；下一拍FINISH只发布历史结果。result邮箱保持
success/code/id/generation/checked_bytes/crc至消费，接纳请求不表示素材完成。
封存版本整次协调复位epoch保持，结果ACK不允许替换，固定拍pixel provider沿用
原同步响应。封存后的online丢失不撤销成功素材；后来的意外R保留历史结果/素材，
另报sticky端口fault及undrained。调用方仍须按平台故障策略协调恢复。

| code | 含义 |
|---|---|
| 1 | 描述符未知、越界、未对齐或长度不匹配，无AR |
| 2 | R响应ID/RESP/LAST/数据非法 |
| 3 | 完成证明前online丢失 |
| 4 | 等待超时 |
| 5 | CRC不一致，最后texel未写入 |
| 6 | 无在途读且无当拍AR握手的意外R |
| 7 | cache内部错误或非法状态 |

fault禁止新装载。已公开AR保持VALID/地址/长度直至接纳，按公布ARLEN接收剩余R，
不因早到LAST提前结束、不再发新burst。RID/LAST/未知数据或意外R使排空可信性
丢失，`port_drained`保持0直到协调reset；已有故障也不能屏蔽后来的意外R。
RESP错误可在全部预期拍排空后报告drained。超时没有伪造响应或取消在途AR/R，
无法排空时须保持故障并由平台协调复位；result和port_drained不能代替全局FREE。

## 可复验入口与结果

```powershell
python scripts/video/run.py --suite avatar_ddr
python scripts/video/run.py --suite mode_resources
python -m unittest discover -s tb/video -p test_*.py
python scripts/video/build_pds.py --target video_avatar_ddr --stage synth
```

显式JSON只列原cache、新wrapper和一个TB。Python独立生成递增地址RGBA字节、
小端AXI word、大端RGBA期望和zlib CRC；RTL测试不复用DUT的CRC算法作oracle。
带停顿AXI源核对每个地址、ID、size/burst/len、4KiB边界、单在途及payload保持。
接纳后毒化描述符，结果背压20拍，封存后尝试覆盖并再次读回末词。

24场景全部通过，包括完整65536 texels、68词尾burst、不同钟比、素材区上边界、
4词最小探针；非法描述符/CRC/RESP/RID/早晚LAST/未知数据；AR待接纳时掉线、
等待R超时后排空、在途reset重装、新代际、接收中掉线；提前R、封存后掉线/意外R、
已有失败后的意外R。完整场景读取262144B、16384拍/1025个burst，逐一核对全部
65536词，另验证错误身份和末词保持，共65538次provider响应检查。小探针不冒充
正式尺寸。复位重装测试重新建立两个域和总线源状态，不声称可单独复位端点。

原mode_resources的16份仿真日志通过；Python109项通过、1项Windows符号链接权限
跳过。未重跑all，也未改旧record_pixels或RAW系统行为。

## RED、修复与独立审查

实现前缺失模块编译RED保留，不当作已有行为故障。审查及父任务另保存三项行为
RED/GREEN：ADDRESS期间误豁免提前R；FINISH错误包含在online/timeout装载期；已有
fault遮蔽后续stray导致虚假drained。分别改为依据实际在途/当拍AR握手、以最后
写入为完成边界、独立锁存排空不可信。历史成功与后来独立端口fault允许并存，
不能用同拍fault追溯撤销已完成素材；最后写入之前的故障仍阻止seal。

9项隔离变异全部检出：跳过CRC、字节序错误、跨4KiB、忽略RESP、接纳封存覆盖、
掉线撤回AR、忽略提前R、封存后误报online故障、已有fault屏蔽后来stray。变异只在
build运行。原变异runner曾预期较晚的断言名，实际更早的结果断言先检出，修正
标签后完整9项复跑；该失败不是生产行为回归。最终独立审查绑定当前源码/工具/
产物，详细探针、修复及未关闭项由机器摘要引用。

## 综合与集成边界

PDS2022.2-SP6.4组件综合509 LUT、628 FF、64 DRM、0 APM、0锁存器。core8ns
寄存器setup估计+2.614ns，pixel25ns+21.793ns，稳定身份束6ns+5.224ns，最小
hold+0.619ns。4项约束全部适用，0 error/critical，48项I/O预算未指定警告。
719个组件端口位超过300物理I/O，目标用于内部组件综合；端口尚无真实外部预算，
ASYNC_REG被工具忽略。上述余量不是布线、物理CDC或板级时序签核，也不解决前一批
record_pixels的core边界违例。

457个保护文件、57项其他路线路径保持，旧入口除新hook外原始字节一致；仅本批
15文件本地提交，STATUS的其他路线追加保持未暂存。单份cache保持版本到协调
reset，未实现运行中多版本替换/一般引用分配器。需要仲裁后才能与实际RAW共享
唯一DDR读口，不能把本客户端接成第二物理DDR通路。下一步接共享读仲裁和完整
记录叠加链，再联合RAW扫描器/owner退休。实际素材清单/上传、物理可见性、CPU/NPU、
连续视频、系统资源、布局布线和板测继续分别验收。
