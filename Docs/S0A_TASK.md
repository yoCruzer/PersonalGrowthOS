# S0A Execution Task

| Item | Value |
| --- | --- |
| Project | Personal Growth OS |
| Document | S0A_TASK.md |
| Version | v0.1 |
| Status | Execution Draft — Owner Approval Required |
| Baseline Commit | 1eed293a4860bf08ea2105bed076c3db956db642 |
| Last Updated | 2026-07-16 |

---

# Purpose and Approval Boundary

本文档把 `Docs/S0_EXECUTION_PLAN.md` 中的 S0A 规划边界转化为一份可直接执行、可独立验证并可明确停止的实施任务定义。

创建或审阅本文档不批准执行 S0A。只有 Owner 明确批准 S0A 后，执行者才可以创建实施分支并开始下述工作。S0A 验收不批准 S0B、S1 或任何后续实现。

当前规划任务只允许创建 `Docs/S0A_TASK.md`；当前不得创建产品代码、测试代码或 Xcode Project。未来只有在 S0A 获得单独执行批准后，才允许创建本文档列出的最小 App Swift 文件和最小测试文件。这些文件只属于可构建、可测试的项目骨架，不代表任何产品功能 Implementation。

如本文档与 Foundation Documents、`Docs/V1_IMPLEMENTATION_PLAN.md` 或 `Docs/S0_EXECUTION_PLAN.md` 冲突，以更高层级且已批准的规划基线为准，并停止执行、返回 Owner Review。

---

# Stage Identity

| Item | Value |
| --- | --- |
| Stage ID | S0A |
| Stage Name | Native Xcode Project Bootstrap |

---

# Goal

S0A 只负责：

- 创建原生 iOS 17+ SwiftUI Xcode 工程；
- 创建 App、Unit Test、UI Test 三个 target；
- 创建 shared `PersonalGrowthOS` Scheme；
- 创建最小静态占位 App；
- 验证工程可以在执行主机实际可用的 iPhone Simulator 上构建、测试和启动。

S0A 的交付物是一个可打开、可构建、可测试、可启动的原生工程骨架，不是产品功能、产品架构或 S0B 测试组合层。

---

# Starting State Preconditions

开始 S0A 前必须逐项确认并记录：

1. 已收到 Owner 的精确执行批准：`APPROVED TO EXECUTE S0A`；本 Execution Draft 或其他措辞本身不构成批准。
2. 实施分支必须从执行时最新且经 Owner 核验的 `main` 创建；开始前必须记录实际 `main` HEAD 作为 Starting HEAD，并确认基线 commit `1eed293a4860bf08ea2105bed076c3db956db642` 是其祖先。
3. 创建实施分支前 working tree 必须 clean。
4. Foundation Documents v0.2 必须存在：
   - `Docs/INDEX.md`
   - `Docs/VISION.md`
   - `Docs/DESIGN_PRINCIPLES.md`
   - `Docs/CORE_MODEL.md`
   - `Docs/INFORMATION_ARCHITECTURE.md`
   - `Docs/V1_SCOPE.md`
5. `Docs/V1_IMPLEMENTATION_PLAN.md` v0.3 和 `Docs/S0_EXECUTION_PLAN.md` v0.3 必须存在。
6. 仓库中不得已有 `.xcodeproj`、产品 Swift 文件、Unit Test 文件或 UI Test 文件。
7. Xcode、`xcodebuild`、`simctl` 和至少一个可用的 iPhone Simulator 必须可发现。
8. 不得依赖 Apple Developer Team、真机、网络、远程服务或账户登录完成 S0A。

建议的起始检查：

~~~sh
git branch --show-current
STARTING_HEAD=$(git rev-parse HEAD)
git merge-base --is-ancestor 1eed293a4860bf08ea2105bed076c3db956db642 "$STARTING_HEAD"
git status --short
test -f Docs/INDEX.md
test -f Docs/VISION.md
test -f Docs/DESIGN_PRINCIPLES.md
test -f Docs/CORE_MODEL.md
test -f Docs/INFORMATION_ARCHITECTURE.md
test -f Docs/V1_SCOPE.md
test -f Docs/V1_IMPLEMENTATION_PLAN.md
test -f Docs/S0_EXECUTION_PLAN.md
find . -name '*.xcodeproj' -o -name '*.swift'
xcodebuild -version
xcrun simctl list devices available
~~~

