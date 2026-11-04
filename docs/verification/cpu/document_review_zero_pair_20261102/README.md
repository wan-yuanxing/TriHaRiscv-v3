# P0-3：零比较分支配对失败定位

结论：原 `tb_issue_zero_pair_pending` 的失败来自强制输入夹具未适配当前队列/发射接口，以及配对期望仍沿用旧策略。本任务没有修改 RTL。原夹具原件、原断言和新复现的 FAIL 均保留；另建完整驱动的夹具和真实取指程序验证当前行为。上述结论限定于下述定向仿真范围。

依据为任务书 P0-3、写作边界，主工程及 CPU 工作树根目录 AGENTS，以及当前 RTL、测试和附录 B.4.6。仅写入 CPU 工作树的新测试/运行器和本证据目录，未修改 LaTeX、图稿或最终审核报告。任务标识沿用 20261102，实际交付运行发生在北京时间 2026-11-03。

## 原失败与因果证据

原件 `tb/cpu/tb_issue_zero_pair_pending.v` 的 SHA256 为 `evidence.json` 中各 legacy 运行的 `inputs` 记录，`source_manifest.json` 确认其与首次复现时一致。默认参数和 `RF_ZERO_META=1` 均在 307 ns 触发原断言：

```text
ZERO_PENDING_PAIR_FAIL op=00700463 a=00000000 b=0e8aedf9 expected=1 actual=0
```

A 为 `BEQ x0,x7,+8`，PC=`80000000`；B 为 `ADDI x10,x10,1`，PC=`80000004`。最后一个断言前稳定样本位于 306.5 ns。原夹具在 50 ns 后停止时钟，因此该阶段按 0.5 ns 记录组合输入样本；不是伪造流水周期。重新启动时钟后，日志同时记录真实时钟周期。整核程序均按上升沿前状态记录。

| 核查项 | 原夹具/差分实验 | 当前接口及因果关系 |
|---|---|---|
| 零标志 | 原始配置的非零 `rb=0e8aedf9` 对应 `rb_zero=1` | 强制 RF 数据未同步零标志，早期“不跳转”资格为 0。启用 `RF_ZERO_META=1` 后零标志变为 0，`branch_pair=1`，但 B 仍未发射。 |
| B 简单 ALU 资格 | `fetch1_instr_simple_exec_i=0`，对同一指令的真实 `triha_exec_classify` 输出为 1 | `pipe1_ok=0` 是启用 RF 元数据后仍失败的直接原因。原夹具强制 `issue_b_exec_w`，未同步现行队列的简单执行资格。 |
| 寄存器角色 | 夹具输入 A/B 均为 `111`；真实预译码应分别为 `011`/`101` | 角色位依次表示读取 rs1、读取 rs2、使用 rd。缺失角色会把分支立即数中的 rd 位段、ADDI 立即数中的 rs2 位段误当成相关寄存器。撤去角色驱动后，待决 x8 会错误阻塞 `00030463`，原期望再次失败。 |
| 预测 PC | 撤去预测 PC 驱动后，MUL 所在 B 的 E1 预测 PC 为 `00000000`，顺序下一 PC 为 `80000008` | `recover1=1` 使 MUL 的后继消费者停止发射。补齐连续预测 PC 后保留的 `early_consumer_issue/capture` 断言通过。 |
| 配对期望 | 旧期望把未提前判定的分支＋简单 ALU 统一判为不配对 | 当前实现允许 B 进行可取消的推测 ALU 运算。使用完整输入而恢复旧期望时，第一项即为 expected=0、actual=1。新夹具显式检查现行策略；整核程序另外检查恢复/异常取消和错误路径写回，未用放宽副作用检查换取通过。 |

`tb_issue_zero_pair_decoded.v` 是独立后继夹具，检查点共 6168 个。保留并补充了 pending、有效性、取指错误、中断、squash、CSR 重定向、LSU/global stall、禁止的共享单元组合，以及 MUL/消费者捕获检查。原测试仍返回 FAIL。

## 真实取指路径覆盖

`tb_zero_pair_program.v` 通过指令存储器总线向 `triha_cpu` 返回 32 位 RV32 指令，经过真实前端、FIFO、预译码、寄存器堆、发射、流水线和 LSU。配置为双发射、原生寄存器堆、`EXTRA_DECODE_STAGE=0`、`SUPPORT_SUPER=0`、`SUPPORT_MMU=0`，其余参数沿用模块默认值。正常运行 `BROKEN=0` 不执行任何内部 force。每次运行保留 `program.hex`、逐拍 `cycles.csv`、ModelSim 日志和完整输入哈希。

