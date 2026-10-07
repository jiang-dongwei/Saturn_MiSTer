# APS6408L-3OBM-BA 独立诊断 Core

Quartus revision：`Saturn_APS6408_Diag.qpf`。顶层仍是 MiSTer `sys_top`，只运行 PSRAM 诊断，不运行 Saturn 核心，也不使用 SDRAM/DDR 代替 PSRAM。

每次构建的修改、测试结果和原因判断统一记在
[编译与测试记录](编译与测试记录.md)；本文保留接线、协议和详细证据。
最新位流 `14ac8ec` 实测 8.47 MHz PASS，16.93/33.87 MHz 仍 FAIL/E2，
不能作为高速稳定性验收；完整结果见统一记录及下方本版记录。

当前诊断通过 OSD 选择 8.47、16.93、33.87 MHz，不需要 BIOS 或游戏。
控制运行于 67.7376 MHz，DQ/DQS 使用 Cyclone V `ALTDDIO_IN` 在
135.4752 MHz 双边沿捕获，采样间隔约 3.69 ns。D0、D1 分别校准固定档位：
先在 8.47 MHz 用独立 CLK 参考核对完整 MR0/1、MR1/2，再以这些字节核对
目标速度的采样候选。当前 `CENTER` 位于 DQS 定位后第 2 个 DDR 样本，
约 7.38 ns，处于 MID 与 LATE 之间；先前 `QUARTER` 版记录保留在下方。
目前 D0 优先匹配完整 MR 参考的 MID，D1 优先有效 LATE，备选 CENTER/MID/EARLY。
内存检查不按预期数据挑选样本；高速失败后的慢速复读只提供诊断值，保留首次 FAIL。
构建成功、功能仿真通过和内部时序通过均不能替代板测，实际结果见下方逐版记录。

## 接线

J1 属于 MiSTER Pi 拓展坞。PSRAM 小板 CN5 的物理管脚经拓展坞 J1 对应到下表 FPGA 管脚。拓展坞资料中的「PCB 标准网络名」源于旧版六线接口，只能供参考，不能当作这块八线 DDR PSRAM 的实际信号名；例如 J1 9 的旧名 `psram_clk` 实际接本板 DQ5。

| CN5/J1 脚号 | PSRAM 信号 | FPGA 管脚 | 拓展坞表中的信号名 |
| ---: | --- | --- | --- |
| 1 | CLK | AH17 | KEY0 |
| 2 | CE# | AH16 | KEY1 |
| 3 | DQ2 | AG13 | Arduino_IO0 |
| 4 | DQ3 | AF13 | Arduino_IO1 |
| 5 | DQ4 | AG10 | Arduino_IO2 |
| 6 | DQ7 | AG9 | Arduino_IO3 |
| 7 | DQS/DM | U14 | Arduino_IO4 |
| 8 | DQ0 | U13 | Arduino_IO5 |
| 9 | DQ5 | AG8 | Arduino_IO6 |
| 10 | DQ1 | AH8 | Arduino_IO7 |
| 11 | DQ6 | AE15 | Arduino_IO9 |

实物照片确认主板为 Retro Remake **MiSTER Pi**。标准 DE10-Nano 的 U29 按键电路不能直接套用到此主板；先前据此认定 AH17/AH16 发生争用的结论已撤回。用户提供的 `123.pdf` 原理图证实 PSRAM 小板 CN5 1/2 分别是 CLK/CE#，9/11 分别是 DQ5/DQ6；结合拓展坞 J1 的封装管脚表，当前八线诊断引脚文件的这四根线映射正确。2026-10-06 用户确认这些管脚专用于 PSRAM，U14/AG9 没有 I²C/模拟 I/O 复用。因此复用争用不再是本轮的主要假设；该确认本身不能排除电气裕量或焊接问题。

## 测试内容

上电等待 2 ms 后，先发送四个时钟周期的 `FFh` Global Reset，并在 CE# 拉高后再等待至少 2 µs。小板原理图中 RESET# 由 10 kΩ 上拉，未连接 FPGA；因此使用 Global Reset 完成初始化。随后用 `40h` 在 8.47 MHz 读取 MR0/1、MR1/2，核对重叠 MR1 字节及厂商/密度位，并要求 DQS 候选与独立 CLK 参考的完整字节相同。MR1 的低 5 位应为 `0D`，MR2 的低 5 位应为 `13`。选择 16.93 或 33.87 MHz 时，再以该速度重读两组寄存器，分别为 D0、D1 选择匹配完整低速参考的固定采样档位；校准失败则报 E6，不写内存。

按所选速度发送八线 DDR OPI 线性写入 `A0h`、线性读取 `20h`。每轮先写再读 256 个偶地址，重复 4 组数据图样，共进行 1024 次写入和 1024 次读取。地址包括原有的 25 个稀疏地址（0、A1～A22、`3FFFFE`、`7FFFFE`），以及 231 个分散在 8 MiB 空间的地址；每轮每个地址的数据不同，以检测地址别名。4 组图样覆盖全 0、全 1 和交错位，并随地址变化。此测试仍不是完整 8 MiB 扫描。8 MHz 用 DQS 上升和下降定位两个字节；16/33 MHz 用首个上升定位 D0，一个 DDR 字节时隙后定位 D1，并单独记录下降沿。写入时将 DQS/DM 驱动为低，以使两个字节都写入。