预期：HEAD 精确匹配 Owner 核验的最新 `main` Starting HEAD、该 HEAD 包含本任务基线、`git status --short` 无输出、基线文档均存在、`find` 不发现现有 `.xcodeproj` 或 Swift 文件，并且至少列出一个可用 iPhone Simulator。

任何 starting state 不符合时，立即停止并报告具体差异。不得自行清理、迁移、重命名或修复无关问题，也不得以修改本任务边界的方式继续。

---

# Implementation Branch

建议实施分支：

~~~text
feat/s0a-project-bootstrap
~~~

规则：

- 仅在 Owner 明确发出 `APPROVED TO EXECUTE S0A` 后创建；
- 从届时最新且经 Owner 核验的 `main` 创建，并记录该 commit 为 Starting HEAD；
- 不在 `main` 直接开发；
- 本规划任务不创建该分支；
- 如果分支已存在、`main` 已移动或起始 commit 不匹配，停止并返回 Owner Review，不自行 rebase、merge 或选择其他基线。

---

# Exact In Scope

S0A 的实施范围严格限定为：

| Area | Approved S0A Decision |
| --- | --- |
| Project name | `PersonalGrowthOS` |
| Native project | `PersonalGrowthOS.xcodeproj` |
| App target | `PersonalGrowthOS` |
| Unit Test target | `PersonalGrowthOSTests` |
| UI Test target | `PersonalGrowthOSUITests` |
| Shared Scheme | `PersonalGrowthOS` |
| Platform | iPhone only |
| Deployment target | iOS 17.0，三个 target 一致 |
| UI lifecycle | SwiftUI App lifecycle，使用 `@main` App 入口 |
| Storyboard | None |
| App Bundle Identifier | `com.yocruzer.PersonalGrowthOS` |
| Test Bundle Identifiers | 从 App identifier 派生 Tests 和 UITests suffix |
| Signing | Automatic Signing |
| Development Team | 不固化或持久化 `DEVELOPMENT_TEAM` |
| Build configurations | Xcode 标准 Debug / Release，且仅有这两种 |
| App source | 最小 SwiftUI App 入口和一个最小静态占位 View |
| Assets | target 构建所必要的最小 `Assets.xcassets` |
| Unit Test | 一个只证明 Unit Test target 可执行的最小 XCTest |
| UI Test | 一个只证明 App 可以启动且不发生启动崩溃的最小 XCUITest |

允许使用原生 Xcode 工程结构和完成上述配置所必需的最小 Xcode 内部元数据。所有生成内容都必须逐项检查；模板默认生成不等于自动获准保留。

---

# Expected Artifacts

允许创建的预期路径如下：

~~~text
PersonalGrowthOS.xcodeproj/project.pbxproj
PersonalGrowthOS.xcodeproj/xcshareddata/xcschemes/PersonalGrowthOS.xcscheme
PersonalGrowthOS/PersonalGrowthOSApp.swift
PersonalGrowthOS/RootPlaceholderView.swift
PersonalGrowthOS/Assets.xcassets/Contents.json
PersonalGrowthOS/Assets.xcassets/AppIcon.appiconset/Contents.json
PersonalGrowthOS/Assets.xcassets/AccentColor.colorset/Contents.json
PersonalGrowthOSTests/PersonalGrowthOSTests.swift
PersonalGrowthOSUITests/PersonalGrowthOSUITests.swift
~~~

Artifact rules:

