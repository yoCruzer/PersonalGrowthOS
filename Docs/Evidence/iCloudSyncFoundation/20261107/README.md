# iCloud 后续准备：证据索引

基线G1 `e57fe3503995771a89754fbc4077ea16627c15be`；正式产品基线 `96f72339a1a3082c43018e06d6115dd93df1df97`。分支 `codex/icloud-sync-foundation` / Draft PR #17。仅合成数据，本机macOS27.0.1 arm64、Xcode27.2(27B52)。旧G1收口和CK_2例外保持，不用这里的离线结果替代真实服务矩阵。

## 初版候选（历史版本，不作为最终P0冻结）

提交 `2e68ab2`：18项原生测试PASS、iOS17 Simulator target编译PASS、8项独立边界测试PASS、schema独立重复生成/已有目录防覆盖PASS。实际命令见native-final.log、ios17-compile.log、review/README.md与源码摘要。早期两轮cache权限失败和一轮测试负例SDK exception保留（native-attempt1/2/3），不得改成PASS。schema hash `a22407cceb196508c4b199a3f0cc4759d542dc02ee9945e25020a14e4c2f0083` 是初版实际codec产物。

随后检查真实领域极值发现16MiB单payload不能覆盖常规合法万行Unicode净资产快照；因此继续开发分块候选。初版18项/独立8项/远端成功不能算新分块版本通过。当前新版本以后续独立目录、源码hash及实际结果为准。

## V16/v12固定输入

`baseline-v16/`是从精确产品归档生成的合成SQLite+WAL、原图、真实v12ZIP和逐字段期望值；`baseline-v16-sha256.json`绑定6份最终文件。不可直接打开冻结SQLite；复制完整Store（含WAL）到新临时目录再打开。不忽略WAL，不把新版本生成库当作旧版本输入。

`baseline-provenance.json`记录所有产品/工程/共享文件与96f源码逐字节相同，仅原测试文件追加生成器。生成器为 `Scripts/Fixtures/CreateSyncV16BaselineFixture.swift`；原始命令和日志见baseline-attempt1/2/3.log.gz，最终专用iPhone16/iOS27.0模拟器1/1 PASS。第一次错误地把v12收据排除（产品实际正确保留），第二次缺CryptoKit import编译失败，第三次修正后通过；原目录保留，未覆盖。

覆盖包括Entry原图/关系、Habit/Log/计划、Goal/事件、体重/回顾/附属、Todo系列、重要日子、睡眠、时间投入、净资产资产/负债正式历史与未完成草稿；两份分享receipt包括已删除来源的receipt，磁盘/ZIP均逐ID保留。净值独立预期1211111整数分。不是39实体全部可选组合；V16→新同步schema迁移尚未实现。

独立审查 `review/verify_baseline.py`、`baseline-verification.json`检查完整ZIP字段（显式Date epoch转换）、manifest hash/CRC/计数、原图、receipt、金额、SQLite16.0.0 metadata及拷贝上的integrity_check；冻结目录前后hash相同。

## 正式产品smoke

`smoke/`保留原0e1f747与e57fe35远端失败、环境、本机修复前1/1与修复后5/5，以及合成UI截图/AX。原CI在iPhone13mini/iOS27.2的中文/英文标题42.333>25；本机iOS27.0修复前英文已PASS，不能假称本机复现。修复省略习惯行重复装饰图标以增加36pt标题空间，未改字体/测试阈值/业务逻辑；两文件独立静态审查无must-fix。最终远端27.2结果另外记录，不靠本机成功覆盖原CI。

## 外部门禁

`portal-observation.json`是本轮既有会话只读观察，正式Development仅Users；未查询记录、未修改能力、未导出schema、未查看Production。Owner选择稍后按清单导出；无需手机/数据线。清单见 `Docs/ICLOUD_SYNC_NEXT_READINESS_ZH.md`。P0未冻结、P1–P4未通过，未执行Production写入/部署、合并、Archive或TestFlight。

## 最终分块候选本机闭合

v2核心为PGMutationV2、PGPayloadChunkV2、PGOriginalV2，实际codec schema hash `6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003`。最终本机原生24/24、独立12/12、iOS17 Simulator target编译通过；[v2记录](v2/README.md)与[独立终审](review-v2/README.md)为权威，最终源hash分别在v2/post-pool及review-v2，主代理再次复算一致。

真实产品49,190,297字节payload拆成11×4,194,304+3,052,953，共12块；1584字节manifest，逐块实际SDK编码/解码、流式完整SHA和独立逐字节重组均通过，原件不变。再生成合成fixture会有新的UUID/编码字节顺序，必须从该次report读取其预期hash，不硬套本次hash。

独立复核先用6PASS/2FAIL揭示源截短/增长错误成功，强制expected descriptor及源检查关闭；再揭示Foundation临时对象累积。相同128MiB prepare由170,606,592字节RSS降至40,058,880；4MiB对照44,236,800。49MB完整SDK/CLI另测116,523,008RSS（包含SDK/CLI开销），不是4MiB总内存承诺。前轮源快照、FAIL和高内存原始测量全部保留。

11项自包含独立chunk回归接入定向CI；第12项依赖本机实际V16大输入，保留独立本机证据，不在远端空环境跳过后冒称通过。正式产品UI源码在2e68ab2之后没有变化，未手动重跑原失败CI。
