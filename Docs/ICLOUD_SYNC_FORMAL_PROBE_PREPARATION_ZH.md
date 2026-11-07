# 正式 Development 批次准备器

2026-11-07。此工具是 P0 的离线工程准备，不是已经具备真实云访问能力的双端客户端。它不链接正式 App，不替换已安装 SyncLab，不打开业务数据库，不创建 CKContainer 或执行网络操作。正式 wire 仍为候选，P0/P1/P2 未通过。

## 实际用途与身份

`Packages/SyncFoundation` 内的 `FormalProbeCore` 复用 v2 codec；`FormalDevelopmentProbe` 提供三个可运行命令：生成固定合成计划、通过实际 CKRecord/CKAsset SDK 回放、只读检查待签名客户端产物。它不接受任意业务数据或图片作为计划输入。

计划固定 Team `83SKX2PM7B`、容器 `iCloud.com.yocruzer.PersonalGrowthOS`、Development、v2 schema hash。每次生成新的 run/dataset，使用内置文字和合成 PNG，包含原图、创建 payload、创建 mutation、修改 payload、修改 mutation、逻辑删除 mutation 共六条记录检查；创建→修改→删除的父链及完整字节均可核对。

独立客户端 Bundle ID 候选为 `com.yocruzer.PersonalGrowthOS.FormalSyncProbe`，明确标为 `PROPOSED_NOT_REGISTERED_OR_VERIFIED`。这不代表 Apple 资源已创建、能力已关联或 profile 可用；也不是要求替换正式 `com.yocruzer.PersonalGrowthOS`。正式 App 的门户关联核对与未来隔离客户端的签名资格分别记录。

## 本机复核命令

仅在新的物理临时目录运行。路径不得经过符号链接（macOS `/tmp` 应使用 `/private/tmp`）；每个输出目录必须尚不存在，已有目录不会覆盖。

```sh
probe_root=$(mktemp -d /private/tmp/PGOS-FormalProbe.XXXXXX)
swift build --package-path Packages/SyncFoundation --scratch-path "$probe_root/build" --product FormalDevelopmentProbe
probe_bin=$(swift build --package-path Packages/SyncFoundation --scratch-path "$probe_root/build" --show-bin-path)/FormalDevelopmentProbe
"$probe_bin" plan "$probe_root/plan"
plan_sha=$(cat "$probe_root/plan/plan.sha256")
"$probe_bin" replay "$probe_root/plan" "$plan_sha" "$probe_root/replay"
"$probe_bin" preflight "$probe_root/plan" "$plan_sha" "$probe_bin" "$probe_root/preflight"
```

最后一条用当前未配置正式能力的 SwiftPM 产物检查拒绝路径，预期退出 2，`preflight/report.json` 为 `NOT_READY`；不是构建失败，也不是正式签名成功。它可能有本地 ad-hoc 签名，仍缺正式 Team/能力/profile。真实候选检查时替换为已经另行准备的独立 `.app` 或可执行文件；本轮没有签名、安装或启动该客户端。

## 报告与失败语义

回放必须逐字节核对计划与内置 fixture 的重建结果，并绑定外部传入的计划 SHA256；修改环境、容器、schema、记录顺序、文件内容、缺文件或多文件都不因重算 hash 而被接受。所有业务内容都是合成数据。报告注明 `OFFLINE_ONLY`、零网络操作、`p0Passed=false`；失败保留已完成命令及失败阶段，不改写原计划或旧输出。

目录使用文件描述符相对访问；SDK 必须使用文件 URL 的边界另核对目录绑定。调用者仍须持有不可变计划和输出 lease，不能把检查当成任意恶意并发替换的绝对保证。后续真实网络发送必须另行实现持久 lease 与身份隔离，不能直接把这些临时输出当成已上传或已 ACK。

preflight 只调用实际 `codesign` 和本地 profile 解码，公开报告仅保存必要的受限字段、摘要及拒绝码，不保存原始 profile、设备列表、证书或账号资料。即使静态字段一致，也只会得到 `STATIC_SIGNING_MATCH_REQUIRES_OWNER_GATE`，`readyForCloudRun=false`、证书/profile/设备资格仍待实际核验，不能据此启动云操作。注入的签名元数据正例只属于单元测试。

## 后续依赖

Owner 已选择稍后按[集中只读清单](ICLOUD_SYNC_NEXT_READINESS_ZH.md)补齐正式 App 关联及两环境 schema，预计 5–10 分钟，手机前台及数据线均 0 分钟。本工具不增加当下的人工动作。

取得导出后先比对固定候选，再准备必要的正式 Development 变化、独立客户端签名和真实发送/读回适配器。真实 Development 覆盖完成前不冻结 P0；Production schema 部署、Production 写入和发布仍须分别基于具体可评审内容授权。不把离线六条 SDK 检查称为真实双向、账户隔离、崩溃恢复或完整 G1 故障矩阵通过。