- `Assets.xcassets` 只允许保留 Xcode 工程构建所需的最小目录结构和 metadata。
- `AppIcon.appiconset` 和 `AccentColor.colorset` 仅在原生模板或 target 构建确实需要时保留；只允许空的最小 metadata，不允许设计图像、品牌颜色或产品资产。
- 不得制作或添加正式 App Icon、品牌颜色、产品图片或任何生产视觉资产。
- Xcode 如为打开工程生成 `PersonalGrowthOS.xcodeproj/project.xcworkspace/contents.xcworkspacedata` 等必要内部元数据，可以保留，但必须说明必要性并逐项检查。
- 不得提交 `xcuserdata`、用户本地 scheme、DerivedData、Simulator 数据、构建产物或本机账户配置。
- 除上述路径及被证明为工程必需的 Xcode 内部元数据外，任何额外生成文件必须先删除或回退。若无法确认其必要性，停止并返回 Owner Review。
- 不允许通过新增 `Info.plist`、entitlements、配置文件或其他目录绕过已批准范围；如工具链强制要求新增未列出的文件，停止并报告。

---

# Explicitly Out of Scope

S0A 明确禁止创建、配置或实现：

- `AppConfiguration`；
- `AppContainer`；
- S0B 的 launch configuration seam、launch arguments 或 environment seam；
- 稳定 accessibility identifier；
- 产品导航、Tab 或 Tab bar；
- Entry、Habit、Goal、Review、Tag、Link；
- SwiftData；
- `VersionedSchema`；
- `ModelContainer`；
- Repository 或 Store abstraction；
- Media；
- Capture；
- Quick Capture；
- Timeline；
- Today；
- Library；
- Search；
- Settings；
- Export / Import；
- 产品图标、品牌视觉、正式文案、生产图片或正式颜色；
- Localization；
- Accessibility 设计扩展；
- 第三方依赖或第三方 binary；
- Swift Package、local package 或 package dependency；
- Capabilities；
- Entitlements 或 `.entitlements` 文件；
- Development Team 配置或持久化的 `DEVELOPMENT_TEAM`；
- 真机签名、provisioning profile 或 distribution signing；
- App Store Connect；
- CI workflow；
- README 修改或新增；
- 非必要架构目录、protocol、service、fixture、sample data 或 placeholder file；
- 任何 S0B、S1 或后续实现。

---

# Placeholder Definition

占位 App 必须是静态、无状态、无产品语义的 SwiftUI 内容。它只用于证明 App 能渲染并保持运行。

允许的最小显示内容示例：

~~~text
Personal Growth OS
Project Bootstrap
~~~

占位 View 不得包含：

- Quick Capture；
- Timeline；
- Today；
- Tab bar 或导航结构；
- 假数据、preview sample data 或用户记录；
- 产品交互、手势或状态变化；
- 未来功能按钮、disabled button 或功能预告；
- accessibility identifier seam；
- 正式营销文案、品牌视觉或产品级布局。

---

# Test Boundary

## Unit Test

Unit Test 只证明 `PersonalGrowthOSTests` target 可以构建和执行。允许一个使用 XCTest 的最小恒真断言，例如 `XCTAssertTrue(true)`。

Unit Test 不得测试或引入：

- `AppConfiguration`；
- `AppContainer`；
- 产品逻辑或领域语义；
- SwiftData 或持久化；
- 未来 service、repository、store、protocol 或 mock；
- fixtures、sample records 或性能测试。

## UI Test

UI Test 只证明：

- `XCUIApplication` 能启动 App；
- App 进程保持运行；
- 不发生启动崩溃。
- `PersonalGrowthOSUITests` target 可以正常执行。

UI Test 不得引入：

- S0B launch arguments 或 environment configuration；
- accessibility identifier seam；
- 产品 UI 文案或控件断言；
- navigation、Tab、数据或布局断言；
- 多步骤交互、截图测试或性能测试。

UI Test 可以检查 App 的运行状态，但不得依赖一个稳定的产品 UI selector。对占位内容的可见性确认应作为人工启动观察记录，不得借机建立 S0B 的确定性 accessibility seam。

---

# Execution Procedure

收到 Owner 明确批准后，严格按以下顺序执行：

