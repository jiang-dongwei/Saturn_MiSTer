# SATURN-PA-BOOT-20261012：完整核心黑屏追踪

状态：仍未解决。按用户明确指定的 Kian’s Skills Plan A Debug Mode，由主 agent 与三个子 agent交叉调查。主 agent统一板测和修改，首轮子 agent只读。

## 固定基线

- 项目：`E:\WorkSpace\Rubbish\Saturn_MiSTer`；游戏包源码 bcff435025423293ca23c2e34bedfbab61537f93，Runner 37732550491。
- RBF：`Saturn_APS6408_Game_20261012.rbf`，SHA256 `34031f562b05b7c49b33c9d33ed1f98f50883b7ee75ef60139755d859fc6f17b`。没有重新编译这个游戏包。
- BIOS：用户提供的 JP 1.01，524288字节，SHA256 `dcfef4b99605f872b6c3b6d05c045385cdea3d1b702906a0ed930df7bcb7deac`。
- 默认游戏配置16.9344MHz，单变量对照8.4672MHz；DQ7外部0Ω、PSRAM直接连接；一个主SDRAM。
- 同次Linux启动ID：`50bfbede-5fa1-41c6-bc0c-2f4d2c2f4b85`。COM13、115200，仅主 agent操作。
- MiSTer版本260707；用户确认黑屏时F12仍能显示设置菜单。
- BIOS/RAML/VDP1走HPS DDR3，主SDRAM承载VDP2/SCSP，APS只替代RAMH；不能把根boot.rom摘要正确等同于FPGA内BIOS写入正确。

## 已观察事实

1. 实际BIOS在8/16MHz均黑屏。重新加载菜单后再加载、显式F2指定BIOS、S0指定Siikasaurus均未显示游戏画面。后续截图320×224全黑，摘要`30a68ae39550dee11dd3d718b82098d479189ce2582822e112936777b3329172`；首张529×240灰色噪点不能混为同一画面。
2. 同次启动下独立诊断核心2e25da3，在8/16MHz各完成262144个32位词、全1MiB、A55A/0101图样，均零错。仅验收独立核心该图样，不能替代完整Saturn验收。
3. 同次启动下完整旧核8MHz默认诊断ROM两次没有生成截图；没有错误计数，不能记录成内存FAIL或PASS。
4. HPS文件句柄实际打开Siikasaurus的game.iso与track1.wav；不能再说没有找到/打开游戏。是否持续读取、是否CPU执行仍待证。
5. 参考Main_MiSTer源码的cfg.cpp默认把C stdout改到/dev/null；实际fd4亦为/dev/null。缺少“Loading config / File selected”日志不能证明未加载。当前二进制与参考源码的逐字对应关系尚未验收。
6. 完整核原Runner整体时序未通过：clk_ram setup −0.633ns、clk_sys setup −0.088ns、clk_sys recovery −1.086ns，接收pair_high[1] setup −0.646ns。降低外部PSRAM频率不改变Saturn/引擎/PHY内部时钟。这是风险，尚非本次黑屏根因证据。

## 假设表

| 编号 | 假设与源码位置 | 支持证据 | 反证/缺口 | 状态 |
| --- | --- | --- | --- | --- |
| H1 | HPS未发送完整BIOS | 黑屏；早期仅有文件摘要 | DEBUG2已记录默认index0.0及显式index2.0各524288字节、Done、CRC32 224B752C | HPS未发送已排除；FPGA内部接收/DDR内容仍待验 |
| H2 | PSRAM初始化/运行错误令整机持续复位；Saturn.sv:658、1729 | ready要求init_done且两种error均0，直接门控rst_sys；OSD独立工作 | 当前RBF无flag/stage读口；独立核PASS不能推定完整核同样状态 | 待内部观测 |
| H3 | BIOS配置SDRAM区域后，慢RAMH后续突发词忽略WAIT；BSC.sv:393、411、587 | Runner原版反例成立，LL1配置SDRAM突发延迟1/12时第二词起出错；BIOS静态复位调用链确实先开缓存再写BCR1=03F1、MCR为32位 | 真实CACHE集成及实板到达该路径仍待验；更早复位失败亦可能 | BSC级缺陷已证，黑屏因果仍待证 |
| H4 | 完整核内部时序/复位恢复失败 | 原Runner多条setup/recovery失败，8MHz仍使用相同内部时钟 | 时序失败与当前症状尚无因果关联 | 保留 |
| H5 | SCU持续写使write_armed不再触发 | 初读状态机时疑似 | SCU.sv:1530每clk默认WR归0、CE_R单脉冲，WRITE_WAIT保持地址 | 已否定，不改写协议 |
| H6 | 仅16MHz外部链路过快 | 先前高速诊断有错 | 同RBF/BIOS改8MHz仍黑，独立8/16MHz均零错 | 单因解释减弱；不能排除完整核链路问题 |

## 预先声明的实验

