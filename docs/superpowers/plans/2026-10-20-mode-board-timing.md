# F3c CRC 读回停止条件的等价时序优化

目标：保持 core8ns、像素25ns及跨域束6ns，消除仅在 RECEIVE 有效的 RLAST 校验到 BYTES 阶段地址使能的长路径。

首轮 normal 六种子4..9均失败，最佳8为 setup -0.060ns/2端点，hold通过；同一seed8的performance复测仍为-0.060ns。路径为bridge beats→RLAST比较→reader stopping→address_q CE，76.6%为布线延迟。两个失败构建均未打包或下载。

原 `video_frame_crc_reader` 的 `fault_now` 只在 RECEIVE 判断RID/RRESP/RLAST，但其合并的 `stopping` 又用于BYTES，形成跨阶段的冗余组合路径。BYTES的停止原因只可能是历史result_code、online丢失、abort或timeout。新增单独的byte停止条件，仅供BYTES使用；原fault_now、首因、接收错误、scratch、结果保持、公开AR/R排空与所有时序不变，不增加流水周期。

这是对“全部F2来源原字节冻结”的有记录例外：仅优化自有公共CRC reader，不复制另一份长期引擎。F2顶层、板级约束、DDR IP及其他既有RTL仍冻结；历史F2位流保留，其旧来源哈希不冒称当前。公共组件的旧/新版本逐拍比较与四态阶段性质作为准入条件。

- [x] 保存优化前原字节/hash；用冻结原版与当前版双实例跑原CRC测试，比较全部公共输出。
- [x] 穷尽BYTES中online/abort/timer/result_code及R字段四态组合，比较新byte停止条件与原停止条件；检查响应字段不污染BYTES。
- [x] 重跑CRC、raw board（含27引擎场景）、mode board及Python；独立审查条件等价、所有权/错误排空和范围。
- [ ] 新目标以原约束重新综合/布线；检查新/旧CDC实际端点及所有setup/hold/recovery/removal，再生成合格下载包。
- [ ] 只有合格包才易失Program/Verify，继续原F3c实体KEY1/KEY0验收；如未通过，保留失败证据继续定位。

CRC修订后seed8/count1/normal：17410 LUT、18736 FF、73.5 DRM、16 APM；setup -0.247ns/14端点，hold slow/fast +0.137/+0.099ns。最差路径为输入DMA written_bytes经result_bad/transport_fault至缩放器使能，共13级，72.3%为布线。该构建仍失败，未打包或下载；保持修订后RTL及全部约束不变，比较normal种子4..7。独立CRC复审另通过14动态场景/3287沿全输出和524288四态组合，并检出漏abort替身。

## 接收私有暂存的后续等价优化

修订后normal种子4/5/6/7的setup分别为-0.190/-0.668/-0.140/-0.515ns，全部hold通过；未打包或下载。seed4暴露CRC burst_beats至128bit data_q CE的校验扇出，其他布局的最差路径分散在采集与显示逻辑。

第二步只改同一公共CRC reader：RECEIVE且rvalid时无条件写data_q及next_address_q/next_row_base_q。原停止判断、状态、首因、AR/R排空和对外结果周期不动。已知停止分支额外装入的值只在失败排空中私有保存；任何重入BYTES前必由新的正常RECEIVE边沿覆盖，因此不属于内部寄存器逐比特等价，但公共输出周期等价。

- [x] 临时副本先跑原15+56场景双实例公共输出逐拍比较；独立14动态/3287沿及6144四态/24576沿通过，含1080个未知停止及1401次额外私有装入；正式源在测试与审查时保持f3c9原字节。
- [x] 将精确审查过的324e2c候选采用到正式源，重跑CRC/raw/mode板级受影响回归；对历史证据按两段等价链绑定，不把旧哈希说成新源码。
- [ ] 按原8/25/6ns约束重新综合/布线，全部内部时序和端点审计通过后才打包、易失下载及现场验收。

## 写DMA的饱和burst算术

CRC两步后seed6仍为setup -0.205ns/4端点，hold通过，未打包/下载。最差路径为video_write_dma row_remaining[3]经33位加15、右移与两次min到burst_beats，共12级、74.1%布线。饱和到16beats只需判断bytes_left高24位是否非零；不饱和时仅低8位作ceil/16。保留未知输入全X行为和原page_beats计算，其他RTL状态/事务周期不变。该步骤对原冻结范围新增公共writer及其原测试的有记录例外，其他既有RTL/F2顶层/约束/IP仍冻结。

- [x] 修改RTL前在原tb_write_dma中新增独立64位除法oracle，旧源通过2499200组长度/4KiB byte offset/阈值/随机/XZ组合；加15改加14错误替身编译后被检出。旧版实际布线失败作为本次时序RED。
- [x] 候选全部公共输出按原19场景逐拍比较，独立审查全32位数学和四态等价；通过后精确采用并重跑受影响套件。
- [ ] 原8/25/6ns约束重新实际布线及端点检查；如第三次逻辑优化仍未闭合，应讨论整体流水/布局方案，不能无休止随机更换种子。

第三次逻辑优化已实际实现，seed6 setup仍-0.225ns/18端点，hold +0.124/+0.089ns；17365 LUT/18737 FF/73.5 DRM/16 APM，结构审计通过。最差路径回到preview DMA结果校验→缩放器使能。6次构建共14个布局均未闭合，不打包/下载；后续转向[core控制流水计划](2026-10-20-mode-capture-pipeline.md)，原现场验收仍未完成。