屏幕和 LED：

- `10`：写入；`20`：读取；`FF` / LED6：通过。
- `E1` / LED7：等待接收完成超时。新版同时显示出错寄存器地址、已观察到的 DQS 边沿位置、DQS 采样值和固定 CLK 采样值；未出现的边沿位置为 `00`。
- `E2` / LED7：读回数据与写入值不一致。屏幕显示出错地址、预期值和实际值。
- `E3` / LED7：MR1/MR2 身份值不符。屏幕 `MR1/MR2` 显示原始读取值；此时内存写入测试尚未开始。
- `E4` / LED7：MR1/MR2 身份值不符，并显示同一次读取在 DQS 边沿后较早、当前、较晚三个采样位置的原始双字节值。
- `E5` / LED7：MR1/MR2 身份值不符，并显示以地址 0、1、2 发起的三次寄存器读取结果，分别为 MR0/1、MR1/2、MR2/3。
- `E6` / LED7：完整 MR 校准失败，包括身份不符、低速 DQS 候选与 CLK 参考不符，或目标速度没有匹配低速完整参考的字节档位。`DQS EDGE` 是捕获时已观察到的读阶段半时钟数，`DQS DATA` 是 DQS 触发得到的 MR1/MR2，`CLK DATA` 是不依赖 DQS、在默认 LC=5 的两个数据时隙按 CLK 延时采到的原始字节；高速下后者仅作显示。两份数据均须结合实际边沿位置判断，不能单凭其中一份就认定是真实寄存器值。

2026-09-29 首次实物运行旧版：在 `000000` 读出 `1616`，预期 `0000`，报 `E2`。仅凭该值无法区分命令/读采样、DQ 接线、写入未生效等原因；新版先读身份寄存器以缩小范围。旧版屏幕中的 “EIGHT LOCATIONS” 是遗漏更新的静态文字，实际固件测试 25 个地址。

首次 MR 身份诊断版在实物上报 `E1`、地址 `000001`、MR 显示 `0000`。这是读取 MR1 时未等到两个 DQS 数据边沿；`0000` 是未完成读取前的初值，并非器件返回值。复核器件手册后发现该版遗漏了上电 Phase 2 初始化。下一候选补充 `FFh` Global Reset，仅在 FPGA 配置后的首次诊断中发送；OSD Restart 不重复发送。须在 PSRAM 小板完全断电后冷启动验证，不能仅用 OSD Restart 代替上电测试。

Global Reset 版冷启动后由 `E1` 变为 `E3`，屏幕原始 MR 值约为 `CAAE`（以实物照片复核），说明现在出现两个 DQS 数据边沿，但读数与 MR1/MR2 预期低 5 位 `0D/13` 不符。下一候选在同一次 MR 读取中记录三个采样时间点，区分采样窗口问题与稳定但错误的总线值。

三点采样版实物报 `E4`，EARLY/MID/LATE 与 MR1/MR2 均为 `AAAA`。在本次位流内移动 DQ 采样点没有改变读数。下一候选连续读取三组不同的寄存器地址；若三组仍为同一值，应重点排查 DQ 总线驱动、接线和命令响应，而不是继续微调当前采样位置。

三地址读取版实物报 `E5`：地址 0（MR0/1）=`2B6B`，地址 1（MR1/2）=`C8AE`，地址 2（MR2/3）=`4A1B`。按器件协议，相邻两组应各有一个相同的寄存器字节；本次读数没有这种重叠，且地址 1 的 `C8/AE` 低 5 位分别为 `08/0E`，不符合 MR1/MR2 预期的 `0D/13`。这证明测试接收到了随事务变化的非恒定值，但尚不能证明这些值来自器件的有效寄存器响应。下一步先用 OSD Restart 在同一次上电中重复两到三次，记录三组数值是否重现；若不稳定，优先检查 DQS/DQ 采样和物理连接，若稳定，再检查命令/地址/延迟映射。OSD Restart 不重新发 Global Reset。

用户反馈重复测试的三组值均相同。故障可重复，随机噪声或偶发亚稳态的解释减弱，但确定性采样错位、错误 DQS 边沿、命令/地址解释错误及固定硬件连接问题仍未排除。本工程没有 RP2350 的 QMI/RXDELAY 寄存器；诊断核使用 Cyclone V 普通 IO、67.7 MHz 系统时钟过采样 DQS/DQ。SDC 中的 `set_input_delay` 是静态时序约束，并不直接移动运行时采样点。后续应先在同一位流中记录首个和第二个 DQS 边沿相对命令/CLK 的时刻，并以独立的 CLK 位置采集 DQ 作对照，不宜直接套用 RP2350 QMI 的 RXDELAY 参数。

首个 E6 候选继续读取地址 0、1、2，仅将地址 1 的 DQS 边沿计数和固定 CLK 采样结果锁存到屏幕。固定 CLK 采样在地址最后一个边沿后第 9、10 个半时钟所对应的两个数据时隙，各延迟三个 67.7 MHz 周期取 DQ。实物照片显示该候选在第三次读取（地址 `000002`）报 `E1`，屏幕显示前一次 MR1/MR2=`CAAA`；它未进入 E6 页面，因而没有展示已锁存的交叉采样值。此结果只证明第三次事务未捕获两个 DQS 边沿，不能据此判断 MR1/MR2 的两种采样是否一致。

