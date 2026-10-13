# SATURN-PA-BOOT-20261012：完整核心黑屏追踪

状态：部分改善，游戏验收仍待完成。按用户明确指定的 Kian’s Skills Plan A Debug Mode，由主 agent 与三个子 agent交叉调查。主 agent统一板测和修改，首轮子 agent只读。

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
| H3 | APS单词缓存不满足原BSC后续SDRAM突发契约；BSC.sv:393、411、587 / adapter:36–41 | Runner原版配慢后端反例成立，配置SDRAM突发延迟1/12时第二词起出错；BIOS复位链先开缓存再设32位SDRAM。原版DDR3后端预取32B块，APS只存一个32位词，换址即miss | 候选CACHE回归已通过；实际APS核是否到该分支/更早复位失败仍待验。不能将整合不匹配泛称所有上游BSC都有故障 | 整合握手缺陷已复现，黑屏因果待板测 |
| H4 | 完整核内部时序/复位恢复失败 | 原Runner多条setup/recovery失败，8MHz仍使用相同内部时钟 | 时序失败与当前症状尚无因果关联 | 保留 |
| H5 | SCU持续写使write_armed不再触发 | 初读状态机时疑似 | SCU.sv:1530每clk默认WR归0、CE_R单脉冲，WRITE_WAIT保持地址 | 已否定，不改写协议 |
| H6 | 仅16MHz外部链路过快 | 先前高速诊断有错 | 同RBF/BIOS改8MHz仍黑，独立8/16MHz均零错 | 单因解释减弱；不能排除完整核链路问题 |
| H7 | 手柄Start未到游戏输入路径，或CPU无法处理 | 8MHz截图到标题但手柄Start无反应；F12设置仍可打开 | 用户明确关闭F12后仍无反应，排除仅在OSD内操作；诊断Start current/sticky和CPU活动尚未上板读取 | 待内部帧证据 |
| H8 | 未缓存SDRAM读的dummy遗留事务跨CPU→SCU仲裁，导致SCU单拍请求未被APS捕获 | BSC单读续接真实地址+4与RD脉冲；APS source_pending不随CS撤回取消；grant无额外后端busy门，SCU START不先查ECWAIT | 尚未Runner反例或实板证据。必须证明合法仲裁时旧dummy仍pending，而非强制构造非法忙时写；与已否定持续WR假设不同 | 条件性兼容风险，未改协议 |

## 预先声明的实验

