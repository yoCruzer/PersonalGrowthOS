#if DEBUG
import Foundation
import Darwin

public struct FaultStage: Codable {
    public let name: String
    public let device: String
    public let instruction: String
    public let expectedExit: Int?
    public let plan: ManualProbePlan
}

/// Fixed synthetic scenarios, prepared offline. A stage's PASS only means its
/// commands ran; the operator must compare paired device evidence afterwards.
public enum FaultBatch {
    public static func stages(dataset: String, runID: String) throws -> [FaultStage] {
        let dependencyPlans = try RemainingBatch.plans(dataset: dataset + "-deps", runID: runID)
        var stages: [FaultStage] = zip(["00-mac-dependency-seed", "00-phone-dependency-repair", "00-mac-dependency-fetch"], dependencyPlans).enumerated().map { index, pair in
            FaultStage(name: pair.0, device: index == 1 ? "iOS" : "macOS", instruction: "异常依赖、新图片有序测试；先Mac种入，再手机获取并修复，最后Mac核对。", expectedExit: nil, plan: pair.1)
        }
        func command(_ action: ProbeCommand.Action, _ name: String, mutation: Mutation? = nil, slot: String? = nil) -> ProbeCommand {
            var c = ProbeCommand(id: "probe-" + name, action: action, mutation: mutation); c.accountSlot = slot; return c
        }
        func m(_ name: String, parents: [String] = [], image: Bool = false) -> Mutation {
            Mutation(id: "probe-" + name, object: "probe-" + (parents.isEmpty ? name : "inflight-old"), parents: parents.map { "probe-" + $0 }, text: "SYNTHETIC fault " + name,
                     imageHash: image ? digest(DevelopmentProbe.secondPNG) : nil, imageBytes: image ? DevelopmentProbe.secondPNG.count : nil)
        }
        @discardableResult func add(_ name: String, _ device: String, _ instruction: String, _ commands: [ProbeCommand], exit: Int? = nil, zone: String? = nil) throws -> ManualProbePlan {
            let ds = zone ?? dataset
            let id = "probe-f-" + digest(Data((ds + "|" + runID + "|" + name).utf8))
            let plan = ManualProbePlan(id: id, dataset: ds, runID: runID, commands: commands)
            try plan.validate()
            stages.append(FaultStage(name: name, device: device, instruction: instruction, expectedExit: exit, plan: plan))
            return plan
        }
        func cached(_ name: String) -> ProbeCommand { command(.openCached, name, slot: "A") }
        func connected(_ name: String) -> ProbeCommand { command(.connect, name, slot: "A") }
        func recover(_ name: String, _ original: ManualProbePlan) throws -> [ProbeCommand] {
            let crashed = original.commands.last!
            var inspect = command(.inspectFaults, name + "-inspect")
            inspect.faultSource = ProbeFaultSource(commandID: crashed.id, planID: original.id, commandDigest: try digest(canonical(crashed)))
            return [cached(name + "-open"), inspect, command(.snapshot, name + "-local")]
        }
        try add("01-phone-seed", "iOS", "在线；新数据集。先核验初始快照为空。", [connected("f01-connect"), command(.snapshot,"f01-empty"), command(.save,"f01-save",mutation:m("remote-seed")), command(.sync,"f01-sync")])
        try add("02-mac-cache", "macOS", "同账户 A；只连接并缓存绑定，不获取记录。", [connected("f02-connect"), command(.snapshot,"f02-empty")])
        let fetch = try add("03-mac-fetch-crash", "macOS", "收到非空真实 CloudKit 内容并落盘后故意退出；保留原计划，勿重放。", [connected("f03-connect"),command(.crashOnFetch,"f03-crash")],exit:75)
        try add("04-mac-fetch-recover", "macOS", "新进程；先导出本地故障标记，再联网重放获取。", try recover("f04",fetch) + [connected("f04-connect"),command(.sync,"f04-sync"),command(.snapshot,"f04-final")])
        try add("05-phone-next-content", "iOS", "产生 Mac 尚未见过的下一条内容。", [connected("f05-connect"),command(.save,"f05-save",mutation:m("remote-next")),command(.sync,"f05-sync")])
        let state = try add("06-mac-state-crash", "macOS", "仅在非空获取之后的 SDK 状态已保存时退出。",[connected("f06-connect"),command(.crashOnState,"f06-crash")],exit:76)
        try add("07-mac-state-recover", "macOS", "新进程；核对故障前后检查点及内容，随后再次同步。",try recover("f07",state) + [connected("f07-connect"),command(.sync,"f07-sync")])
        for (name,action,exit) in [("08",ProbeCommand.Action.crashBeforeSave,73),("10",.crashAfterSave,74)] {
            let crash = try add(name + "-mac-transaction-crash","macOS","离线本地事务边界退出；不重放原命令。",[cached("f"+name+"-open"),command(action,"f"+name+"-crash",mutation:m("transaction-"+name))],exit:exit)
            try add((name == "08" ? "09" : "11") + "-mac-transaction-recover","macOS","新进程核对事实和待发队列；提交前记录应不存在，提交后应存在。",try recover("f"+name+"-recover",crash))
        }
        try add("12-mac-inflight","macOS","旧批次交给 SDK 后写入后继修改；若 ACK 先到，此场景失败且保留证据。",[connected("f12-connect"),command(.save,"f12-old",mutation:m("inflight-old")),command(.editDuringSend,"f12-edit",mutation:m("inflight-new",parents:["inflight-old"])),command(.sync,"f12-drain"),command(.snapshot,"f12-final")])
        let lease = try add("13-mac-asset-crash","macOS","新图片待发，SDK 持有 CKAsset 且 ACK 尚未到达时退出。",[connected("f13-connect"),command(.save,"f13-save",mutation:m("lease-image",image:true)),command(.crashWithImageLease,"f13-crash")],exit:77)
        try add("14-mac-asset-recover","macOS","新进程验证原图与待发事实仍在，重新发送。",try recover("f14",lease) + [connected("f14-connect"),command(.sync,"f14-sync"),command(.sync,"f14-drain")])
        try add("15-phone-receive","iOS","核对 Mac 后继版本、提交后记录、新原图；提交前记录应不存在。",[connected("f15-connect"),command(.sync,"f15-sync"),command(.snapshot,"f15-final"),command(.imageFaults,"f15-images")])
        try add("16-phone-offline","iOS","先由 Owner 关闭手机 WLAN 和蜂窝网络；此计划只打开缓存分区，不尝试联网。",[cached("f16-open"),command(.save,"f16-save",mutation:m("phone-offline")),command(.reopenLocal,"f16-reopen"),command(.snapshot,"f16-final")])
        try add("17-phone-reconnect","iOS","Owner 恢复手机网络后执行；不重复离线保存。",[connected("f17-connect"),command(.sync,"f17-sync"),command(.snapshot,"f17-final")])
        try add("18-mac-receive-offline","macOS","核对手机离线记录实际到达。",[connected("f18-connect"),command(.sync,"f18-sync"),command(.snapshot,"f18-final")])
        let restoreDS = dataset + "-restore"
        try add("19-phone-restore-seed","iOS","独立新数据集；准备真实远端待收内容。",[connected("f19-connect"),command(.save,"f19-save",mutation:m("restore-remote")),command(.sync,"f19-sync")],zone:restoreDS)
        try add("20-mac-restore-race","macOS","该数据集 Mac 必须为空；真实获取回调到达时隔离恢复目标并围栏旧接收器。",[connected("f20-connect"),command(.restoreIsolation,"f20-restore",mutation:m("restore-target"))],zone:restoreDS)
        try add("21-mac-account-A","macOS","仅 haha 测试用户。开始后等待账户变更；Owner 在系统设置退出 A 并登录 B，最长等待十分钟。不要切换手机账户。",[connected("f21-connect"),command(.save,"f21-save",mutation:m("account-a-pending")),command(.waitForAccountChange,"f21-wait"),command(.closePartition,"f21-close")])
        try add("22-mac-account-B","macOS","确认系统 B 已登录；B 指纹必须不同、B 数据集应为空且无 A 待发记录。",[command(.connect,"f22-connect",slot:"B"),command(.sync,"f22-fetch"),command(.snapshot,"f22-empty"),command(.closePartition,"f22-close")])
        try add("23-mac-account-A-return","macOS","Owner 在 haha 恢复 A 后执行；先检查缓存 A 待发事实仍在，再验证真实账户并发送。",[cached("f23-open"),command(.snapshot,"f23-pending"),connected("f23-connect"),command(.sync,"f23-sync"),command(.snapshot,"f23-final")])
        try add("24-phone-account-receive","iOS","核对 A 待发记录最终到达；不需要退出手机日常账户。",[connected("f24-connect"),command(.sync,"f24-sync"),command(.snapshot,"f24-final")])
        return stages
    }
    public static func write(to directory: URL, dataset: String, runID: String) throws {
        let values = try stages(dataset: dataset, runID: runID)
        guard mkdir(directory.path,0o700) == 0 else { throw LabError.blocked }
        for value in values {
            let dir = directory.appendingPathComponent(value.name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
            try canonical(value.plan).write(to: dir.appendingPathComponent("SyncLab-Probe-Plan.json"),options:.withoutOverwriting)
        }
        let phone = ManualProbeBundle(items: values.filter { $0.device == "iOS" }.map { .init(title: $0.name, plan: $0.plan) })
        let phoneBytes = try canonical(phone)
        _ = try ManualProbeBundle.decode(phoneBytes)
        try phoneBytes.write(to: directory.appendingPathComponent("SyncLab-Probe-Batch.json"), options: .withoutOverwriting)
        try canonical(values).write(to:directory.appendingPathComponent("manifest.json"),options:.withoutOverwriting)
    }
}
#endif
