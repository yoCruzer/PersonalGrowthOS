# iCloud 后续开发：正式产品 smoke 修复验证

基线 e57fe3503995771a89754fbc4077ea16627c15be；仅布局修复，测试断言未修改。

原 CI run 42379022508：head 0e1f7475434a31d695f9e175984340def448b889，测试 checkout 为 PR merge 4b0734907327981ea8f34b0db38e10a5a09083ba。Xcode 27.0 / iPhone 13 mini / iOS 27.2。5项 smoke 为3 PASS/2 FAIL，失败均为短中文标题高度42.333pt超过25pt；release/unit成功，extended跳过。原始失败不改写。

本机 macOS 27.0.1 (26A434), arm64, Xcode 27.2 (27B52), 专用 iPhone13mini / iOS27.0 (24A434), UUID 48EC06F9-5776-47BA-8436-C719A8F12238。

修复前原样英文测试1/1 PASS。本机没有CI所用27.2 runtime，因此没有声称本机复现了CI失败。原UI代码与此前已通过的布局代码相同；本机原图/AX表明月习惯8字标题自然宽135pt且仅刚好容纳，说明默认布局余量很小，具体OS内部差异未独立证明。

修复：仅HabitOverviewRow省略重复装饰图标，为名称释放36pt；ModuleEntryRow支持可选symbol，其他调用仍传原symbol。保留原生NavigationLink、任意长名换行、默认/XXXL/辅助字号、44pt计数按钮、业务周期/当日计数语义。没有缩小字体、固定标题行数或放宽测试阈值。

结果与命令见后续追加。原完整日志及xcresult位于 /private/tmp/pgos-icloud-smoke-{before,after}.*；原CI compact artifact位于 /private/tmp/pgos-smoke-original-artifact。

修复后完整 CI 同5项 smoke 本机5/5 PASS，0失败，exit0（391.817s）。包括中文默认+XXXL、英文、最大辅助字号shell、按钮44pt/名称导航/0→1→0/重启持久化。截图与AX人工核验默认短名称单行、长名完整换行、计数区域不重叠。最新原分支e57fe35 CI42383151034仍为release/unit PASS、smoke3PASS/2FAIL，原样同42.333>25；与修复前失败一致。未触发无因重复CI。当前修复仍待远端27.2独立验证。