| 实验 | 单变量与判据 | 实际结果 |
| --- | --- | --- |
| E1 HPS日志观察 | 备份并核对INI，临时追加[Saturn] debug=2；保持RBF/BIOS/16MHz。出现524288字节BIOS下载及Done/CRC支持HPS已完成发送；无传输需核对实际配置与自动加载路径，不能直接归因硬件。逐次重载前保存debug.txt。 | 无盘、F2、S0三份日志均保存。默认与F2传输都完成，S0有Image selected且BIOS回退完成；截图仍全黑。原INI摘要60d0d6...已恢复，临时摘要224b48...；真实BIOS与16MHz CFG不变 |
| E2 BSC协议反例 | Runner中实际写MCR A55A0040、BCR1 A55A03F1，06000000四词burst，换词延迟0/1/12个CE周期对。BCR1=03F0为单变量对照；WAIT低时不得消费、物理地址与四词正确。 | ca35b11 / Runner38219131480：LL0 64/64对照通过，LL1 192项中32项预期失败，均配置SDRAM的CBUS/DBUS burst延迟1/12；普通区全部通过。工作流SUCCESS表示成功复现失败，不是原RTL通过 |
| E3 独立反证 | 子agent C检查E2是否符合CACHE/总线契约，尝试推翻H3；不得用多数意见代替证据。 | 缺日志推论已否定。指出单改TRCAS会放行重复消费，盲目置busy又会死锁非burst；测试已加入消费地址与首请求busy检查。该TB只模拟CACHE消费契约，不等于真实CACHE集成验收 |
| E4 最小内部观测 | 如E1确认传输仍黑，独立候选RBF仅暴露init_done/init_error/adapter_error/stage、CPU活动和BIOS计数。保留门控。ready正常且复位释放否定持续复位假设；init/runtime error支持H2。 | 在确证BSC缺陷后先评估最小修复；保留观测方案，不移除保护门控 |
| E5 BSC最小候选前后对照 | 仅慢区域32位真实SDRAM burst续读转TRCAS并重新置BUSY/活跃consumer busy；单字dummy burst、16/8位、写、LL0、普通区保持原代码。原版须重复失败，候选256项须零错；非burst须排空。 | 9171350 / Runner38219635675：原版32项失败重现；候选LL0 64/64、LL1 192/192通过，快速路径CASE观察一致。仅在独立分支，生产分支与板端RBF未改 |
| E6 真实CACHE集成 | 生产CACHE+BSC，CACHE_RAM保留posedge注册读地址，TAG/VALID/LRU按实际MLAB异步读；四偏移、FAST两档、延迟0/1/12/逐词不同。每次miss恰好四次正确cache RAM写入，再四词命中、无新外存请求；换tag同set重测。原版应失败、候选应通过。 | 6b36dbe / 38220310290旧模型PASS保留，但其后三类存储模型误读同名未引用文件，不再计为生产时序匹配。修正08f3b8d / 38221596989：原版24失败、候选快16/慢64全通过；a4d67db / 38221839189追加零初值/旧有效内容两组，候选160/160通过，原版各24失败。均为数字RAM模型，非物理RAM验收 |
| E7 完整候选构建 | 固定6b36dbe功能源码；三组Runner回归先通过，再Quartus17.0.2综合布局布线及原SDC报告。检查资源与内部/外部setup、hold、recovery，产物SHA唯一识别，不能仅看workflow SUCCESS。 | Runner38220583985三门禁PASS后Fitter失败：需求4207 LAB，器件4191，超出16；没有RBF及完整STA。其CACHE旧模型范围已撤回，额外更正回归38221839189已PASS且功能源码无diff。Info20032并行设4，Warning20031同时报系统检测2，不据此声称4物理核 |
| E8 资源单变量对照 | 保留BSC/PHY/频率/QSF/SDC，仅关闭APS6408的12个逻辑FB RAM实例在线JTAG编辑；默认其他core为YES。历史31b65d9曾布局成功，但不同基线不能直接推定本轮节省。须检查附加编辑网络消失、功能RAM参数不变、新fit/STA。 | e42c61b / Runner38224686093三门禁及完整构建成功，12个FB RAM参数NO、SLD hub消失已由报告确认。最终40117 ALM、43594 FF、4186/4191 LAB、逻辑RAM4006464位。nproc=4、online=4、allowed0-3、Quartus并行4，本轮无20031警告。整体STA仍FAIL；RBF4571892B，SHA3c1c5e9c8dc25da28a0b70615bb83c37df1d7a706efa517cfdee2791e70edced；板测待完成 |
| E9 官方单SDRAM正对照 | 只切换板端既有官方Saturn_20251003.rbf，保持同boot/真实JP BIOS/其他Saturn.CFG；其RAMH走板载DDR3，CFG中的APS频率位无效。若显示BIOS/游戏，降低HPS/文件/主SDRAM整体失效解释；仍黑则不能把故障仅归于APS路径。不同发布/拟合版本不能独立证明BSC补丁解决原故障。 | 官方Git blob faa1a6fcbfbd7e26cb4c50cea31c215fec8e5c55 / SHA a78fc42b1890e4293e259dacfc871d906873a90013eab5dcb22f6b48adf11a37。板端同boot下显示BIOS界面；同Siikasaurus CUE进入PRESS START，连续截图确认动画更新。用户明确反馈能进入游戏并正常操作。BIOS/INI/CFG SHA不变，未覆盖RBF。记原版DDR3后端正常运行，不计APS8/16/33MHz通过 |

## 验收层级

源码交叉审查、独立候选BSC消费契约256项及更正后的真实CACHE/M10K/MLAB模型160项前后仿真已完成。候选e42c61b已完成综合布局布线并生成RBF，生产源码及原RBF保留；整体STA未通过，原板BIOS/游戏验收待完成。历史诊断PASS不代表游戏通过。