下一候选在地址 1 读取完成后立即比较身份值和两种采样值；若不符便显示 E6，不再为了显示旧 MR 映射而增加地址 2 事务。如果地址 0 或 1 的读取仍报 E1，E1 页面也显示当次事务的 DQS 边沿计数、DQS 采样和固定 CLK 采样。若 DQS 数据和 CLK 数据不一致，先看 DQS 边沿是否早于 `090A`；若两者一致但仍不符合身份值，则排查命令/地址、DQ 位映射、总线驱动和实际芯片时序。功能仿真覆盖正常、数据损坏、DQS 全缺失、地址 1 缺失 DQS、地址线别名、错误 ID 和提前 DQS 边沿七种情形。

最新 E6 实物照片：MR1/MR2=`CAAE`，DQS EDGE=`090A`，DQS DATA=`CAAE`，CLK DATA=`CAAE`。两种采样相同且边沿位置符合仿真，读采样偏移不是首要嫌疑；这些值仍不是有效器件 ID。后续照片确认实物是 MiSTER Pi，而非标准 DE10-Nano；因此 DE10-Nano U29 争用推断无效。`123.pdf` 与拓展坞表共同证实原八线引脚映射，无需换脚重编译。

借鉴另一个工程师的 Stage 1 N230901：其 RTL 在每个 PSRAM_CLK 边沿后的一个 FPGA 周期才准备下一字节，避免当前诊断版原先的 DQ/CLK 同周期变化导致指令、地址或 D0 保持时间依赖 FPGA 输出布线偏差。新版保留 4.23 MHz 与现有采样方式，仅调整 DQ 更新时刻；寄存器读无 DQS 时约 2.9 µs 内释放 CE#，内存读在标准温度的 8 µs tCEM 限制内释放。Stage 1 的自动重试可掩盖第一次失败，因此只借鉴其底层时序与超时处理，不把其绿色 PASS 当成冷启动签核。

2026-09-30 实物确认上一版在 4.23 MHz、25 个地址下显示 `PASS/FF`，MR1/MR2=`0D93`，用户反馈重启后可稳定复现。随后扩展到 4 轮、每轮 256 个地址，实物照片仍显示 `PASS/FF`、MR1/MR2=`0D93`。当前候选将 PSRAM 时钟提高到 8.47 MHz，并把 DQS 边沿检测和数据采样提前到缩短后的半周期内；未改动命令/地址相对时钟的更新方式。

这版诊断验证低速信号连通、基本 DDR 命令与 DQS 读回、以及分散地址。它不验证 133 MHz 上限、连续吞吐量、RAMH 适配或 Saturn 游戏运行。`PASS` 只表示上述 256 个地址和 4 组图样的读写检查通过。

## 构建与仿真

### 2026-10-06：33.87 MHz 串口实测

当前 COM13 板卡是 APS6408 八线 DDR。8.47 MHz 旧候选读到
`MR1/MR2=0D93` 并通过 4×256 地址检查；四线 QPI core 不适用于此板。
诊断现在通过 OSD 选择 8.47、16.93、33.87 MHz，不需要 BIOS 或游戏。
构建和功能仿真全部在 GitHub Runner 运行，Quartus 固定为 17.0.2。

早期 33 MHz 接收增加了 8 个负边沿 DQ 输入寄存器和 DQS 首级输入寄存器，
Fitter 确认共 9 个输入寄存器实际打包进 IO。读取 MR0/1、MR1/2 时，
校验重叠的 MR1 字节及厂商/密度位，再选择有效 LATE、MID 或 EARLY 档位。
此选择仅发生在身份读取阶段，内存检查一直使用固定档位，不按预期数据
为每次读取挑选样本。错误仍冻结为 FAIL；33 MHz 失败后的 16.93 MHz
重读只显示 `SLOW` 诊断值，不能将高速失败改为 PASS。

| 位流源码 | 33.87 MHz 真机结果 | 关键原始字段 |
| --- | --- | --- |
| `334a27e` | FAIL/E2 | 地址 `000800`，预期 `000B`，实际 `0019`，SLOW `000B` |
| `9049da1` | FAIL/E6 | MR `0D8D`，EARLY `0D93`，MID `0D8D` |
| `5c71ce9` | FAIL/E6 | MR `0D9F`，EARLY `0D93`，MID `0D9F` |
| `461db60` | FAIL/E2 | MR `0D93`，EARLY 档，地址 `000080`，预期 `0007`，实际 `000E`，DQS `0B0E`，SLOW `0007` |
| `fbf63bb` | FAIL/E2 | MID 档，第三图样地址 `000000`，预期 `A55A`，实际 `A5DA`，DQS `0B0C`，SLOW `A55A` |
| `a64523b` | FAIL/E6 | EARLY `000D`，MID `059F`，LATE `0D93`；先前只校准两档，无法选择有效 LATE |
| `f5abd7a` | FAIL/E2 | LATE 档，地址 `339EE4`，预期 `FF7F`，实际 `FFFF`，DQS `0A00`，SLOW `FF7F` |
| `c2468d8` | FAIL/E2 | 两次配置分别在 `000000` 出现 `A55A→A5DA`、在 `339EE4` 出现 `FF7F→FFFF`；均为 DQ7 差异 |
| `bbcbf6e` | FAIL/E2 | 两次配置均在 `000000` 出现 `A55A→A5DA`；LATE、DQS `0A0B`、16 MHz 重读 `A55A` |

