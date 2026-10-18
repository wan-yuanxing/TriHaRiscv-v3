# RX启动内容变化补充诊断

独立RX镜像在四角图输入下收到准确CRC33bac95a、462440个非黑像素及完整边界；KEY0后采样的26帧（序号220..6252）仍与参考一致，但未覆盖每个启动帧。

同一preview包重新Program/Verify后raw/preview CRC为33bac95a/679ff89c，用户确认四角和边框完整；一次KEY0后两CRC改变，用户确认再次变窄条或缺角。故障不仅是显示读口，可涉及启动内容或采集入口。

补充只读历史：在接收端同一个完整好帧发布沿记录第128、第129帧CRC、最近一次CRC变化序号及变化前CRC。历史随好帧原子更新，随全局复位清零，不改变任何准入、等待或超时。128/129项仅在sequence足够时有效；CRC变化是静态定位图下的观测，不是通用内容就绪判据。

UART新增type10：4字节头(type,flags,version1,reserved0)和7个uint32为sequence,crc128,crc129,last_change_sequence,crc_before_change,current_crc,0；与type8/9共用冻结快照，周期变为1/3/8/9/10。snapshot宽度856，复用原150ns束约束，无新CDC。原type1/3/8/9格式不变。

先补128/129帧及变化后保持断言，旧行为须失败，再实现并重跑组件/完整RX板级/解码及独立审查。重新构建和来源核对后Program/Verify，保持四角输入，记录一次实体KEY0。原preview图像验收保持失败。