e42时序证据：四工况最坏全局setup/hold为−37.401/−7.735ns，DDIO到逻辑−0.723/+1.073ns，PSRAM内部寄存器组（含50MHz实验档）−5.501/−1.077ns；默认STA主clk_ram为−1.145/−0.323ns，主clk_sys为+0.153/+0.244ns。实验板测不计时序签核。

E10候选板测预声明：同boot、JP1.01 BIOS、Siikasaurus、其他CFG不变，仅换为e42 RBF；先16.9344MHz再8.4672MHz。若BIOS和游戏恢复且可操作，支持候选整合修复；若仍黑，则H3逻辑缺陷修复已被仿真验证，但不是已确认的唯一黑屏原因，继续E4观测ready/error/stage与CPU活动。截图只判断画面，游戏操作须用户确认，仍不能验收33/50MHz或所有游戏。候选另存APS6408_PLAN_A_e42c61b.rbf，不覆盖原开发/官方RBF。

E7资源证据：新旧同阶段map估算ALM 40581→40734，寄存器41653→41655，逻辑RAMbits均4006464；新Fitter预布局41692ALM/4207LAB，旧完整布局41424ALM/4191LAB。不同阶段FF不直接比较。两个BSC实体组合ALUT总数1100→1099、寄存器不变，因此不能把全设计打包增长说成“七行BSC补丁直接膨胀268ALM”。失败为近满设计的布局容量；本次没有新的时序slack可报告。

本地日志位于聊天工作目录`work`：`plan-a-baseline-20261012-A.log`、`PA_DEBUG_*`、`GAME_BIOS*`、`GAME_SIIKA16_MGL_A.load.log`；截图和统计位于`outputs/APS6408_33MHz_20261006`。保留失败样本，不提交用户BIOS/游戏二进制到公开仓库。

E1证据：`PA_DEBUG_BIOS_ONLY_A.debug.txt:217–219`默认发送；`PA_DEBUG_F2_A.debug.txt:259–263`显式F2发送；`PA_DEBUG_S0_A.debug.txt:262–269`选盘与BIOS回退；`PA_DEBUG_S0_SCREEN_A.capture.json`记录全黑截图。默认不存在boot0～3、cd_bios.rom时的回退日志与缺少可选滤镜/存档文件，不能自动解释成启动失败。

实验恢复：`PA_DEBUG_NORMAL_RESTORE_A.log`核对原INI、16MHz Saturn.CFG、真实BIOS三份SHA，移除本轮独立核临时CFG及验证无诊断ROM所有权标记，重新加载游戏核心。板端保留一份原INI备份用于审计。独立分支首次workflow_dispatch因工作流尚未在默认分支注册返回404，随后改成仅该实验分支push触发；这是调度问题，不是HDL仿真失败。

E2范围：32位CBUS/DBUS、burst/nonburst、四个起始偏移、FAST0/1、LL0/1。DRAM0 DBUS因BSC不实现该burst，驱动表现为四个连续普通请求，只用于消费数据对照，不能计为普通区域DMA单burst协议通过。16位、真实CACHE标签/回读、仲裁与背靠背读写仍待补充。

BIOS静态证据（只读反汇编，不执行）：复位PC=20000200；文件偏移0200无条件调用0380缓存初始化、03A2写CCR=01；020E随后调用0478；0480写BCR1=A55A03F1，0484写BCR2=A55A00FC，0488写WCR=A55A5555，均在主/从分支048A之前。主CPU048E写MCR=A55A0078，从CPU返回延迟槽04A2写A55A0070，二者均32位。静态初始化链不能证明当前实板已达到这些指令。

模型纠错与限制：files.qip:5实际引用`rtl/SH7604_mem.sv`，未引用`rtl/SH/SH7604/SH7604_mem.sv`。首次审查据后者误设TAG/VALID/LRU为negedge注册读，撤回生产时序匹配结论；实际前三类为MLAB异步读，CACHE_RAM为M10K注册读地址。生产MLAB允许未知初值，Verilator二态模型只覆盖零和预先有效旧内容，检查DIRTY复位屏蔽及复位后旧cache再次miss；不宣称真实X态或原语CONSTRAINED_DONT_CARE读写冲突行为已覆盖。

