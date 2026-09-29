# APS6408L-3OBM-BA 独立诊断 Core

Quartus revision：`Saturn_APS6408_Diag.qpf`。顶层仍是 MiSTer `sys_top`，只运行 PSRAM 诊断，不运行 Saturn 核心，也不使用 SDRAM/DDR 代替 PSRAM。

## 接线

以下映射由用户提供的两张 FPGA 接线图与 `Datesheet.pdf` 小板原理图合并得到。J1 与小板 HDMI 形状插座的同号管脚相连；这个接口承载 GPIO 信号，不是 HDMI 视频信号。

| 小板连接器脚 | PSRAM 信号 | FPGA 管脚 | 被占用的原功能 |
| ---: | --- | --- | --- |
| 1 | CLK | AH17 | KEY0 |
| 2 | CE# | AH16 | KEY1 |
| 3 | DQ2 | AG13 | SDRAM_DQML |
| 4 | DQ3 | AF13 | SDRAM_DQMH |
| 5 | DQ4 | AG10 | SDRAM_CKE |
| 6 | DQ7 | AG9 | IO_SDA |
| 7 | DQS/DM | U14 | IO_SCL |
| 8 | DQ0 | U13 | SD_SPI_MOSI |
| 9 | DQ5 | AG8 | SD_SPI_CLK |
| 10 | DQ1 | AH8 | SD_SPI_MISO |
| 11 | DQ6 | AE15 | SD_SPI_CS |

本 revision 在 RTL 顶层和 Quartus 引脚文件中隔离这些旧功能。由于 CLK、CE# 还连在板载 KEY0/KEY1 管脚上，诊断运行时不要按这两个实体按键；使用 OSD 的 `Restart test` 重跑。若另外装有会主动使用 IO_SCL/IO_SDA 的 I/O 扩展板，须先隔离它，因为 DQS/DQ7 与之共线。

## 测试内容

上电等待 2 ms 后，先用 `40h` 命令读取 MR1/MR2。屏幕显示原始两个字节；MR1 的低 5 位应为厂商码 `0D`，MR2 的低 5 位应为 64 Mbit、第三代器件码 `13`。其余位不参与比较。之后以约 4.23 MHz 发送八线 DDR OPI 线性写入 `A0h`、线性读取 `20h`。测试 25 个偶地址：地址 0、A1～A22 各自单独置 1 的地址、`3FFFFE` 和 `7FFFFE`。先全部写入不同的 16 位数据，再逐个读回；数据图样包含全 0、全 1、`00FF`、`FF00` 和交错位。此测试可发现常见数据线故障和地址线别名，但不是完整 8 MiB 扫描。读取用 DQS 的首个上升沿与随后的下降沿采样；写入时将 DQS/DM 驱动为低，以使两个字节都写入。

屏幕和 LED：

- `10`：写入；`20`：读取；`FF` / LED6：通过。
- `E1` / LED7：等待两个 DQS 数据边沿超时。
- `E2` / LED7：读回数据与写入值不一致。屏幕显示出错地址、预期值和实际值。
- `E3` / LED7：MR1/MR2 身份值不符。屏幕 `MR1/MR2` 显示原始读取值；此时内存写入测试尚未开始。

2026-09-29 首次实物运行旧版：在 `000000` 读出 `1616`，预期 `0000`，报 `E2`。仅凭该值无法区分命令/读采样、DQ 接线、写入未生效等原因；新版先读身份寄存器以缩小范围。旧版屏幕中的 “EIGHT LOCATIONS” 是遗漏更新的静态文字，实际固件测试 25 个地址。

这版诊断验证低速信号连通、基本 DDR 命令与 DQS 读回、以及地址范围。它不验证 133 MHz 上限、连续吞吐量、RAMH 适配或 Saturn 游戏运行。`PASS` 只表示上述稀疏地址的读写检查通过。

## 构建与仿真

```sh
quartus_sh --flow compile Saturn_APS6408_Diag
```

输出位于 `output_files_aps6408_diag/Saturn_APS6408_Diag.rbf`。2026-09-28 旧版全编译通过，SHA-256 为 `da060e7abf1f7c48acd229655177efdc653475989b51a3834c88bc5570a02936`；新版需重新编译后核对文件哈希。新增 MR 身份读取后，正常、数据错误、DQS 超时、A12 地址线别名及身份错误五种仿真场景均通过。

本次 TimeQuest 在 slow 100°C 模型下报告最差 setup 余量 **-28.870 ns**、最差 hold 余量 **-6.741 ns**，且整体设计存在未完全约束的路径。低速诊断采用系统时钟过采样 DQS，现有同步 I/O 约束无法准确描述「检测 DQS 后数个系统周期再采样 DQ」的条件关系；不能将本次编译视为外部 PSRAM 时序收敛。上板后应以诊断结果及示波器/逻辑分析仪验证读写窗口。若要提高频率或作为 Saturn RAMH 后端，应改用专门的 DQS/DDIO 捕获结构与相应的时序约束。

```sh
iverilog -g2012 -s tb_aps6408_diag -o /tmp/aps6408_diag.vvp \
  rtl/aps6408_diag_core.sv sim/psram/tb_aps6408_diag.sv
vvp /tmp/aps6408_diag.vvp
vvp /tmp/aps6408_diag.vvp +corrupt
vvp /tmp/aps6408_diag.vvp +no_dqs
vvp /tmp/aps6408_diag.vvp +alias_bit12
vvp /tmp/aps6408_diag.vvp +bad_id
```

仿真中的存储器是针对命令、地址、默认写延迟、DQS 和数据返回的功能模型；它不能代替器件电气时序或 FPGA 实物测试。
