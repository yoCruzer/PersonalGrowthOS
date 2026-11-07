# 产品CI独立验证：2e68ab2

真实GitHub Actions运行[42384595846](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42384595846)完成SUCCESS。PR17 head `2e68ab27122867d3d55be2c1be4a203cd43675f0`；实际PR合并checkout `949c18a30398bdbb515652dd75d185d941502191`，不是把head与测试checkout混写。

- Release：SUCCESS；unsigned主App、ShareExtension、ImportantDaysWidget产物存在检查通过。
- Unit：599总数，598PASS/0FAIL/1SKIP，runtimeWarnings为空。唯一SKIP为`TodoFoundationTests/testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure()`：需要隔离32MB HFS+镜像，未填满主卷，不将跳过写为通过。
- Smoke：5/5PASS、0FAIL/0SKIP、runtimeWarnings为空。Xcode27.0 (27A266a)，iPhone13mini / iOS27.2 (24B8117)。保留原25pt标题、70pt紧凑行与44pt命中区域断言，覆盖原先失败的中英文方法以及中文XXXL、shell最大辅助字号、计数与持久化。
- Optional extended UI：按workflow条件SKIPPED，不记通过。

与原0e1f747 / e57fe35两个CI中的3PASS/2FAIL对照，原短标题42.333>25失败保持在同级smoke历史证据，不改写。此次真实27.2成功验证布局修复，但不代表iCloud真实服务或Production门禁通过。

证据来自`gh run download`的`ios-unit-1`、`ios-release-1`和`ios-smoke-1`原始compact artifacts。原始测试summary/tests、os/xcode日志与bundles按字节保存；公开environment只保留SHA、工具、架构、runtime与模拟器型号，去除runner名称、临时模拟器UUID/路径及无关完整设备枚举。每个原artifact内文件SHA256在`source-files-sha256.json`，完整下载原件保留本机`/private/tmp/pgos-ci-2e68ab2-{unit,release,smoke}`。远端artifact id/digest见`artifacts-public.json`；没有重跑或修改远端结果。