E9证据：`PA_STOCK_CORE_IDENTITY_A.log`与官方仓库contents API元数据一致；`PA_NATIVE_BIOS_SCREEN_A.png`为320×224 BIOS/CD控制界面；`PA_NATIVE_SIIKA_SCREEN_A/B.png`均320×240 PRESS START，SHA分别6278f746... / 07dc355b...，背景与三维模型姿态变化；`PA_NATIVE_SIIKA_RUNTIME_A.log`记录同boot、三文件SHA一致及ISO/WAV打开。板上当前临时为官方DDR3后端正常版本，不冒充APS候选。


E10初步实板结果：e42独立RBF已上传且板端SHA一致。16MHz无盘BIOS正常（PA_E42_BIOS16_A，1493色）；同Siikasaurus加载过渡图形、纯蓝后晚期全黑（SCREEN16_C），操作反馈/是否手动重载待核对。8MHz首次无盘截图黑，但同游戏稍后到PRESS START，两次标题截图SHA59733f93...相同；不据此宣称动画持续更新或操作通过。板端当前保留e42 APS/8MHz供用户操作，原版DDR3与旧bcff均未覆盖，真实BIOS/INI未改。

H3最小协议缺陷已被前后仿真确认，且候选改善启动；实板包含关闭FB JTAG附加网络及重新拟合，尚不能隔离成唯一黑屏原因。H2在16MHz成功BIOS/8MHz游戏标题阶段不成立为“始终未完成初始化”，但随后运行error触发复位仍保留；H4时序风险仍保留。当前未验收16MHz游戏、33/50MHz、操作流畅度或长期稳定性。

E4接口预备已只读核对：ttyS0/FFC02000为COM13控制台，ttyS1/FFC03000空闲、无uartmode守护标记/占用；TXD目前常量0且与SNAC独立。若继续异常，可构建仅UART观测候选，原域快照握手接出stage、ready/errors及复位分因；当前没有安装/执行该观测RTL。


E10重新演示：e42同boot重新演示16.9344MHz：重新加载同Siikasaurus后到PRESS START，PA_E42_REDEMO16_B截图352×720，重复画面与颜色异常。用户按Start明确反馈进入后卡住或黑屏；PA_E42_REDEMO16_AFTER_START_A截图与标题异常图SHA相同29d42a1a...。确认该轮16MHz游戏验收失败，不能将BIOS/标题显示称游戏通过。随后重新加载8.4672MHz进行同样操作对照，结果待确认。


8MHz重新演示后首次截图全黑，随后PA_E42_REDEMO8_B到PRESS START，320x240，无16MHz重复画面异常；截图SHA ec959b75b75dcd1a33742cdbf4eb7f2bf0d4cdc3a06d0b754ae871aec34d0bb6。已提示用户按Start，操作反馈待确认，板端保持e42/8.4672MHz。


E10操作结果及E4下一步：用户确认新APS e42/8.4672MHz画面能到标题或菜单，但Start没有反应；PA_E42_REDEMO8_AFTER_START_A与标题PNG SHA相同ec959b75...。8MHz操作验收亦未通过；目前不能区分输入映射和CPU/内存挂起。已准备独立UART诊断候选，接出Start current/sticky、完成取指访问计数、复位、PSRAM flags/stage；尚未编译/上板。


用户澄清此前“菜单”是F12设置菜单，不是游戏菜单；随后明确关闭F12后手柄Start仍无反应。撤回将该用户措辞视作游戏已响应的推论；截图到PRESS START事实独立保留。8MHz操作未通过，输入是否到核心和CPU活动仍待观测。UART1USEFPGA只读0xFFD08718=1；诊断仅独立分支。vvp首轮崩溃无RTL结论，Verilator第二轮复位fresh时延断言失败，修订获取期限后第三轮在Runner验证；原功能协议和保护复位门控不改，尚无新诊断RBF/板测。


