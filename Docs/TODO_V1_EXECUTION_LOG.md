# Todo V1 执行记录

## S0 基线

2026-10-09：完整读取 Goal Pack Rev2 五文件，按 AGENTS 顺序读取 Foundation/Contract/Current；git status 起始干净 main/dd09975。实际 git fetch 成功；PR 栈 #1–#7 均 OPEN Draft。annotated tag 与 origin/codex/external-capture-v1 均 c5a3c0ac859efc3ffa4e5d9f77909ec43565c871。创建 codex/todo-v1-personal-actions，未改旧 PR/标签/编号/签名。Owner 当前安装 Build 12 的事实与仓库 App 1.0(7) 分开。

## S1 定向门禁

环境 Xcode 27.0 (27A266a)，iPhone 18 Pro Simulator iOS 27.0，UDID FD666264-A2DF-445C-A77D-534B9E8ED595。所有证据在 `/tmp/pgos-todo-evidence/`。

命令公共参数：`xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO`；每次独立 resultBundlePath，对应日志同名。

- domain-1 / domain-2：exit 65，分别是新 SwiftData 谓词捕获/throwing while 与新测试缺少 try 的编译错误；没有执行测试，未声称通过。
- domain-3：exit 0，7/7 PASS，0 FAIL/SKIP。无日期、多行中文、真实时钟回拨、状态/统计、计划与硬截止、时区、固定四种重复、短月/闰年、DST、幂等撤销/跳过/停止、来源/清单删除、保存失败回滚、重启。
- 精确源码归档 fixture：baseline-fixture 初次 exit 65（生成测试使用错误 StoredMediaFile 字段和私有 snapshot）；修正仅生成测试后 baseline-fixture-2 exit 0，生成真实 V10 sqlite、原始图片与 v6 备份。源码来源与复现方法见 Scripts/Fixtures/README.md；不修改历史 fixture，不接触私人数据。
- domain-migration-1：exit 0，11/11 PASS，0 FAIL/SKIP。9 Todo 测试加原 exact-V7/exact-V8 测试；真实 V10 两次打开、完整旧数据逐字段 equality、图片字节、receipt 及迁移后新增/来源/reopen 验证。TodoIntegrity 拒绝未知状态、错误最终事件、悬挂事件。

## 构建溯源（提前接入）

官方依据：[CI 环境变量](https://developer.apple.com/documentation/xcode/environment-variable-reference)、[自定义构建脚本](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)。App target 的 Generate Build Provenance 阶段位于 Sources/Resources 之前，每次执行，输出 DERIVED_FILE_DIR/BuildProvenance.plist，正常资源拷贝进入最终 App 后由 Bundle 读取，签名后不写 bundle。CI_COMMIT 完整 40 位优先；若存在但格式无效或与可核对 HEAD 不符，构建失败。真实 CI_TAG 可选、受长度/字符校验；本地读取对应 SRCROOT HEAD + dirty，无 Git 未知。Version/Build 仍取 Bundle 原字段。

- `python3 Scripts/verify-build-provenance.py` exit 0：实际脚本的合成 clean/dirty、CI tag/非 tag、无 Git、非法/过期 SHA、不安全 tag 全部通过。
- provenance-1：exit 0，2/2 PASS，0 FAIL/SKIP；实际 Debug App 包资源存在、完整 SHA/短 SHA/组合复制行为通过。产物 `/tmp/pgos-todo-derived/Build/Products/Debug-iphonesimulator/PersonalGrowthOS.app/BuildProvenance.plist` 此次 Commit=c5a3c0ac859efc3ffa4e5d9f77909ec43565c871，Source=localGit，Dirty=true（当时尚未提交新源码），Tag 空；不是硬编码输出。
- Release、模拟 CI 编译产物、实际 About UI/粘贴、双语大字体深色等仍待候选验证，不能用 helper/脚本测试替代。

## 待完成

S2 Todo Hub/快捷连续输入/详情/来源回溯/搜索/统计；S3 通知生命周期；S4 备份 v7、完整兼容/非法包/恢复边界、集中回归、Debug/Release 与 UI；S5 普通 push 与新 Draft PR。未达到 READY_FOR_INDEPENDENT_REVIEW，Goal 保持进行中。Owner 私人库覆盖、真机通知实际触达、实际 Cloud/TestFlight 由 Owner 门禁保留。