| 实验 | 单变量与判据 | 实际结果 |
| --- | --- | --- |
| E1 HPS日志观察 | 备份并核对INI，临时追加[Saturn] debug=2；保持RBF/BIOS/16MHz。出现524288字节BIOS下载及Done/CRC支持HPS已完成发送；无传输需核对实际配置与自动加载路径，不能直接归因硬件。逐次重载前保存debug.txt。 | 无盘、F2、S0三份日志均保存。默认与F2传输都完成，S0有Image selected且BIOS回退完成；截图仍全黑。原INI摘要60d0d6...已恢复，临时摘要224b48...；真实BIOS与16MHz CFG不变 |
| E2 BSC协议反例 | Runner中实际写MCR A55A0040、BCR1 A55A03F1，06000000四词burst，换词延迟0/1/12个CE周期对。BCR1=03F0为单变量对照；WAIT低时不得消费、物理地址与四词正确。 | ca35b11 / Runner38219131480：LL0 64/64对照通过，LL1 192项中32项预期失败，均配置SDRAM的CBUS/DBUS burst延迟1/12；普通区全部通过。工作流SUCCESS表示成功复现失败，不是原RTL通过 |
| E3 独立反证 | 子agent C检查E2是否符合CACHE/总线契约，尝试推翻H3；不得用多数意见代替证据。 | 缺日志推论已否定。指出单改TRCAS会放行重复消费，盲目置busy又会死锁非burst；测试已加入消费地址与首请求busy检查。该TB只模拟CACHE消费契约，不等于真实CACHE集成验收 |
| E4 最小内部观测 | 如E1确认传输仍黑，独立候选RBF仅暴露init_done/init_error/adapter_error/stage、CPU活动和BIOS计数。保留门控。ready正常且复位释放否定持续复位假设；init/runtime error支持H2。 | 在确证BSC缺陷后先评估最小修复；保留观测方案，不移除保护门控 |
| E5 BSC最小候选前后对照 | 仅慢区域32位真实SDRAM burst续读转TRCAS并重新置BUSY/活跃consumer busy；单字dummy burst、16/8位、写、LL0、普通区保持原代码。原版须重复失败，候选256项须零错；非burst须排空。 | 9171350 / Runner38219635675：原版32项失败重现；候选LL0 64/64、LL1 192/192通过，快速路径CASE观察一致。仅在独立分支，生产分支与板端RBF未改 |
| E6 真实CACHE集成 | 生产CACHE+BSC，原语模型保留读地址寄存边沿；四偏移、FAST两档、延迟0/1/12/逐词不同。每次miss恰好四次正确cache RAM写入，再四词命中、无新外存请求；换tag同set重测。原版应失败、候选应通过。 | 6b36dbe / Runner38220310290 PASS：原版LL1 64项中24项失败；候选64/64与快速16/16通过。保留生产CACHE，仅用同步读地址模型替代Altera存储原语，不等于物理RAM或板测 |
| E7 完整候选构建 | 固定6b36dbe源码；三组Runner回归先通过，再Quartus17.0.2综合布局布线及原SDC报告。检查资源与内部/外部setup、hold、recovery，产物SHA唯一识别，不能仅看workflow SUCCESS。 | Runner38220583985已启动；runtime与bsc已PASS，diagnostic仍执行，Quartus尚未开始。保留全部频率菜单，PSRAM不锁最高频；编译阶段Docker内nproc设置全部可用核心，实际日志待核对 |

## 验收层级

源码交叉审查、独立候选BSC消费契约256项及真实CACHE/同步RAM模型80项前后仿真已完成；生产源码与板端RBF未改。综合布局布线、时序和原板BIOS/游戏验收待完成。历史RBF的构建成功不代表整体时序通过，历史诊断PASS不代表游戏通过。

本地日志位于聊天工作目录`work`：`plan-a-baseline-20261012-A.log`、`PA_DEBUG_*`、`GAME_BIOS*`、`GAME_SIIKA16_MGL_A.load.log`；截图和统计位于`outputs/APS6408_33MHz_20261006`。保留失败样本，不提交用户BIOS/游戏二进制到公开仓库。

E1证据：`PA_DEBUG_BIOS_ONLY_A.debug.txt:217–219`默认发送；`PA_DEBUG_F2_A.debug.txt:259–263`显式F2发送；`PA_DEBUG_S0_A.debug.txt:262–269`选盘与BIOS回退；`PA_DEBUG_S0_SCREEN_A.capture.json`记录全黑截图。默认不存在boot0～3、cd_bios.rom时的回退日志与缺少可选滤镜/存档文件，不能自动解释成启动失败。

实验恢复：`PA_DEBUG_NORMAL_RESTORE_A.log`核对原INI、16MHz Saturn.CFG、真实BIOS三份SHA，移除本轮独立核临时CFG及验证无诊断ROM所有权标记，重新加载游戏核心。板端保留一份原INI备份用于审计。独立分支首次workflow_dispatch因工作流尚未在默认分支注册返回404，随后改成仅该实验分支push触发；这是调度问题，不是HDL仿真失败。

E2范围：32位CBUS/DBUS、burst/nonburst、四个起始偏移、FAST0/1、LL0/1。DRAM0 DBUS因BSC不实现该burst，驱动表现为四个连续普通请求，只用于消费数据对照，不能计为普通区域DMA单burst协议通过。16位、真实CACHE标签/回读、仲裁与背靠背读写仍待补充。

BIOS静态证据（只读反汇编，不执行）：复位PC=20000200；文件偏移0200无条件调用0380缓存初始化、03A2写CCR=01；020E随后调用0478；0480写BCR1=A55A03F1，0484写BCR2=A55A00FC，0488写WCR=A55A5555，均在主/从分支048A之前。主CPU048E写MCR=A55A0078，从CPU返回延迟槽04A2写A55A0070，二者均32位。静态初始化链不能证明当前实板已达到这些指令。