E4 UART观测判据：先确认帧序号、校验和与分域fresh有效位；无帧不能解释为CPU挂死。Start_seen仅覆盖普通手柄P1 raw joystick_0[7]；用户本轮明确使用手柄。fresh SYS下Start_seen=0支持输入未到该核心入口；Start_seen=1只证明收到输入，不证明游戏处理。fresh RAM下ready=0、error=1、rst_sys=1支持复位门控近端原因；ready正常且CPU复位释放后才分析取指活动/Cache busy/RAMH busy。取指计数8位会循环，相同单值不能证明停机，地址三位仅是大区分类。不同域快照不是同一物理时刻，不能用瞬态不一致直接推定因果。


5e2079f/38236922070 UART两分频、停源与reset恢复、BSC256/CACHE160数字回归通过。67f3991追加每个valid字段内容检查及停源首帧全invalid断言，功能观测RTL不变；完整Runner38237273814已启动，需三门禁后才能Quartus。用户关闭F12后手柄Start仍无反应，排除仅在设置菜单内操作这一条件。原板e42/8MHz不变，没有新诊断RBF；输入到达/CPU活动与运行error仍待帧证据。


2026-10-12用户确认已拔下板卡串口，要求先记录；停止本轮上板操作。最后实测仍为e42 APS/8.4672MHz，关闭F12后手柄Start无反应；16MHz标题重复/颜色异常且Start后卡住或黑屏。原版DDR3同游戏此前由用户确认可进入并操作，不能用于证明APS通过。新UART诊断67f3991/38237273814已完整构建且RBF本地SHA核对一致，STA未签核，未传板。重新接入后先核对新boot_id/BIOS/CFG/core，再另存诊断RBF、8MHz无盘与同游戏读UART基线，关闭F12并按手柄Start后比对fresh Start_seen、CPU活动、ready/error/复位；不先改协议或再次调电阻。
三门禁及完整Quartus成功，全部4个可用逻辑处理器nproc/online=4、allowed0-3、并行4。最终40146ALM/43368FF/4189LAB（仅余2LAB），逻辑RAM4006464位不变。RBF4556904B/SHA363afeaba8c07bf36023e68440b1adb2e8ae5e0818b4dbcd2dbda286f53e4a70。整体STA仍FAIL：默认STA clk_ram setup/hold=-0.737/-0.294ns，clk_sys=-0.350/+0.051ns；诊断新增跨域观测路径须与原功能路径分开分析，不计时序优化完成。COM13在上板预检时已消失，用户确认已拔下并要求先记录；未上传/加载此诊断RBF，无UART板端帧或游戏验收结论。


67f3991新增分组STA复核：clk_ram入站setup -0.737ns为SCU.CBUS_WR[0](clk_sys)到ramh_din[6](clk_ram)，hold -0.294ns为VDP2.VRAMA_D[60]到sdram1.din[0][60]；主PLL相关功能通路，不能任意false-path。同clk_ram setup/hold -0.065/-0.254ns仍负。clk_sys入站setup -0.350ns是adapter cache_addr[9]到Saturn.OPEN_BUS[19]；四角hold最坏 -0.088ns，默认+0.051ns不是四角签核。ENGINE33同钟四角最坏 -1.259ns、ENGINE50 -6.180ns，训练reference_mr0到memory_training；新观测/模式迁移跨域须另证，不以整体FAIL仅归外部模型。另保留H8未缓存dummy读跨SCU仲裁可能漏单拍请求假设：仅静态允许前提，未跑反例/上板，不改协议。

### 2026-10-13 UART67 串口优先复测与帧率调查

本轮未新增RBF：板端为67f3991、SHA256 363afeaba8c07bf36023e68440b1adb2e8ae5e0818b4dbcd2dbda286f53e4a70；boot_id 8d07c902-5aa7-4cab-9129-b4ce75f3877a。COM13控制台与FPGA ttyS1诊断分开；每次采集核对启动ID、RBF摘要和MiSTer命令行，恢复ttyS1设置。