`461db60` 的同一固件在 8.47 和 16.93 MHz 均 PASS/FF；17 项仿真通过。
它的 RBF 为 2,447,824 字节，SHA-256
`96e6782171893628805b873d35e76d744f334bee2fc6f4a96d0f356de7da808c`。
多角 TimeQuest 最差 setup/hold 为 -36.572/-8.229 ns，仍未时序签核。

针对内存读取出现不相邻的两个 DQS 边沿，后续诊断在 33 MHz 用首个
DQS 上升沿定位 D0，D1 在一个 DDR 半周期后使用同一档位采样；下降沿
单独记录，未观察到时为 `00`。8/16 MHz 仍分别按原 CLK/DQS 边沿定位数据。
新增延迟内存下降沿的模型场景用于验证该诊断，不代表器件电气时序合规。
该版本 `fbf63bb` 的 18 项仿真、Quartus 编译和串口完整性校验通过，
真机完成前两组图样后，在第三组出现 DQ7 单比特差异，仍为 FAIL。
RBF 为 2,470,248 字节，SHA-256
`99a871ba5bbb83a8a8bb4eeb778e4f33bbb0ec641b50cd529900309d818c1e2c`。
多角 setup/hold 为 -36.420/-8.229 ns。

后续使用 APS 专用 PLL 将采样时钟改为 270.9504 MHz，外部 PSRAM
仍以 8.47/16.93/33.87 MHz 运行；33 MHz 每个 DDR 字节有 4 个采样周期。
上电与复位恢复计数同步加倍，以保持 2 ms/2 µs 的等待时间；外部时钟
约束相应改为 divide-by-8。原 QPI PLL 不变。`a64523b` 实测只有 LATE
寄存器得到有效身份值，因未提供该档位而报 E6；其多角 setup/hold 为
-41.339/-8.712 ns。

三档校准版按有效 LATE、MID、EARLY 的顺序选择固定档位。`f5abd7a`
在 33 MHz 通过身份训练，但内存仍出现 DQ7 错误；同版 8 MHz PASS，
16 MHz 在地址 `09240E` 预期 `002B`、实际 `0023`，三个诊断样本却均为
`002B`，暴露主读与诊断样本使用不同输入捕获路径的问题。

