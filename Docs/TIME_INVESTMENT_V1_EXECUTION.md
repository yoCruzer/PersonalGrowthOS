# 时间投入 V1 执行证据

状态：IMPLEMENTING_A；不是交付或验收通过。执行日期 2026-10-16。

固定输入：BASE `ad0720ad743f495ac6f2ee3e97b16577266351db`；PLAN_ROOT `043a2673c2463cb4f2259dbd27f58dc998b62bc5`；GOAL_SHA `72ee8bdf954a5628806db867682a6b021e63545b`。两份规格全文均为1.1。

`git merge-base --is-ancestor` 已核验 BASE→PLAN_ROOT→GOAL_SHA；PLAN_ROOT父提交为BASE；`git diff --name-status BASE GOAL_SHA` 严格只有两份时间投入规格。原规划有三次文档提交，不要求最终GOAL直接父提交为BASE。

独立worktree `/Users/himini/.codex/worktrees/time-investment-v1/PersonalGrowthOS`，从GOAL_SHA建立 `codex/time-investment-v1`。远端同名分支/PR不存在；PR#11 OPEN Draft head/base核验为 `ad0720a` / `codex/important-days-v1`；新PR预定base `codex/sleep-routine-v1`，其当前head仍为BASE。原工作区三项未知dirty保留，不stash/reset/clean/吸收。旧PR快照 `/tmp/pgos-time-investment-evidence/old-pr-snapshot.json`。

## 实际状态机与事务

- running→paused/resume；running→按目标投影targetReached；unfinished→finish冻结pendingSave。
- 不同进程/单调锚点失效/壁钟异常/超过18小时的自动累计→recoveryRequired，保留此前可信检查点。
- pendingSave/targetReached/recoveryRequired→原子写Session和saved终态；discarded/deleted保留操作墓碑，旧ID不复活。
- 每参与者一个unfinished，不限制其他参与者。统计只读正式Session，区间按原时区自然日分摊、按Session ID去重。
- 写入使用同库独立ModelContext，失败只rollback本次context；计划在界面接线时补持久草稿与生命周期检查点。

## 已运行命令与真实结果

环境：macOS本机，Xcode 27.1 / 27A9275。构建均使用本任务 `/tmp/pgos-time-investment-derived`。

1. `xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/pgos-time-investment-derived CODE_SIGNING_ALLOWED=NO build`：exit65，throwing短路表达式编译错误。日志 `/tmp/pgos-time-investment-build1.log`；原错误保留。
2. 修正该表达式后，增加 `-arch arm64` 的同一Debug命令：exit0 / BUILD SUCCEEDED，日志 `/tmp/pgos-time-investment-build2.log`。此时UI尚未接线，不代表验收通过。
3. 本任务`xcrun simctl list devices available`触发Xcode包装脚本`xcodebuild -runFirstLaunch`，卡住约四分钟。仅结束本任务PID76479/76470/76469，不终止其他任务或系统服务。当前已安装CoreSimulator=1171.7.0，Xcode要求1174.9.2，构建明确报 simulator device support disabled。直接读取已安装引擎清单可见iOS27.0设备；不绕过Xcode版本检查，不安装或操作旧模块模拟器。

所有新Unit/磁盘集成/UI目前为NOT_RUN；测试编译和后续门禁另追加。原Debug构建通过不等于SwiftData运行或设备通过。没有启动真实手机或私人库，没有发布、merge、tag或Archive。

## 阶段 B 实现与第一轮独立审查（进行中）

固定核心提交 `d21f8fae8cb8c4855dc76c82061ca67936be774c` 交给真实独立只读 agent `/root/time_investment_reviewer`。其报告四项：R1改活动未同步Operation、R2时钟微漂移产生重叠、R3恢复到目标后继续仍被目标封顶、R4零秒跨日首段日期不匹配。限定修复及回归已加入，尚待下一固定提交独立复核；不能写成最终通过。

已接线：Growth/Today紧凑状态、活动改名/归档/弱重复、正/倒计时、持久确认与手工草稿、五档体验/备注、全部累计/7/30自然日筛选、历史和原时区日分摊详情、修改后共享快照刷新、中英新文案。默认参与者惰性创建，记录者有独立ID。统一包v10新增原外部导入收据保全，v1–v9不反推原来缺失的收据；新实体/收据纳入空库及发布检查。恢复后的计时转换为待复核，隔离与重开验证只对这项明确状态转换比较期望，其余字段继续完整相等。

新增测试：五种V10/11.0/11.1/V12/V13磁盘Schema直升/媒体与事实保留、运行/暂停/到目标/待保存计时真实ZIP恢复继续、预览后新计时竞态/重复恢复、发布前失败回滚、15类实际坏ZIP、三项时间投入UI及真实设置Files恢复前浏览时间投入。它们目前仅编译，不是运行证据。

- `/tmp/pgos-time-investment-testcompile1.log`、`testcompile2.log`、`testcompile3.log`、`testcompile4.log`、`testcompile5.log`：均exit0 / TEST BUILD SUCCEEDED。逐轮扩展范围，不将它们累加成测试通过数。
- `/tmp/pgos-time-investment-unit1.log`、`unit1.xcresult`：对本任务新建隔离模拟器 `540825BC-D0D4-4D71-B8DF-D73B243C3726` 的一次运行尝试exit70；Xcode因CoreSimulator版本不匹配禁用目的地，运行0项。后续不循环重试。已请Owner完成Xcode组件更新；目前未收到完成确认。真实iOS Unit/磁盘/恢复/UI及全量回归仍NOT_RUN。
- 为继续发现核心问题，建立临时macOS探针 `/tmp/pgos-time-investment-mac-probe`。原样编译生产InvestmentFoundation/InvestmentTransfer、原始CivilDay/日期编码依赖及同一InvestmentFoundationTests；仅测试容器和TransferData外壳为适配器，独立内存schema，不是iOS V14/迁移/ZIP/UI验证。源文件SHA清单在该目录SOURCE_MANIFEST.json，生成命令在 `/tmp/pgos-time-investment-evidence/make-mac-probe.py`。
- `swift test --package-path /tmp/pgos-time-investment-mac-probe`：`mac-probe1.log` 16/16、`mac-probe2.log` 20/20 PASS/exit0；它们是不同轮次，不能相加。对应当时源码在探针manifest记录；后续新修改仍需补验。
- 用审查固定d21f8fa的原生产Foundation替换探针对应文件，运行相同R1/R2反例：`mac-review-red1.log` 2测试失败、5断言/错误（1unexpected），exit1。明确复现原问题，不删断言。
- 新增94个双语键；静态逐项比较937个原键值未变，git diff --check通过。界面真实视觉/无障碍验证仍NOT_RUN。

固定a873b5f后追加限定修复R5–R7，不扩产品范围。`testcompile6.log`成功，`mac-probe3.log`21/21通过，但其运行早于a873最终两处校验；不能冒称完整a873运行。为此保存 `a873b5f-mac-source-manifest.json`，独立run `mac-probe4-a873b5f.log`和`testcompile7.log`；后续最终限定修复仍需对应新提交证据。
