# 产品CI独立验证：99ef002

真实GitHub Actions运行[42386508033](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42386508033)完成SUCCESS。PR17 head `99ef002d68685ea0e64988257b18a20c6c374f8c`；实际PR合并checkout `8a54e2a15915b3184f5a5161cdeedeb1d0a1f2fd`，不是把head与测试checkout混写。

- Release：SUCCESS；unsigned主App、ShareExtension、ImportantDaysWidget产物存在检查通过。
- Unit：599总数，598PASS/0FAIL/1SKIP，runtimeWarnings为空。唯一SKIP为`TodoFoundationTests/testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure()`：需要隔离32MB HFS+镜像，未填满主卷，不将跳过写为通过。
- Smoke：5/5PASS、0FAIL/0SKIP、runtimeWarnings为空。Xcode27.0 (27A266a)，iPhone13mini / iOS27.2 (24B8117)。保留原25pt标题、70pt紧凑行与44pt命中区域断言，覆盖原先失败的中英文方法以及中文XXXL、shell最大辅助字号、计数与持久化。
- Optional extended UI：按workflow条件SKIPPED，不记通过。

与原0e1f747 / e57fe35两个CI中的3PASS/2FAIL对照，原短标题42.333>25失败保持在同级smoke历史证据，不改写。此次真实27.2成功验证布局修复，但不代表iCloud真实服务或Production门禁通过。

证据来自`gh run download`的`ios-unit-1`、`ios-release-1`和`ios-smoke-1`原始compact artifacts。原始测试summary/tests、os/xcode日志与bundles按字节保存；公开environment只保留SHA、工具、架构、runtime与模拟器型号，去除runner名称、临时模拟器UUID/路径及无关完整设备枚举。每个原artifact内文件SHA256在`source-files-sha256.json`，完整下载原件保留本机`/private/tmp/pgos-ci-99ef002-{unit,release,smoke}`。远端artifact id/digest见`artifacts-public.json`；没有重跑或修改远端结果。

本轮独立于前次2e68证据保存；`product-source-identity.json`核对两个候选的产品/测试/工程/扩展与产品CI完全同源，不用前轮结果冒充本轮。Unit19m49s、smoke14m9s、release3m21s；没有手动重跑。