1. 运行 Starting State Preconditions；任一失败即停止。
2. 从已核对的 `main` HEAD 创建 `feat/s0a-project-bootstrap`，记录 Branch 和 Starting HEAD。
3. 使用本机 Xcode 的原生工程结构创建 iOS SwiftUI App 工程及两个 XCTest target；不得使用 XcodeGen、Tuist、Swift Package 或第三方生成器。
4. 配置已批准的 target、scheme、iOS 17.0、iPhone-only、Bundle Identifier、Automatic Signing、Debug / Release 和 no-storyboard 决策。
5. 删除模板中不属于 Expected Artifacts 或不满足占位/test boundary 的示例内容。
6. 创建最小 App 入口、静态占位 View、最小 Unit Test 和只做启动证明的最小 UI Test。
7. 将 `PersonalGrowthOS` Scheme 设为 shared，并逐项检查工程 metadata。
8. 在实际可用的 iPhone Simulator 上执行全部 Validation Commands；任何失败均不得跳过。
9. 对照 Exit Criteria 和允许文件清单审查完整 diff。
10. 输出 Required Final Report，然后停止；不得 commit、push 或继续 S0B。

---

# Validation Commands

所有命令从仓库根目录执行。必须记录原始命令、关键输出和结果，不得只写“通过”。验证不得硬编码设备型号；先发现本机实际可用的 iPhone Simulator，再以其 UDID 作为 destination。

## 1. Toolchain and Simulator Discovery

~~~sh
xcodebuild -version
xcrun simctl list runtimes
xcrun simctl list devices available
~~~

从上述可用设备中选择一个 iPhone Simulator，记录 device name、UDID 和 runtime，然后仅为当前 shell 设置：

~~~sh
export SIMULATOR_UDID='<selected-available-iphone-simulator-udid>'
~~~

不得把 UDID 或设备型号写入 project、scheme、源码或测试文件。

## 2. Project, Targets, and Scheme Discovery

~~~sh
xcodebuild -list -project PersonalGrowthOS.xcodeproj
test -f PersonalGrowthOS.xcodeproj/xcshareddata/xcschemes/PersonalGrowthOS.xcscheme
~~~

必须确认：

- project 为 `PersonalGrowthOS`；
- targets 恰好包含 `PersonalGrowthOS`、`PersonalGrowthOSTests`、`PersonalGrowthOSUITests`；
- shared scheme 为 `PersonalGrowthOS`；
- build configurations 仅为 Debug 和 Release。

## 3. App Build

~~~sh
xcodebuild \
  -project PersonalGrowthOS.xcodeproj \
  -scheme PersonalGrowthOS \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath /tmp/PersonalGrowthOS-S0A-DerivedData \
  build
~~~

结果必须为成功，不得依赖 Development Team、真机签名、网络或账户登录。

S0A 使用 Automatic Signing，但 shared project 不得固化 `DEVELOPMENT_TEAM`。Simulator build/test 必须在没有 Apple Developer Team 时通过；不得配置 provisioning profile，也不得进行真机签名、distribution signing 或发布配置。

## 4. Unit Test

~~~sh
xcodebuild \
  -project PersonalGrowthOS.xcodeproj \
  -scheme PersonalGrowthOS \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath /tmp/PersonalGrowthOS-S0A-DerivedData \
  test \
  -only-testing:PersonalGrowthOSTests
~~~

必须确认最小 Unit Test 实际执行且通过，不得以只构建 test target 代替。

## 5. UI Test

~~~sh
xcodebuild \
  -project PersonalGrowthOS.xcodeproj \
  -scheme PersonalGrowthOS \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath /tmp/PersonalGrowthOS-S0A-DerivedData \
  test \
  -only-testing:PersonalGrowthOSUITests
~~~

必须确认最小 UI Test 实际启动 App、进程保持运行并通过；不得跳过或改成 S0B 的 identifier-based smoke test。

## 6. Simulator Launch Observation

~~~sh
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl install "$SIMULATOR_UDID" /tmp/PersonalGrowthOS-S0A-DerivedData/Build/Products/Debug-iphonesimulator/PersonalGrowthOS.app
xcrun simctl launch "$SIMULATOR_UDID" com.yocruzer.PersonalGrowthOS
~~~

