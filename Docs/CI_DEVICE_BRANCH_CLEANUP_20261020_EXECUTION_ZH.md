# 计数器补修、GitHub Actions 与分支清点实际执行（2026-10-20）

状态：**LOCAL_VALIDATION_COMPLETE / WAITING_DIRECT_PUSH_AUTHORIZATION**。整体目标尚未完成；没有真实 Actions run，不能恢复 READY_FOR_OWNER_DEVICE_GATE。Owner 最新授权取代旧 G2/清理阶段：本轮只做计数器 P2、真实 CI 和分支只读清点，不执行真机或删除门。

## 固定身份与实际边界

- 实时只读 PR #13：OPEN Draft，head `codex/usage-remediation-20261017`，远端 `50f726391f4f548647694368ad6378a901667189`；base `codex/time-investment-v1` / `5a70f0110b151f8a45ac7c33d3f443823b1cff24` 不变。
- 原任务 worktree `/private/tmp/PersonalGrowthOS-usage-remediation-20261017` 从干净 c7f5a38 安全 fast-forward 到 50f7263；已审产品/测试 537a6f9 及交付 50f7263 全部保留。刷新前 refs/worktrees 已保存，fetch 明确 `--no-prune`。主目录三项未知改动与其他 worktree 原样保留。
- 最后产品实现 `e5b486a8c3f5746a09fc5afb5650944e55be0743`；最后产品/测试 `d84bd5f1529214b57e503cd89904c011302a0154`（后续只修测试定位和独立按下采集窗口）。CI 实现 `13f0409adccc0e0216461ec9ff00a3a11f90e67c`，按需 UI 增量 `30b7a9b384d64922fdaf42fa4a33d5f13edcec73`。清点初交 220090d、独立审查补修 `b9ac72507be54f4b4bd15c7ca8b6947742bab2e2`。均为本地普通提交，尚未推送。

## 计数器 P2 与生产原图

旧两张 sRGB 原图复算蓝色 `#0088FF` / 灰底 `#D1D1D1` = **2.305181:1**，确认启用非文本图标缺陷；零次禁用减号不计入3:1门。现在只对两个按钮使用独立 ButtonStyle，读取 isEnabled / colorScheme / isPressed，不给整组套 primary；数字仍用 primary。浅/深底色分别 `#E6ECF2` / `#283744`，常态启用前景 `#174F78` / `#D5EAFE`，按下 `#103B5D` / 白；禁用另用低强调灰色。44×45pt实际目标、ScaledMetric 胶囊、完整名称、紧凑布局及所有业务统计/持久化未改。

[31张原始PNG及来源/hash](Evidence/CounterContrast20261020/manifest.json)、[20个实际像素样本与坐标](Evidence/CounterContrast20261020/samples.json)、[复算结果](Evidence/CounterContrast20261020/contrast-results.json)、[复算脚本](Evidence/CounterContrast20261020/measure_contrast.py)。原图直接按字节复制，无裁剪/改色。常态来自 XCUIApplication.screenshot；按下来自真实按钮按住期间的 simctl framebuffer PNG，不使用重绘宿主或有损录像帧。所有测量图保有sRGB元数据，取glyph实心区及实际胶囊底色，不使用抗锯齿边缘冒称最差实心值。

| 实测状态 | 普通/最大辅助字号中最低对比度 |
|---|---:|
| 浅色启用 | 7.273152:1 |
| 深色启用 | 9.899899:1 |
| 浅色按下加/减号 | 9.771907:1 |
| 深色按下加/减号 | 12.208099:1 |

松开后的过渡色也在真实截图中测量，均留有余量。禁用状态用真实0→1→0与原图分别核对，没有用isHittable或AX语义审计代替颜色测量。

Today 日计数、Today 周/月共享 Overview、Growth 周/月与长名、详情均实际0→1→0；截图及AX保存昨日合成事实2条与当前日0/1的独立呈现，Growth同时断言周期2/3→3/3→2/3、2/10→3/10→2/10（周期边界动态取真实期望）。名称导航不增加计数；普通短名紧凑断言、最大AX完整名称与>=44pt目标继续通过。普通字号、XXXL与最大辅助字号分别留证，XXXL没有代替最大辅助字号。