零比较每组覆盖 `BEQ/BNE × x0 位于 rs1/rs2 × B 为 ALU/Load/Store`，共 12 项。普通双源对照为 6 种组合各重复两次，未将重复运行描述为新的覆盖维度。

| 场景 | 运行结果 | 关键观测 |
|---|---|---|
| RF 操作数就绪，确认不跳转 | 12/12 PASS | 12 次目标 A/B 配对；4 次目标 Load、4 次目标 Store 正常完成，ALU/Load 写回值正确。 |
| 分支实际跳转，冷启动预测未命中 | 12/12 PASS | 12 次目标分支恢复；4 个推测 ALU 被取消；8 个 Load/Store 后继没有外部请求或退休。 |
| 年长 Load → A 分支 RAW | 12/12 PASS | 目标分支累计等待 108 周期；12 次采用加载前递后配对。等待期间 B 未越过 A 发射。 |
| 已取分支目标不对齐，异常后返回 | 12/12 PASS | 12 次目标故障、12 次陷入及正常 MRET；4 个推测 ALU 被取消，Load/Store 后继均未执行。 |
| 年长 Load → B RAW | 12/12 PASS | 12 次 B pending 阻塞；A 先发射，B 后续取得加载结果后独立执行，目标 A/B 配对数为 0。 |
| 普通双源分支，未在 ID 提前确认 | 12/12 PASS | 4 个简单 ALU 配对；8 个 LSU 后继独立发射。该组为 6 种组合各重复两次。 |

矩阵合计 **72/72 PASS，4656 个执行周期**，其中 **60 项零比较、12 次普通双源对照运行**。72 个程序还各包含一次真实 A→B RAW：A 生成 Store 数据，B 等待并最终写出正确值。逐拍检查验证 B 接纳蕴含 A 接纳；恢复、异常、CSR 重定向或 squash 时禁止年轻发射/LSU 有效。总线模型对外部接纳的访问检查地址、方向、写掩码、数据及次数，写回检查按 B 的 PC 匹配。

`case_matrix.csv` 按 case 列出操作码、源值、前递来源、检查计数及日志路径。表中的目标恢复/取消数按 E1 PC=`80000080` 从逐拍记录提取；程序原始计数包含末尾循环等其他控制流，未混作目标分支次数。所有有效队首的角色、ALU 控制和 B 简单执行标志，也已逐拍与对相同指令重新调用的预译码模块结果比对。

## 额外回归与保留失败

| 测试 | 状态 | 结果/解释 |
|---|---|---|
| 新完整输入夹具 | PASS | 6168 检查点。 |
| 原 `tb_e1_branch_pair` | PASS | 156 周期，9 个保持周期，4 次恢复，3 次陷入；包含年长加载完成与恢复交叠。 |
| 原 `tb_lsu_zero_program` | PASS | 377 周期，48 次加载、48 次消费者 ALU 检查，LSU A/B 发射均有覆盖。 |
| 原 `tb_issue_branch_zero_sources` | **FAIL，保留** | check=7、PC=`80000004` 时仍假定 PC[2] 将 A 选为第二槽；当前 `payload0_selected_w=1`，A 固定取 FIFO head0。原件未改。 |
| 新 `tb_issue_branch_zero_sources_head` | PASS | 694800 检查点；按当前 head0/head1 契约核对两路数据/零标志，覆盖六级前递优先级、RF 写入、复位、X/Z；强制 E2 数据时同步提供 E2 零标志。 |

额外旧夹具的后继测试没有删除数据/零标志断言。保留 PC[2]=0/1/X 刺激并检查其不能改变 A 所用队首，新增 B 两个操作数的独立数值检查。仅修正队首假设但撤去强制 E2 数据对应的零标志时，也会触发 `HEAD_ZERO_FAIL`。

选定交付记录共有 **76 次 PASS、12 次 FAIL**，并非“全部回归通过”。FAIL 分为三次旧夹具运行，以及九次诊断或故障注入：撤去 RF/simple/roles/prediction/E2 元数据、恢复旧策略期望、错误开放目标分支的 LSU 配对、禁止取消推测 B、破坏 B 零标志。错误开放 LSU 触发 `unresolved_B_LSU_issued`；禁止取消触发 `wrong_path_B_retired`。故障注入的实际测试结果均为 FAIL，运行器均返回非零。