人工确认静态占位 App 成功显示且无启动崩溃，并记录观察结果。不得在此步骤增加产品 UI 或 accessibility seam。

## 7. Build Settings

~~~sh
for TARGET in PersonalGrowthOS PersonalGrowthOSTests PersonalGrowthOSUITests; do
  xcodebuild \
    -project PersonalGrowthOS.xcodeproj \
    -target "$TARGET" \
    -configuration Debug \
    -showBuildSettings \
  | rg 'PRODUCT_BUNDLE_IDENTIFIER|IPHONEOS_DEPLOYMENT_TARGET|TARGETED_DEVICE_FAMILY|CODE_SIGN_STYLE|DEVELOPMENT_TEAM'
done
~~~

必须确认：

- 三个 target 的 `IPHONEOS_DEPLOYMENT_TARGET` 均为 `17.0`；
- 三个 target 的 `TARGETED_DEVICE_FAMILY` 均为 `1`，即 iPhone only；
- App 的 `PRODUCT_BUNDLE_IDENTIFIER` 为 `com.yocruzer.PersonalGrowthOS`；
- test bundle identifiers 按批准规则从 App identifier 派生；
- `CODE_SIGN_STYLE` 为 `Automatic`；
- 不存在被固化的 Development Team 值。

同时检查 shared project 未持久化 `DEVELOPMENT_TEAM`：

~~~sh
rg -n 'DEVELOPMENT_TEAM' PersonalGrowthOS.xcodeproj/project.pbxproj
~~~

预期无匹配。命令无匹配时可能返回非零状态；这代表本项检查通过，不得因此添加空的 `DEVELOPMENT_TEAM`。

## 8. Forbidden Project Configuration

~~~sh
find . -name '*.storyboard' -print
find . -name '*.entitlements' -print
rg -n 'CODE_SIGN_ENTITLEMENTS|SystemCapabilities' PersonalGrowthOS.xcodeproj
rg -n 'XCRemoteSwiftPackageReference|XCSwiftPackageProductDependency' PersonalGrowthOS.xcodeproj/project.pbxproj
~~~

以上检查均预期无输出，并据此确认：无 Storyboard、无 Capability、无 Entitlements、无 package dependency。

## 9. Forbidden Implementation Content

~~~sh
rg -n 'SwiftData|VersionedSchema|ModelContainer|AppConfiguration|AppContainer|Quick Capture|Timeline|Today|Library|Search|Settings|Export|Import' \
  PersonalGrowthOS PersonalGrowthOSTests PersonalGrowthOSUITests
~~~

预期无匹配。随后人工检查所有 Swift 文件，确认没有 Entry、Habit、Goal、Review、Tag、Link、Media、Capture、Repository、产品导航、产品交互、假数据、S0B seam 或后续实现。

## 10. Diff and Working Tree

~~~sh
git diff --check
git diff --name-status "$STARTING_HEAD"
git status --short
~~~

必须确认 `git diff --check` 通过，且 name/status 与 working tree 只包含 Expected Artifacts 及经逐项证明必要的 Xcode 内部元数据。

## Required Validation Record

最终报告必须记录：

- 实际 `xcodebuild -version` 输出；
- 实际 Simulator device name 和 UDID；
- 实际 Simulator runtime；
- 实际执行的 build/test/launch commands；
- 每个命令的成功或失败结果；
- Unit Test 和 UI Test 的 executed/passed 数量；
- 静态占位 App 的启动观察结果。

---

# Failure and Stop Rules