设置页 [真实App系统材质原图](Evidence/CounterContrast20261020/real-App-settings-material.png) 显示黑色加号及完整圆形系统材质，系统状态栏也存在。与旧 real-reminder-retry.png 的 layer.render 宿主图对照，独立reviewer支持排除取图差异，无设置产品改动。

## 本机实际验证与保留失败

环境：macOS27.0.1 arm64、Xcode27.1(27A9275)、SDK27.1、专用 iPhone13mini / iOS27.0(24A434)。真实 appearance 通过 simctl 设置并以原图核实；本机 UDID 仅在本机台账，未硬编码到 Actions。所有产物在工作树外 `/private/tmp/pgos-ci-contrast-20261020` 与原UI证据根；全部合成数据。

完整命令、来源SHA、开始/结束时间、exit与源文件摘要见 [runs.json](Evidence/CounterContrast20261020/runs.json)，数量直接取xcresult summary：

| 轮次 | 结果 | 边界 |
|---|---|---|
| contrast-build / e5b486a | PASS | 真实App/测试构建 |
| contrast-ui-light | 2PASS / 2FAIL / 0SKIP | 新Today周/月测试定位误用daily前缀；原计数持久化与设置真实截图分别PASS。保留整轮exit65 |
| contrast-build2 / 5fa5560 | PASS | 只改Today周/月测试定位为共享Overview前缀，无减断言 |
| contrast-ui-light2 / 5fa5560 | 2/2PASS | 普通+XXXL、最大AX浅色，生产共享消费者与导航、尺寸/密度 |
| contrast-ui-dark（实际复用5fa build2） | 2/2PASS | 真深色普通+最大AX，同上 |
| contrast-build-final / b9ac725 | PASS | 加入窄按下采集方法 |
| contrast-press-dark / light | 各1/1PASS | 1秒按住行为通过；抓帧串行速度不足，部分原图抓到主屏，未计入按下色通过 |
| contrast-unit-final / b9ac725 | 99PASS / 0FAIL / 0SKIP | 完整HabitFoundationTests + AppCompositionTests，相邻业务与本地化；不是完整Unit |
| contrast-build-press2 / d84bd5f | PASS | 仅证据方法按住1秒→2秒，采集每次3张→1张 |
| contrast-press2-dark / light / d84bd5f | 各1/1PASS | 8张加减号按住原始PNG；两种字号、两种外观 |
| contrast-release / d84bd5f | PASS | generic iOS unsigned Release；构建时仅新增Docs证据未跟踪，不能称整树clean |

原首轮 light 和 dark 的 `sourceUnchanged=false` 如实保留：前者运行中修测试定位，原失败不重标；后者运行中仅新增窄按下证据方法，实际 test-without-building 仍使用5fa构建，矩阵方法/生产实现未改。最终d84只把新窄方法按住延长，产品实现、所有已通过矩阵方法、99项Unit及旧持久化/设置方法均未改；按具体定义/方法范围复用，不宣称整个测试文件相同。源码摘要与Git blob可复算。后续清洁Release核对单列实际结果。

## GitHub Actions：配置已实现，真实远端 NOT_RUN

已查当前分支与 origin/main 的 `.github/workflows` 均无配置；只读 API workflows total_count=0，避免重复。新增 `.github/workflows/ios-regression.yml` + `Scripts/ci/run_ios.py`，YAML Ruby解析、Python编译检查通过；本机原生构建/99 Unit/定向UI可执行，不能替代新CI验收。