- 8.4672MHz首次BIOS加载：372有效帧，stage E6、init_error/adapter_error=1、ready=0，表示启动ID/模式寄存器训练签名失败；未输出实际读值，不能据此指定DQ7。相同设置重新加载后训练成功、取指计数变化，启动结果存在波动。
- Siikasaurus 8.4672MHz早期有197种取指计数；随后连续采集为CPU状态F7（REQ/ID/CACHE_BUSY置位）、计数227、ready=1、RAMH busy/read=0。用户关闭F12按Start仍无反应；原始Start_seen=1只证明输入进入FPGA，不能证明游戏已处理。
- 不按键对照也出现F7等待形态，Start_seen始终0；早期/后期计数分别0和190，不能说CPU从未再前进。后期4096字节仅202有效帧，须保留原始日志并核查串口垃圾/缺帧。撤回“Start导致卡住”的推断。
- 16.9344MHz同核、同BIOS、同游戏：训练成功；371有效帧为CPU F0、计数3、ready=1、RAMH busy/read=0。用户明确反馈启动动画明显更流畅，但画面异常（截图352×720、重复/颜色异常）；不是游戏通过。板端本轮最后停在此16MHz实验状态。
- 8位取指计数存在256次回绕别名，固定值不是永久停机证明；stage20是最近读取状态，不代表此刻持续读取。下一诊断候选增加不回绕的窗口进展位、完整CBUS/IBUS地址、CACHE/BSC/SCU等待页；不同状态页分时采样，仅地址页2～5冻结同一对地址。
- 用户视频为1280×720、约7.24秒、手机记录29fps；29fps不能当游戏帧率。图像显示BIOS动画缓慢推进；音频能量后半降低包含环境噪声，尚不能据此断言SCSP停机。视频是辅助证据，串口与日志为主要定位依据。

原始证据位于chat/work：PA_UART67_BIOS8_20261013_A/B、SIIKA8_UART_20261013_A/B/C、SIIKA8_AFTER_START_20261013_A、SIIKA8_NO_INPUT_EARLY/TITLE_20261013_A、BIOS16_20261013_A、SIIKA16_EARLY_20261013_A各uart.bin/json/log。所有现有时序FAIL保留；提高外部PSRAM频率改善主观流畅度不能代替功能、吞吐或时序验收。

### 2026-10-13 UART2 880fa28 正式上板诊断

完整构建38337782678于11:31完成：Quartus含详细STA 42分14秒，总流程53分36秒；4CPU全部启用。41112ALM/43438FF/4189LAB，仍仅余2LAB；RBF4569832B、SHA256 540a15a37dc2859a4234abb7b98e1bd6389f02ff8f923327a014506fba34dd98。四角同clk_sys +0.354/+0.080ns、同clk_ram +0.547/+0.156ns、ENGINE33同钟 +0.468/+0.113ns；入站clk_sys -0.231/-0.028ns、clk_ram -1.001/-0.051ns，整体STA仍FAIL，观察器跨CLK50链未单独签核。

用户明确授权上板。COM13预检新boot_id 8dac8acd-3b9a-4c4b-9f32-8e61025c8d50，MiSTer菜单正常、UART1 FPGA路由=1；新RBF独立上传且板端大小/SHA一致，旧核心保留。

- 8.4672MHz首次加载PA_UART2_BIOS8_20261013_A：372个连续valid7 A6帧，RAM8616、stageE6、训练错误和整机复位保持；记录FAIL，不以重试覆盖。重新加载B：371个连续valid7帧，训练成功，全部窗口有完成取指，46组地址变化，主要访问RAMH。
- 同核Siikasaurus早期PA_UART2_SIIKA8_EARLY_20261013_A：371帧，353窗口有完成取指；后续LATE与TITLE各371帧全部progress1。正常PRESS START截图B为320×240，SHA ec959b75b75dcd1a33742cdbf4eb7f2bf0d4cdc3a06d0b754ae871aec34d0bb6；截图不代替游戏功能验收。
- 再后续WAIT_INPUT与STALL_CONFIRM两次各371连续valid7帧，无序号缺口/校验错，全部progress0，Start_seen0，RAM8209（ready/init_done=1、init/adapter_error=0、RAMH busy/read=0）、stage20。page0 E4F7、page1 83F1、page6 0C13、page7 0079固定；每次46组完整同拍地址固定CBUS_A=FFFFFFFE、IBUS_A=00000002。确认这两个采样窗口内没有完成取指，排除了单靠8位计数回绕产生的假停顿；不等同于已知异常起因或永久全CPU停止。
- CACHE保持IBREQ/IBUS_WAIT/IBUS_WRITE_PEND，BSC在T0且BUS_RLS/BGR置位；SCU idle、CBUS_WAIT置位。地址不再支持“当前停在0700 RAMH”的旧推测，需检查地址回绕、未完成写/预取与总线释放组合。不同页状态分时采样，固定多轮仍不能将动态状态当同拍。