初期运行器的编译/路径错误、新程序调试时的覆盖未命中和将 MRET 误计为陷入等记录也未覆盖或删除，全部列入 `evidence.json` 的 development inventory，未计入交付 PASS。最终程序分别检查陷入和 MRET 返回次数，并通过真实指令序列和取指速率控制使 B RAW 窗口实际出现。

## 复现与追溯

工作目录：`D:/FPGA/TriHaRiscv-cpu-dualissue-windows`。运行器采用已安装的 `D:/modeltech64_2020.4/win64` 和现有 `scripts/cpu/run_modelsim.do`，按正式 `cpu_core.json` 显式源清单编译，创建全新时间戳 build 目录。安装目录下 Pango 原语仅作为仿真模型读取并验证哈希。

```powershell
python scripts/cpu/run_document_zero_pair.py --suite legacy
python scripts/cpu/run_document_zero_pair.py --suite legacy --rf-zero-meta 1
python scripts/cpu/run_document_zero_pair.py --suite fixture
python scripts/cpu/run_document_zero_pair.py --suite program
python scripts/cpu/run_document_zero_pair.py --suite regression
python scripts/cpu/run_document_zero_pair.py --suite source-head
python scripts/cpu/run_document_zero_pair.py --suite fixture --omit simple
python scripts/cpu/run_document_zero_pair.py --suite fixture --omit rf
python scripts/cpu/run_document_zero_pair.py --suite fixture --omit roles
python scripts/cpu/run_document_zero_pair.py --suite fixture --omit prediction
python scripts/cpu/run_document_zero_pair.py --suite fixture --omit current-oracle
python scripts/cpu/run_document_zero_pair.py --suite source-head --omit e2
python scripts/cpu/run_document_zero_pair.py --suite program --case 14 --broken 1
python scripts/cpu/run_document_zero_pair.py --suite program --case 12 --broken 2
python scripts/cpu/run_document_zero_pair.py --suite source-head --broken 1
```

前两条、regression（其中旧 source 用例失败）及诊断/故障注入命令的非零退出是保留的实际结果。每次运行冻结项目输入到该次 build 的 `src/`，记录工具版本/哈希、命令、返回码、输入/输出哈希、工作目录变化；旧输出目录拒绝复用。`cycles.csv` 包含 PC/指令、源角色、源 pending、前递选择、零标志、配对资格、stall、恢复/异常、issue/accept、LSU 请求和外部 Store 接纳。源选择编码为 RF=0、WB0/1=1/2、E2_0/1=3/4、E1_0/1=5/6、x0=7；若 pending/global stall 有效，前递网络上的暂态值不表示已就绪。

关键原始结果目录，均位于 CPU 工作树 `build/cpu/`：

- 原失败：`document-zero-pair-20261102T161403861591Z/`、`document-zero-pair-20261102T161403878477Z/`。
- 完整输入夹具：`document-zero-pair-20261102T161403858111Z/`。
- 72 项整核矩阵：`document-zero-pair-20261102T163017039365Z/`。
- 额外回归（含保留的旧 FAIL）：`document-zero-pair-20261102T163337823617Z/`。
- 当前队首契约/前递检查：`document-zero-pair-20261102T161911143826Z/`。

`evidence.json` 内嵌所选运行的原始 result JSON，并给出原文件、逐拍记录、日志的绝对路径和哈希；`source_manifest.json` 登记源码身份；`case_matrix.csv` 提供逐项覆盖；`appendix_fragment.md` 为父任务可用的文字片段。

开始时 CPU 分支为干净的 `cpu-github`，HEAD=`12733df2650fa0daee98457889ee16588dd72b5c`。首次复现后、最终矩阵之前，父任务更新了 CSR、LSU、正式源清单，并改用本地 `triha_csr_regfile.v`；哈希差异已登记，不能用 HEAD 单独代表最终仿真源码。首轮矩阵结束后，父任务再次更新 CSR 标识寄存器和仿真控制条件，本任务随后对新快照重跑全部 72 项并再次通过；旧矩阵亦完整保留。最终矩阵冻结时已包含这些修改，运行期间 `live_source_changes={}`，`triha_issue.v` 自首次复现起未变。本任务只创建五个测试/运行器文件，未编辑 CSR、LSU、头文件或 vendor。

本轮验证为指定配置下的定向 ModelSim 仿真，覆盖本任务要求的配对、RAW、恢复和副作用约束；不是全 ISA、所有异常/预测状态的穷尽证明。未运行 PDS、上板、提交或推送。
