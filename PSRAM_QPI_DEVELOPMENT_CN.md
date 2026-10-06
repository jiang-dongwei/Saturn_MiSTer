# Saturn 4-bit QPI PSRAM 开发续接

## 路线与基线

本目录的原有工作是 LY68L6400SLIT、4-bit SDR QPI 的 Saturn RAMH 后端。
共用远端分支后来加入了 APS6408 八线 DDR 独立诊断；该诊断的 PASS 或构建成功不能作为本 QPI 路线的验收证据。

- 生产版：约 28.64 MHz、`RAMH_SLOW=1`、16B read line、guard=8、无重复物理写，已有游戏启动与后续真机通过记录。
- 生产源码：`4c2877de6313a08d9f03327e459c1f0a4e812627`。
- 生产 RBF SHA-256：`9BC138A4145944A6FD15ACE5C17CE38D1C1CDBEE2C534E7DF49EE30A5B7F8F8D`。
- 下一候选：`Saturn_PSRAM_33M87`，控制域 67.7376 MHz、QPI 33.8688 MHz，保持 `RAMH_SLOW=1` 和原缓存参数。
- `RAMH_SLOW=0` 尚未验收；当前工作不宣称达到原 SDRAM 的最坏访问时序。

## 2026-10-06 恢复检查

本地原停在 `9cc1a92`。远端同名分支已到 `334a27e`，已通过 fast-forward 同步，既有未跟踪文件和生产 RBF 保留。
本轮在 `codex/qpi-33m87-validation` 分支补充 QPI 验证流程，不修改生产 RTL、引脚、QPI 参数或 APS6408 诊断 RTL。

QPI 工作流最近一次运行仍是 `32695005835`（源码 `6261a49`），结论为 failure。
已有 TimeQuest 报告显示：

| 检查 | 最差余量 |
|---|---:|
| PSRAM 外部时钟 setup / hold | +6.230 / +2.716 ns |
| PSRAM 控制时钟域 setup | -0.353 ns |
| 全局 setup / hold | -0.444 / -0.586 ns |

外部时钟两项为正不能代表完整 PSRAM 控制路径已收敛。
该历史报告通过新检查器解析后应失败，不能发布为已通过时序验收的真机候选。

## 验证流程

所有 HDL 仿真、Quartus、Fitter、Assembler 和 TimeQuest 均在 GitHub Runner 执行。
Quartus 固定为 `theypsilon/quartus-lite-c5:17.0.2`，本地只做文本与报告检查。

工作流 `build-saturn-psram.yml` 先运行 QPI 引擎、稳定适配器、五种子随机回归，再运行异步适配器的六组位级回归。
异步测试使用 114.547 MHz Saturn 侧与 67.7376 MHz 引擎侧时钟，覆盖 0/3/7 ns 初相差及 7/12 ns DQ 模型延迟。
覆盖初始化期间保持读取、16B 行填充和四字命中、全部 15 种非零 byte-enable、写后失效、跨行替换、RFS，以及事务中断后的协调复位恢复。
这些是功能仿真，不能代替亚稳态分析、静态时序与板级电气验证。

`build_quartus=false` 只运行回归；默认 `true` 在回归通过后执行完整构建。
完整构建额外保存 DQ 输入、CE/DQ 输出及 PSRAM 引擎端点的 setup/hold 详细路径报告。
验收脚本检查五类时序余量、两个活动时钟频率、忽略的 QPI 约束以及 DQ/CE 延迟缺失。
只有检查通过才产生带提交编号的候选副本和 SHA-256；失败时原始 RBF 与报告只作构建证据保留。

## 后续闭环

1. 根据专用路径报告定位 PSRAM 控制域的负裕量，不用宽泛 false-path 掩盖数据路径。
2. 时序通过后，在正常的四线 PSRAM 板上冷启动三次，并与 28.64 MHz 生产版做同游戏 A/B。
3. 连续运行至少 30 分钟，再测试 2～3 款不同游戏，记录加载、贴图、声音及死机异常。
4. 33.87 MHz 完整通过前不继续升频，不覆盖生产 RBF。