原始uart.bin/log、v2decoded.json保存在chat/work对应tag；两次固定停顿raw SHA分别2a4df126c80d67760fca8568921aba6bfbaf231f7b6e0b9291c1f81ea4c6f9f3、6ff04c14bc72709cd2cbc6c5b92e45923657f9b158e5fc21e45ff1d6bacbe540。仍未游戏PASS，未将软件异常定为DQ7硬件问题。板端保持新版8.47MHz PRESS START，已请求用户Start反馈，16MHz对照待此反馈后执行。

UART2观察语义补充：源码core.BUS_ID并不严格等于指令取指（store也可能ID=1）。本轮progress/count只表示符合REQ/ID且缓存/MULT未阻塞条件的CPU总线访问活动，不能计为指令退休或精确取指率；前述“完成取指”应按此理解。progress0与WRITE_PEND/IBUS_WAIT固定组合仍支持持续等待。83F1表明写pending，0C13表明主SH让出总线；0079表明SCU无DMA却有CPU A/B等待。副SH仲裁/外设响应链为新候选，缺少副SH与SCU A/B状态，尚未确认根因。

### 2026-10-13 用户改换 SonicZtreme Metal 对照

用户明确要求停止用Siikasaurus，改用板上已有SonicZtreme Metal。保持UART2 880fa28、同boot_id 8dac8acd-3b9a-4c4b-9f32-8e61025c8d50、同JP1.01 BIOS及8.4672MHz，仅更换S0 CUE：/media/fat/games/Saturn/SonicZtremeMetal/SONICZTREME_METAL.cue。CUE引用sl_coff.iso（2654208B）及TRACK01.WAV（31881464B），文件齐全；MiSTer实际fd分别打开镜像/音轨，MGL命令RC0。

- PA_UART2_SONIC8_EARLY_20261013_A：372连续valid7帧、357窗口有访问活动，46组冻结地址；初始化成功，未检测Start。
- PA_UART2_SONIC8_LATE_20261013_A：371连续valid7帧，全部progress1、RAM8209、BSC T0无BUS_RLS/BGR、CACHE命中且IBREQ/IBUS_WAIT/WRITE_PEND为0。地址主要06000950/954、IBUS保留06000014。截图A为正常Saturn BIOS画面，不能当游戏卡死。
- 稍后PA_UART2_SONIC8_WAIT_20261013_A：372连续valid7帧、全部progress1、46组地址，无CRC错误/序号缺口。截图B352×240已进入SonicZtreme 3D场景，SHA682009ebe3b899ab7b521596c3bd450f31d8cb9d62ba8b45f548f22bc92b5194。当前窗口未重现Siikasaurus固定写等待，不能据此认定长期稳定或流畅度/时序通过。

raw SHA early=0305268b9886d0ad113c1c1da754a693788ecd6b3c2c277db12f3ec57872d11d、late=f3545d2650bdfd3ce5c329eb03c9619d28ef8face7cc35591bce2cb37f10fd8f、wait=29adacf6dc892a238b33c92522fd4e24f8164c2562ec719ff9b958fb324dab51。证据均在chat/work对应tag。当前保持8MHz Sonic场景，已请求用户手柄移动反馈，未判交互PASS。16MHz对照尚未执行。