官方依据：[当前标准runner清单](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[xcode-27镜像具体工具链/runtime](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)、[10月15日GA公告](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/)。当前清单的标准 xcode-27 arm64 用于公开仓库，未选large/xlarge或私人self-hosted；默认 Xcode27.0(27A266a) `/Applications/Xcode_27.app` / iOS27.0可用。真实run仍须以实际环境输出为准。

- 三个必选独立VM job：App/Share/Widget generic unsigned Release、整个托管 iOS Unit target、5个稳定关键UI方法（启动、五Tab/设置最大字号、中文普通/XXXL布局、英文本地化、计数持久化）。模拟器在每个测试VM动态创建，列出Xcode/SDK/runtime与实际device；同job原生测试串行。构建job实际断言3个bundle存在且无签名。
- PR事件不限制base，当前堆叠base与Draft均覆盖；只对main额外push，避免当前分支同次push+PR双跑。未设pull_request_target，只有contents:read，不获取发布/签名凭据，checkout不保留凭据。
- checkout v7.0.1 固定 `3d3c42e5aac5ba805825da76410c181273ba90b1`，upload-artifact v7.0.2 固定 `cf430e030ddbb5b0abf93d22962f4752f3646cd9`，均已核官方发布与tag。timeout35分钟、按PR/ref concurrency，矩阵失败不连带取消其他lane；没有continue-on-error或新增SKIP。
- 每job products/DerivedData/xcresult在RUNNER_TEMP；保留精简环境、日志与真实test summary/tests，always上传便于失败诊断，3天后过期，无全量大产物/缓存堆积。只用公开合成夹具。
- 较复杂Sleep/Investment/ImportantDays UI在独立workflow_dispatch可选job，默认none，NOT_RUN。工作流尚未进入默认分支，dispatch UI/API可能受默认分支注册限制；首次验收必须靠本轮正常推送产生PR事件，不为此合入main或改base。未添加schedule。
- 既有物理低空间HFS+环境限定SKIP由原测试自身报告，未来完整远端Unit单列；本机本轮99项无SKIP。不得把这些99项冒充完整远端Unit。

**当前无workflow/run/job URL、runner实跑环境或远端通过数量**：首次普通推送被自动审批审查两次拒绝，理由均为当前可信用户消息未直接授权向具体仓库发送代码/CI/测试内容，可能存在代码外传风险。第二次已附目标指令与origin核对依据仍拒绝，没有改用旁路。已向用户发直接确认：目的地 `git@github.com:yoCruzer/PersonalGrowthOS.git`、分支 `codex/usage-remediation-20261017`、产品/公开合成测试/CI/清点文档。等待其回复后才可普通推送；确认到达后继续跟踪真实run/日志并闭环失败。

验收记录必须分别填写 PR head SHA、checkout/merge SHA、run/job URLs、runner/image/Xcode/SDK/runtime、各job PASS/FAIL/SKIP。PR事件默认checkout merge ref，不能冒称head构建。当前这些字段为NOT_RUN，未以本机PASS或YAML代替。

Xcode Cloud `testflight-`→发布链、项目身份/版本/schema/数据模型/签名与branch protection均未改；未打tag、Archive、发布、merge或进行设备验收。

## 分支只读清点与独立补修

[中文清单](CI_DEVICE_BRANCH_CLEANUP_20261020_BRANCH_INVENTORY_ZH.md) / [全部机器事实](Evidence/CI20261020/branch-inventory.json)：29远端、8本地、30并集、13开放Draft；11叠加基底、3必须保留、13合并后候选、3疑似重复、主分类含未同步/独有工作0、信息不足0。主分类之外保留Todo脏状态与失效worktree UNKNOWN，不能因0忽略未知工作。每条有完整SHA/时间、upstream/ahead/behind、未推送与两种tip独有ID、三参考比较、后继PR、tag/Docs引用及未来前置条件/顺序。

独立reviewer先指出三项确认缺口：status错误误记clean、UI分支upstream文案矛盾、同SHA其他引用未参与独有覆盖。已修复且其独立重算全部30分支列表一致。important-days遗留worktree status exit128 → status:null/UNKNOWN，不清理；detached quiet-wins-review-fix完整SHA保留。两条plan各有非祖先历史提交，git cherry为+，5/5改动文件均与候选字节相同，仍为疑似重复并保留ref。#1单独指main且开放；#2至#13完整叠加链不能越过依赖删基底。

清点报告完成即交付，无“等待删除批准所以本任务未完成”的依赖；本轮不执行任何分支删除或worktree清理。

## 停点与尚未通过门

当前继续条件只是真实推送授权；随后必须完成实际Actions验收与最终独立审查，再恢复READY_FOR_OWNER_DEVICE_GATE。未参与实现的独立reviewer已核配置/分类/原图与20样本，但CI真实run当前不存在，整体目标保持active。

真机D1–D4、真实VoiceOver/系统相机权限弹窗、AlarmKit正向、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、O-01非阻断UNCONFIRMED等既有状态保留。本轮不执行旧G2或代Owner通过设备门。