- 工程生成失败时立即停止并报告，不得换用第三方生成器或扩展架构。
- Xcode 自动生成超出范围的文件时，先删除或回退超出范围内容；在 diff 恢复边界前不得继续。
- 如果额外文件是当前工具链不可避免的工程 metadata，必须逐项说明；无法证明必要性时停止并返回 Owner Review。
- App build、Unit Test 或 UI Test 失败时不得跳过、忽略、禁用测试或只报告部分成功。
- 不得为了通过 build/test 引入 S0B、SwiftData、产品模型、产品服务、产品 UI、第三方依赖或额外 architecture seam。
- 不得自行更改 Bundle Identifier、deployment target、device family、target/scheme 名称或 Automatic Signing 策略。
- 不得配置或持久化 Development Team，不得转为真机验收。
- 不得添加 Capability、Entitlements、Swift Package、Storyboard 或 CI。
- 如工具链行为要求改变任何已批准决策，立即停止并返回 Owner Review；不得静默采用替代方案。
- 如 starting state、baseline 或 branch 不匹配，停止并报告，不自行修复无关问题。
- 达到 S0A Exit Criteria 并完成报告后必须停止；不得继续 S0B。
- S0A 未通过时同样必须停止并报告失败证据，不得扩大范围追求“整体完成”。

---

# Exit Criteria

只有以下条件全部满足，S0A 才可提交 Owner 验收：

- `PersonalGrowthOS.xcodeproj` 可被所记录的 Xcode 正常打开，且无 repair 或 migration prompt；
- shared `PersonalGrowthOS` Scheme 可被 `xcodebuild -list` 发现；
- 三个 target 名称精确为 `PersonalGrowthOS`、`PersonalGrowthOSTests`、`PersonalGrowthOSUITests`；
- build configurations 仅为 Debug / Release；
- iPhone Simulator build 成功；
- 最小 Unit Test 实际执行并通过；
- 最小 UI Test 实际启动 App 并通过；
- 静态占位 App 在所记录的 Simulator 上成功启动并保持运行；
- deployment target 为 iOS 17.0，device family 为 iPhone only；
- App Bundle Identifier 为 `com.yocruzer.PersonalGrowthOS`；
- 使用 SwiftUI App lifecycle，且无 Storyboard；
- 无 SwiftData、`VersionedSchema` 或 `ModelContainer`；
- 无产品模型、产品功能、产品导航、产品交互或假数据；
- 无第三方依赖或 Swift Package；
- 无 Capability 或 Entitlements；
- 使用 Automatic Signing，且无固化 Development Team；
- diff 仅包含批准的 S0A artifacts 和经逐项证明必要的 Xcode 内部元数据；
- `git diff --check` 通过；
- 完整 Required Final Report 已准备；
- S0B 仍未开始且仍需独立 Owner 批准。

满足这些条件只表示 S0A 可供 Owner Review，不构成自动接受、自动提交或继续实施的授权。

---

# Commit Policy

S0A 实施完成后：

- 不自动 commit；
- 不自动 push；
- 不合并；
- 等待 Owner Review；
- 不继续 S0B；
- 不创建任何 S0B 文件、launch arguments/environment seam、`AppConfiguration` 或 `AppContainer`；
- Proposed Commit Subject：

~~~text
build: bootstrap native ios project
~~~

---

# Required Final Report

未来 S0A 执行完成或失败停止后，必须按以下顺序报告：

1. Branch；
2. Starting HEAD；
3. Xcode version；
4. Simulator device/runtime；
5. 创建文件；
6. 修改文件；
7. Project、target、scheme 名称；
8. Bundle Identifier；
9. Deployment target；
10. Signing settings；
11. Capabilities；
12. `xcodebuild -list`；
13. App build result；
14. Unit Test result；
15. UI Test result；
16. `git diff --check`；
17. `git status --short`；
18. 是否存在 SwiftData、产品功能或 S0B 内容；
19. Proposed Commit Subject；
20. Working tree 状态。

每项必须给出实际事实或输出摘要；失败项不得省略。报告完成后等待 Owner Review。

---

# Planning Status

S0A remains unapproved.

S0B remains unapproved.

Product implementation has not started.

创建本任务文档不创建 Xcode Project、不创建 Swift 或测试文件、不创建实施分支，也不批准任何 Implementation 工作。

---

# Change History

| Version | Date | Change |
| --- | --- | --- |
| v0.1 | 2026-07-16 | Initial executable S0A task draft for Owner Review. |