`c2468d8` 在 DQS 检测后的负边沿用 IO 输入寄存器捕获 LATE 数据，
下一正边沿将同一份样本提交到身份训练样本和主读数据寄存器。
16 MHz 主读也改用该 IO 输入寄存器，8 MHz 路径不变。新增仅 LATE
有效的窗口、该窗口的数据损坏和错误 ID 场景，共 21 项仿真。
用户确认 U14/AG9 等引脚仅用于 PSRAM，没有 I²C/模拟 IO 引脚复用。
本版 [Runner 37421172419](https://github.com/jiang-dongwei/Saturn_MiSTer/actions/runs/37421172419)
的 21 项功能仿真和 Quartus 编译成功，Fitter 确认 9 个 IO 输入寄存器。
RBF 为 2,453,308 字节，SHA-256
`2056d86c3b7fee0f6ae0bf178b1cb4302b5cb2fbe4cfb994ab61cef70406c938`。
COM13 发送后板端长度和 SHA-256 一致，加载独立测试文件
`/media/fat/_Console/APS6408_33_CADENCE_c2468d8.rbf`。

真机 8.47 MHz PASS/FF；16.93 MHz FAIL/E6，MR=`0D00`、DQS=`0900`，
未读全身份寄存器；33.87 MHz 两次配置均 FAIL/E2，身份 `0D93`、
RX LATE、DQS=`0A00`，故障字段见上表。对应 16 MHz 慢速重读分别为
`A500`、`FF00`，本版低速重读路径也存在回归，不能据此判定写入正确与否。
该轮板上保留本版 33 MHz 失败页面，CFG 首字节 `10h`。

最差 setup/hold 为 -40.710/-8.713 ns；slow 100°C 模型的采样时钟域
Fmax 仅 71.87 MHz，远低于实际 270.9504 MHz。这是控制逻辑/输入捕获
时序仍未收敛的证据，不能简单解释为外部约束保守，也不能宣称采样移动
已解决问题。后续应先分离高速接收捕获与较低频控制逻辑、取得关键路径
报告并收敛内部时序，再以真机验证 DQ7 的有效窗口。

详细基线 `d51ba5d` 的 slow 100°C 报告证实内部最差 setup 为
−5.112 ns：负边沿 IO 输入到比较逻辑只有 1.845 ns，数据路径
5.787 ns。`cell_index` 到发送数据路径也达到 9.273 ns。
这些是内部路径问题，不能归因于外部 `set_input_delay`。

`bbcbf6e` 将流程、地址和数据比较移至 67.7376 MHz，独立接收模块
仍以 270.9504 MHz 同一正边沿采样，先经无条件流水寄存器再锁存。
CLK 参考读数在接收模块内保持，经完成信号同步后传给控制器。
发送数据在 67 MHz 正边沿准备、负边沿提交，模型验证至少 3 ns
建立和保持时间；原有 2 ms/2 µs 初始化等待和外部 I/O 约束不变。
[Runner 37428192103](https://github.com/jiang-dongwei/Saturn_MiSTer/actions/runs/37428192103)
通过 21 项加强仿真及编译，Fitter 打包 9 个输入寄存器。
四角内部 setup/hold 最差 −1.988/+0.151 ns，仍未通过。
最差路径现在是 `dq_input_sample[3]` 到 `dq_prev[3]`，IO 到逻辑
数据延迟 4.272 ns、时钟偏差 −1.206 ns，而可用周期只有 3.690 ns。
整体 setup/hold 为 −35.649/−8.103 ns；两类报告分别保留。

该版 COM13 传输后的长度和 SHA-256 一致。33.87 MHz 两次重载均
FAIL/E2，字段见上表；16.93 MHz 在 `40EDA8` 出现
`3FC0→BFC0`，MID=`3FC0`、LATE=`BFC0`，仍涉及 DQ7。
8.47 MHz 身份 DQS 数据为 `0D93`，固定 CLK 参考为 `000D`，
因此报 E6；这是参考采样提前，不能将该次身份校验记作 PASS。
RBF 2,455,432 字节，SHA-256 为
`473cad2ea2dc142eb0e6ffda7c6447fe586cbc46059b5a5d02c956f36c52d825`。

接收修复采用 Cyclone V `ALTDDIO_IN`：135.4752 MHz 双边沿采样，
每 3.69 ns 一个样本，两路先寄存，再以 135 MHz 处理 DQS 事件和
EARLY/MID/LATE 候选。控制和发送仍为 67.7376 MHz，外部频率不变。
固定 CLK 参考考虑流水历史中的最后一个地址下降沿；8 MHz 另加
两个接收周期等待，使采样处于字节中部。功能模型描述 DDR 输入的
负边沿采样及正边沿重同步，不能替代器件电气检查。

### DDR 输入版 `b0f020f`：实际构建与板测

[Runner 37430906883](https://github.com/jiang-dongwei/Saturn_MiSTer/actions/runs/37430906883) 的 21 项仿真及 Quartus 17.0.2 编译完成。
位流使用 135.4752 MHz ALTDDIO 双边沿捕获，控制为 67.7376 MHz。
四角内部 setup/hold 最差为 0.389/0.167 ns，内部检查 PASS。
整体 setup/hold 仍为 -36.177/-8.228 ns，不能视为整机 PVT 签核。
COM13 传输后长度与 SHA-256 一致；以下全部来自板端原始截图：

- `16MHz_b0f020f_1`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 16.93 MHZ; ADDRESS:  40EDA8; EXPECTED:  3FC0; ACTUAL:  BFC0; RX TAP: LATE
- `33MHz_b0f020f_1`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 33.87 MHZ; ADDRESS:  000000; EXPECTED:  A55A; ACTUAL:  A5DA; RX TAP: LATE; DQS EDGES: 0A00   SLOW: A55A
- `33MHz_b0f020f_2`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 33.87 MHZ; ADDRESS:  000000; EXPECTED:  A55A; ACTUAL:  A5DA; RX TAP: LATE; DQS EDGES: 0A00   SLOW: A55A
- `8MHz_b0f020f_1`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 8.47 MHZ; ADDRESS:  40EDA8; EXPECTED:  3FC0; ACTUAL:  BFC0; RX TAP: LATE

RBF `APS6408_33MHz_b0f020f.rbf` 为 2,439,908 字节，SHA-256
`5fb40fa305ba6bf5a7d55b7f76e5ba24bd71fa809cb4d23c44f44b82f571a57a`。板上最终保留最后一次 33.87 MHz 页面，CFG 首字节 `10h`。
没有断电冷启动、完整 8 MiB 扫描、Saturn/RAMH 或游戏验证。

### DDR 输入版 `e133f8c`：实际构建与板测

[Runner 37432637025](https://github.com/jiang-dongwei/Saturn_MiSTer/actions/runs/37432637025) 的 22 项仿真及 Quartus 17.0.2 编译完成。
位流使用 135.4752 MHz ALTDDIO 双边沿捕获，控制为 67.7376 MHz。
四角内部 setup/hold 最差为 0.5/0.167 ns，内部检查 PASS。
整体 setup/hold 仍为 -36.177/-8.228 ns，不能视为整机 PVT 签核。
COM13 传输后长度与 SHA-256 一致；以下全部来自板端原始截图：

- `16MHz_e133f8c_1`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 16.93 MHZ; ADDRESS:  3994CC; EXPECTED:  FF73; ACTUAL:  FFF3; RX TAP: MID
- `33MHz_e133f8c_1`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 33.87 MHZ; ADDRESS:  000002; EXPECTED:  A45B; ACTUAL:  A4DB; RX TAP: LATE; DQS EDGES: 0A00   SLOW: A4DB
- `33MHz_e133f8c_2`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 33.87 MHZ; ADDRESS:  000002; EXPECTED:  A45B; ACTUAL:  A4DB; RX TAP: LATE; DQS EDGES: 0A00   SLOW: A4DB
- `8MHz_e133f8c_1`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 8.47 MHZ; ADDRESS:  3994CC; EXPECTED:  FF73; ACTUAL:  FFF3; RX TAP: MID

RBF `APS6408_33MHz_e133f8c.rbf` 为 2,440,672 字节，SHA-256
`b56c7b562f716d0680f32f74cb94c32c062712ce13eb30893083ebd4a660c74e`。板上最终保留最后一次 33.87 MHz 页面，CFG 首字节 `10h`。
没有断电冷启动、完整 8 MiB 扫描、Saturn/RAMH 或游戏验证。

本版 LATE 为 DQS 定位后第 3 个 DDR 样本。8/16 MHz 也校准固定档位，优先有效 MID，再尝试 LATE/EARLY；33 MHz 优先有效 LATE。慢速诊断重读固定 MID，不能覆盖首次高速 FAIL。

### DDR 输入版 `f59b7f8`：实际构建与板测

[Runner 37437042902](https://github.com/jiang-dongwei/Saturn_MiSTer/actions/runs/37437042902) 的 22 项仿真及 Quartus 17.0.2 编译完成。
位流使用 135.4752 MHz ALTDDIO 双边沿捕获，控制为 67.7376 MHz。
四角内部 setup/hold 最差为 0.753/0.135 ns，内部检查 PASS。
整体 setup/hold 仍为 -36.177/-8.228 ns，不能视为整机 PVT 签核。
COM13 传输后长度与 SHA-256 一致；以下全部来自板端原始截图：

- `16MHz_f59b7f8_1`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 16.93 MHZ; ADDRESS:  123F62; EXPECTED:  003D; ACTUAL:  00BD; RX TAP: MID         D1: LATE
- `33MHz_f59b7f8_1`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 33.87 MHZ; ADDRESS:  000004; EXPECTED:  FFFD; ACTUAL:  FFFF; RX TAP: MID         D1: QTR; DQS EDGES: 0A00   SLOW: FFFD
- `33MHz_f59b7f8_2`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 33.87 MHZ; ADDRESS:  000004; EXPECTED:  FFFD; ACTUAL:  FFFF; RX TAP: MID         D1: QTR; DQS EDGES: 0A00   SLOW: FFFD
- `8MHz_f59b7f8_1`: RESULT: PASS; STAGE:  FF; MR1 MR2:  0D93; CLOCK: 8.47 MHZ; ADDRESS:  000000; EXPECTED:  0000; ACTUAL:  0000; RX TAP: MID         D1: LATE

RBF `APS6408_33MHz_f59b7f8.rbf` 为 2,431,304 字节，SHA-256
`1fece00097198951e41d3700aba0c4de3eccf1453a13ae256884155f463dda5d`。板上最终保留最后一次 33.87 MHz 页面，CFG 首字节 `10h`。
没有断电冷启动、完整 8 MiB 扫描、Saturn/RAMH 或游戏验证。

本版分别校准 D0/D1，新增 DQS 定位后第 1 个 DDR 样本 QUARTER。先在 8.47 MHz 用 CLK 参考验证完整 MR0/1、MR1/2；目标速度的两个字节均须匹配这些参考。D0 优先有效 MID；低速 D1 优先 LATE，33 MHz D1 优先 QUARTER。诊断复读沿用低速参考档位，未另作 16.93 MHz 校准；任何复读均不覆盖首次 FAIL，也不按内存预期值选样本。

### DDR 输入版 `ece1b37`：实际构建与板测

[Runner 37439155495](https://github.com/jiang-dongwei/Saturn_MiSTer/actions/runs/37439155495) 的 24 项仿真及 Quartus 17.0.2 编译完成。
位流使用 135.4752 MHz ALTDDIO 双边沿捕获，控制为 67.7376 MHz。
四角内部 setup/hold 最差为 0.702/0.164 ns，内部检查 PASS。
整体 setup/hold 仍为 -36.177/-8.228 ns，不能视为整机 PVT 签核。
COM13 传输后长度与 SHA-256 一致；以下全部来自板端原始截图：

- `16MHz_ece1b37_1`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 16.93 MHZ; ADDRESS:  000000; EXPECTED:  A55A; ACTUAL:  A5DA; RX TAP: MID         D1: CENTER
- `33MHz_ece1b37_1`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 33.87 MHZ; ADDRESS:  000000; EXPECTED:  A55A; ACTUAL:  A5DA; RX TAP: MID         D1: CENTER; DQS EDGES: 0A00   SLOW: A55A
- `33MHz_ece1b37_2`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 33.87 MHZ; ADDRESS:  000000; EXPECTED:  A55A; ACTUAL:  A5DA; RX TAP: MID         D1: CENTER; DQS EDGES: 0A00   SLOW: A55A
- `8MHz_ece1b37_1`: RESULT: PASS; STAGE:  FF; MR1 MR2:  0D93; CLOCK: 8.47 MHZ; ADDRESS:  000000; EXPECTED:  0000; ACTUAL:  0000; RX TAP: MID         D1: LATE

RBF `APS6408_33MHz_ece1b37.rbf` 为 2,453,188 字节，SHA-256
`33f0b2139a1c1319e40e191365e4ea7da5733c8f3a87428f475e2668bafcff6e`。板上最终保留最后一次 33.87 MHz 页面，CFG 首字节 `10h`。
没有断电冷启动、完整 8 MiB 扫描、Saturn/RAMH 或游戏验证。

本版 CENTER 为 DQS 定位后第 2 个 DDR 样本，约 7.38 ns。D0 优先有效 MID；8 MHz D1 优先 LATE，16/33 MHz D1 优先 CENTER。16/33 MHz 均在首个 DQS 上升后一个 DDR 字节时隙定位 D1，下降沿独立记录。先低速 CLK 完整 MR 参考，再以全部参考字节分别校准目标速度的 D0/D1；不按预期内存值选择样本。诊断复读沿用低速参考档位，未另作 16 MHz 校准，不覆盖首次 FAIL。

### DDR 输入版 `14ac8ec`：实际构建与板测

[Runner 37441144476](https://github.com/jiang-dongwei/Saturn_MiSTer/actions/runs/37441144476) 的 24 项仿真及 Quartus 17.0.2 编译完成。
位流使用 135.4752 MHz ALTDDIO 双边沿捕获，控制为 67.7376 MHz。
四角内部 setup/hold 最差为 0.7/0.162 ns，内部检查 PASS。
整体 setup/hold 仍为 -36.199/-8.228 ns，不能视为整机 PVT 签核。
COM13 传输后长度与 SHA-256 一致；以下全部来自板端原始截图：

- `16MHz_14ac8ec_1`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 16.93 MHZ; ADDRESS:  000002; EXPECTED:  A45B; ACTUAL:  A4DB; RX TAP: MID         D1: LATE
- `33MHz_14ac8ec_1`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 33.87 MHZ; ADDRESS:  000020; EXPECTED:  A05F; ACTUAL:  A0DF; RX TAP: MID         D1: LATE; DQS EDGES: 0A00   SLOW: A0DF
- `33MHz_14ac8ec_2`: RESULT: FAIL; STAGE:  E2; MR1 MR2:  0D93; CLOCK: 33.87 MHZ; ADDRESS:  000002; EXPECTED:  A45B; ACTUAL:  A4DB; RX TAP: MID         D1: LATE; DQS EDGES: 0A00   SLOW: A4DB
- `8MHz_14ac8ec_1`: RESULT: PASS; STAGE:  FF; MR1 MR2:  0D93; CLOCK: 8.47 MHZ; ADDRESS:  000000; EXPECTED:  0000; ACTUAL:  0000; RX TAP: MID         D1: LATE

RBF `APS6408_33MHz_14ac8ec.rbf` 为 2,459,776 字节，SHA-256
`27b4c5c085151f56809d71089ca208e8178db27c0bf238ceae68f65e0f578870`。板上最终保留最后一次 33.87 MHz 页面，CFG 首字节 `10h`。
没有断电冷启动、完整 8 MiB 扫描、Saturn/RAMH 或游戏验证。

本版 CENTER 为 DQS 定位后第 2 个 DDR 样本，约 7.38 ns。D0 优先有效 MID；各速度 D1 均优先匹配完整 MR 参考的 LATE，备选 CENTER/MID/EARLY。16/33 MHz 均在首个 DQS 上升后一个 DDR 字节时隙定位 D1，下降沿独立记录。先低速 CLK 完整 MR 参考，再以全部参考字节分别校准目标速度的 D0/D1；不按预期内存值选择样本。诊断复读沿用低速参考档位，未另作 16 MHz 校准，不覆盖首次 FAIL。

本测试仍仅覆盖 4 组图样、每组 256 个分散地址；既不是完整 8 MiB 扫描，
也不验证 Saturn/RAMH、游戏兼容性、连续吞吐量或冷启动/PVT 稳定性。

通过 GitHub Runner 构建，禁止在本地执行 Quartus 或 HDL 仿真：

```sh
gh workflow run build-aps6408-diag.yml --repo jiang-dongwei/Saturn_MiSTer \
  --ref codex/qpi-33m87-validation
```

输出位于 `output_files_aps6408_diag/Saturn_APS6408_Diag.rbf`。2026-09-28 旧版全编译通过，SHA-256 为 `da060e7abf1f7c48acd229655177efdc653475989b51a3834c88bc5570a02936`；新版需重新编译后核对文件哈希。新增 MR 身份读取后，正常、数据错误、DQS 超时、A12 地址线别名及身份错误五种仿真场景均通过。

本次 TimeQuest 在 slow 100°C 模型下报告最差 setup 余量 **-28.870 ns**、最差 hold 余量 **-6.741 ns**，且整体设计存在未完全约束的路径。低速诊断采用系统时钟过采样 DQS，现有同步 I/O 约束无法准确描述「检测 DQS 后数个系统周期再采样 DQ」的条件关系；不能将本次编译视为外部 PSRAM 时序收敛。上板后应以诊断结果及示波器/逻辑分析仪验证读写窗口。若要提高频率或作为 Saturn RAMH 后端，应改用专门的 DQS/DDIO 捕获结构与相应的时序约束。

以下命令由 GitHub Runner 执行；实际 workflow 还覆盖 16/33 MHz 和采样窗口：

```sh
iverilog -g2012 -DAPS6408_DIAG_SIM -s tb_aps6408_diag -o /tmp/aps6408_diag.vvp \
  rtl/aps6408_diag_core.sv rtl/aps6408_diag_rx.sv \
  rtl/aps6408_diag_ddio_input.sv sim/psram/tb_aps6408_diag.sv
vvp /tmp/aps6408_diag.vvp
vvp /tmp/aps6408_diag.vvp +corrupt
vvp /tmp/aps6408_diag.vvp +no_dqs
vvp /tmp/aps6408_diag.vvp +missing_slot1
vvp /tmp/aps6408_diag.vvp +alias_bit12
vvp /tmp/aps6408_diag.vvp +bad_id
vvp /tmp/aps6408_diag.vvp +early_dqs
```

仿真中的存储器是针对命令、地址、默认写延迟、DQS 和数据返回的功能模型；它不能代替器件电气时序或 FPGA 实物测试。

## 2026-10-07 交叉速度版本 3125dc8（待板测）

```text
APS6408 交叉速度版本 3125dc8，2026-10-07 更新
Runner https://github.com/jiang-dongwei/Saturn_MiSTer/actions/runs/37445940689 编译成功。
Quartus固定17.0.2、全部HDL仿真仅GitHub Runner；40项仿真通过、27 DDIO输入寄存器。
本地RBF 2487612 bytes，SHA256 42efd17a4a7052f0e4e926a0160dff9b5849ac3eb1162ddd44a10cb30aa1afe8。
内部四工况 setup/hold 1.065/0.15 ns，内部检查通过。
全局 setup/hold -36.177/-8.228 ns，外部接口/PVT尚未通过。
新增同速、8MHz写/目标速读、目标速写/8MHz读；OSD status[8:7]选择0/1/2。
训练按读取速度选择：先8MHz完整CLK/MR参考，读速非零时再做目标速MR训练。
失败复读改为独立校准的8MHz，屏幕R8字段；首次FAIL保留。内存预期值不参与挑样。
新增16个定向故障场景，确认高速读错在8MHz复读恢复，已写入错误仍被检出。

板测：未完成、未加载新版。串口上传在80%后ClearCommError/拒绝访问，随后COM13消失。
设备清单确认COM13为CH9101 VID1A86/PID55D8；当前COM11是另一台CH343，不可替代。
上传只有PREFLIGHT:0；没有RECEIVED、VERIFY:0、FINAL:0，不能声称板上长度/哈希验证成功。
远端目标/media/fat/_Console/APS6408_CROSS_3125dc8.rbf不应视为有效位流；可能只留下本次.upload.gz.part。
没有新版截图或交叉实测，DQ7根因仍未确认。上一版8MHz PASS、16/33MHz FAIL不能记为本版结果。
待COM13接回后恢复shell、检查并清理本次专用传输残留、重新上传核验，再运行九次交叉矩阵。
4图样×256分散地址；尚无完整8MiB、冷启动、Saturn/RAMH游戏或PVT验收。
```

## 2026-10-07 串口上传容错及控制台重试

2026-10-07 开发补记（未重新编译 FPGA）：
新增 scripts/aps6408_serial_upload.py，默认COM13/115200 8N1。
接收使用180秒超时并恢复原终端属性；恢复后只接收本次release token，防止迟到的二进制字节进入命令执行。
每次传输使用独立临时文件，核对解压长度/SHA256后才改成最终文件名；拒绝覆盖现有目标及使用Saturn生产文件名。
登录失败或串口断开时关闭端口；日志保留本次临时路径和接收release token。
7项主机故障测试通过：命令回显、错误板端/已有目标、接收超时、完整性失败、串口断开、成功校验顺序、生产文件保护。
这些是Python主机测试，不是新的HDL仿真或板端验收，FPGA位流仍为3125dc8。
硬件重试：COM13的CH9101已重新枚举。普通连接超时；补满已知700315字节接收预算的空白恢复仍没有字符。
用户确认重新上电后，再连接并监听25秒收到0字节，无启动/login/root输出。当前不能加载新版、无交叉板测结果。
等待确认Linux控制台的COM口及TX/RX/GND连接。DQ7根因未确认。

上传脚本需要 Python 3 和 pyserial，密码可通过 `APS6408_SERIAL_PASSWORD` 环境变量或 `--password` 提供。

```powershell
python scripts/aps6408_serial_upload.py <本地RBF路径> /media/fat/_Console/APS6408_CROSS_3125dc8.rbf --port COM13 --log <日志路径>
python scripts/test_aps6408_serial_upload.py
```

断线后等接收超时，再使用日志中的 `Receiver release token`：给同一次重试增加 `--release-receiver <token>`。
此选项只适用于本脚本的接收握手；旧上传程序没有这个握手，不能套用。失败临时文件留作证据；确认属本次传输后才清理。
当前尚未在板端验证新脚本的超时/恢复行为。未改动PSRAM时钟、接收档位或原生产RBF。

## 2026-10-07 完整启动日志与系统异常

2026-10-07完整启动复测：用户断电上电后确认菜单出现。COM13连续180秒保存181428字节；zImage_dtb读取7361361字节并Starting kernel，MiSTer识别MENU。Linux启动中缺/dev/pts、/dev/shm目录，sync、sleep、mkdir、cat等命令反复Segmentation fault。随后25秒登录探测保存171772字节、2934次Segmentation fault；收到login/Password并发送授权凭据，未得到root Shell。现阶段证实系统命令异常，尚不能确认SD文件损坏、版本兼容或运行内存异常；与APS DQ7错误分开调查。新版3125dc8未上传/加载，九次交叉测试未执行；等待板子IP以尝试网络登录，或断电后SD接读卡器做只读校验。COM13已关闭释放。
