# Saturn 3SQR PSRAM 独立诊断工程

本工程用于 SS1 / SuperDock 的 3SQR QPI PSRAM 扩展板第一阶段验收。它只验证 FPGA 与 PSRAM 板之间的引脚、电气连接、QPI 协议、容量寻址和工作频率，不包含 Sega Saturn 核心，也不会用 SDRAM 或 DDR 作为替代内存。

只有本诊断在真实硬件上显示 `RESULT: PASS` 后，才进入第二阶段：把 Saturn 双 SDRAM 版本中的第二片 SDRAM（RAMH）替换为 PSRAM。

## 工程入口

- Quartus 工程：`Saturn_PSRAM_Diag.qpf`
- revision：`Saturn_PSRAM_Diag`
- 顶层封装：`sys/sys_top.v`
- 诊断顶层：`Saturn_PSRAM_Diag.sv`（模块名保持 MiSTer 要求的 `emu`）
- 输出文件：`output_files/Saturn_PSRAM_Diag.rbf`

推荐 Quartus 17.0.2 Lite 或 Standard Edition。本次验证使用 Lite Edition。命令行编译：

```sh
quartus_sh --flow compile Saturn_PSRAM_Diag
```

### 已验证构建结果

2026-07-31 使用 `theypsilon/quartus-lite-c5:17.0.2` 完成 Full Compilation：

- Quartus：17.0.2 Build 602 Lite Edition；
- 结果：Analysis & Synthesis、Fitter、Assembler、TimeQuest 全部成功，0 errors；
- RBF：`output_files/Saturn_PSRAM_Diag.rbf`，2,485,856 bytes；
- SHA-256：`26aeb9ac5006c748f179357aed36293cc0ac3437e763a11dc10658b873e0437a`；
- 视频：320×240 有效区、432×262 总时序，约 15.68 kHz / 59.84 Hz，适配 SuperDock 模拟 CRT；
- 资源：8,154 / 41,910 ALMs，384,389 / 5,662,720 RAM bits，3 / 6 PLLs；
- 整体最差 setup / hold：`+0.582 ns` / `+0.254 ns`；
- `PSRAM_SCLK` setup / hold：`+8.358 ns` / `+1.234 ns`，TNS 均为 0；
- 各阶段：Analysis & Synthesis、Fitter、Assembler、TimeQuest 均为 0 errors。

## 3SQR 引脚

| 信号 | HDMI 小板 / J1 | FPGA 引脚 | 电气标准 |
|---|---:|---:|---|
| `PSRAM_CLK` | J1-9 | `AG8` | 3.3-V LVTTL, 8 mA |
| `PSRAM_CE_N` | J1-11 | `AE15` | 3.3-V LVTTL, 8 mA |
| `PSRAM_DQ[0]` | J1-8 | `U13` | 3.3-V LVTTL, 8 mA |
| `PSRAM_DQ[1]` | J1-10 | `AH8` | 3.3-V LVTTL, 8 mA |
| `PSRAM_DQ[2]` | J1-3 | `AG13` | 3.3-V LVTTL, 8 mA |
| `PSRAM_DQ[3]` | J1-4 | `AF13` | 3.3-V LVTTL, 8 mA |

这个 revision 会让上述 6 个 FPGA 引脚脱离原来的 SD-SPI 和 SDRAM DQM 功能。普通 `Saturn`、`Saturn_DS` 等 revision 没有定义 `MISTER_PSRAM`，因此仍使用官方原始引脚和逻辑。

## 自动测试流程

上电后诊断会自动执行：

1. SPI 模式读取 `0x9F` ID，并验证 KGD 字节。
2. 发送 `0x35` 进入 QPI 模式。
3. 用基本固定图样验证 QPI 写入和读取。
4. 用多组数据图样检查数据线。
5. 用跨 4 MiB 边界的地址图样检查地址别名，验证完整 8 MiB 寻址。
6. 依次在 2.8224、4.2336、8.4672、16.9344、33.8688 MHz 下读写。

正常通过时：

- 画面背景为绿色；
- `RESULT: PASS`；
- `STAGE: 0A`；
- DE10-Nano `LED6` 亮；
- `LED7` 灭。

失败时背景为红色，`LED7` 亮，屏幕保留失败阶段、地址、期望值和实际值：

| 阶段 | 含义 |
|---:|---|
| `01` | SPI ID / KGD 失败，优先检查供电、CLK、CE_N、DQ0 |
| `03` | QPI 基本读写失败，优先检查 4 根 DQ 的顺序和焊接 |
| `04` | 数据图样失败，可能是某一根 DQ 不稳定 |
| `41` | 2 字节短读失败、3 字节延长读恢复，定位为读取最后一拍或 CE/CLK 收尾问题 |
| `42` | 3 字节延长读中的目标字仍错误，优先定位写入或稳定数据通路 |
| `43` | 3 字节延长写使目标字恢复，定位为原 2 字节写入的最后一拍或收尾问题 |
| `44` | 延长写与延长读后目标字仍错误，定位为稳定数据位通路问题 |
| `05` | 地址测试失败，可能出现容量别名或器件容量不符 |
| `06`–`0A` | 对应频率档失败，优先检查信号完整性、时序和连线 |

## 仿真

仿真需要 `iverilog` 和 `vvp`：

```sh
sh sim/psram/run_diag.sh
```

测试台同时覆盖正常器件、读数据损坏、4 MiB 地址别名和无有效 ID 四种模型。成功输出应包含：

```text
PASS: diagnostic isolates ID, QPI, address, read-tail, and stored/write faults
```

2026-07-31 已在 Ubuntu 20.04 WSL、Icarus Verilog 10.3 中实际运行并得到上述 PASS。

2026-08-03 增加 Stage 41/42 对照测试，并通过正常设备、短读末拍故障、写入数据故障、地址别名和无 ID 的故障注入仿真。

同日根据 Stage 42 真机结果增加 Stage 43/44：使用 3 字节写事务把目标 `FFFF` 移到事务中间，进一步区分写入收尾与稳定数据路径。

仿真只能验证控制状态机和故障定位，不能代替真实 SuperDock + PSRAM 小板的上板测试。

## 第二阶段边界

官方 Saturn 双 SDRAM 架构中，第二片 SDRAM连接的是 RAMH 总线；VDP2 RAM 和 SCSP RAM 仍在第一片 SDRAM。第一阶段通过后，第二阶段应在单独 revision 中为 RAMH 实现 PSRAM 适配层，并验证：

- 四字节写使能到 PSRAM 读改写/写掩码策略；
- `RAMH_BURST` 与 `RAMH_RFS` 的时序；
- `sdr2_busy` 等价的等待/背压；
- Saturn 游戏和 ST-V 工作负载下的带宽与延迟。

在第一阶段真实硬件没有达到 PASS 前，不应把 PSRAM 接入完整 Saturn 核心。
