import SwiftUI
import CloudKit
import Darwin

@main struct SyncLabApp: App {
    var body: some Scene { WindowGroup { LabScreen() } }
}
@MainActor final class LabViewModel: ObservableObject {
    @Published var status = "离线实验；尚未连接 CloudKit"
    @Published var text = "SYNTHETIC G1"
    @Published var dataset = ProcessInfo.processInfo.environment["SYNCLAB_DATASET"] ?? "synthetic-g1-001"
    @Published var summary = ""
    @Published var snapshotURL: URL?
    @Published var manualProbeRunning = false
    @Published var manualProbeResultURL: URL?
    #if DEBUG
    @Published var importedBundle: ManualProbeBundle?
    @Published var selectedPlanID = ""
    func loadBundle() {
        guard !manualProbeRunning else { return }
        do {
            let bundle = try ManualProbeBundle.read(documents: .documentsDirectory)
            importedBundle = bundle; selectedPlanID = bundle.items[0].plan.id
            status = "批次已读取；请选择当前步骤，再点击启动。尚未连接云端。"
        } catch {
            importedBundle = nil; selectedPlanID = ""
            status = "批次未载入；原有测试结果保留。"
        }
    }
    #endif
    var store: LabStore?
    var driver: CloudDriver?
    var probeStarted = false
    let base = URL.applicationSupportDirectory.appendingPathComponent("PersonalGrowthOS-SyncLab", isDirectory: true)
    // Synthetic 1x1 PNG. No photo library or product files are accessed.
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
    func openOffline() {
        do {
            guard store == nil else { return }
            store = try LabStore(base: base, binding: Binding(accountHash: digest(Data("OFFLINE-UNBOUND".utf8)), dataset: dataset))
            try refresh()
        } catch { status = "本地打开失败；未清库" }
    }
    func refresh() throws {
        guard let store else { return }
        let p = try store.projections()["entry"]
        summary = "状态：\(p?.state ?? "absent")\n候选：\(p?.candidates.joined(separator: ",") ?? "")\n完整：\(p?.complete ?? true)\n待发送：\(try store.pending().count)\n预览：\(p?.preview?.text ?? "—")"
    }
    func save(deleted: Bool = false, resolve: Bool = false) {
        do {
            guard let store else { return }
            let graph = try Graph(store.envelopes().flatMap(\.mutations))
            guard let heads = graph.heads("entry"), resolve || heads.count <= 1 else { status = "有冲突，请使用显式解决"; return }
            try store.save(Mutation(object: "entry", parents: heads.map(\.id), text: deleted ? "" : text, deleted: deleted, imageHash: deleted ? nil : digest(png), imageBytes: deleted ? nil : png.count), image: deleted ? nil : png)
            try refresh(); status = "本地已保存；不代表云端已收到"
        } catch { status = "保存失败；保留已有事实" }
    }
    func reopenLocally() async {
        guard let binding = store?.binding else { return }
        await driver?.stop(); driver = nil
        do { store = try LabStore(base: base, binding: binding); try refresh(); status = "已重开本地分区；云连接需重新核验账户" }
        catch { status = "重开失败；原文件保留" }
    }
    func export() {
        do {
            guard let store else { return }
            let url = store.root.appendingPathComponent("synthetic-export-" + UUID().uuidString + ".json")
            try store.exportSnapshot().write(to: url, options: .atomic); snapshotURL = url
            status = "完整原图已校验；请选择外部保存位置"
        } catch { status = "导出失败或缺原图；不得称为完整备份" }
    }
    func connect() async {
        do {
            guard ProcessInfo.processInfo.environment["SYNCLAB_ENABLE_DEVELOPMENT"] == "YES" else { throw LabError.blocked }
            guard driver == nil else { return }
            let container = CKContainer(identifier: Binding.container)
            guard try await container.accountStatus() == .available else { throw LabError.blocked }
            let account = try await container.userRecordID()
            let binding = try Binding(accountHash: digest(Data(account.recordName.utf8)), dataset: dataset)
            // Do not move unbound/offline facts into a newly discovered account.
            store?.fence()
            let partition = try LabStore(base: base, binding: binding)
            store = partition
            let new = CloudDriver(store: partition); driver = new
            try await new.start(); try refresh(); status = "已打开当前账户独立实验分区；离线分区原样保留"
        } catch { status = "连接未就绪；检查签名、测试账户及运行门禁" }
    }
    func sync() async {
        do { guard let driver else { throw LabError.blocked }; try await driver.sync(); try refresh(); status = driver.events.suffix(8).joined(separator: "\n") }
        catch { status = "同步未完成；保留队列，禁止据此声称双端一致" }
    }
    func runProbeIfRequested() async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard !probeStarted, env["SYNCLAB_PROBE_RUN"] != nil else { return }
        probeStarted = true
        do {
            guard let run = env["SYNCLAB_PROBE_RUN"] else { throw LabError.blocked }
            let probe = try DevelopmentProbe(base: base, dataset: dataset, runID: run)
            do {
            if env["SYNCLAB_PROBE_IMPORTED_PLAN"] == "YES" {
                let bytes = try ManualProbePlan.readImportedPlan(documents: .documentsDirectory)
                let execution = try await probe.runManualPlan(bytes, documents: .documentsDirectory)
                status = execution.report.completedAllCommands ? "测试计划完成，原始结果已导出" : "测试计划停止，原始结果保留"
                #if os(macOS)
                // Only the explicitly enabled synthetic launcher exits automatically.
                Darwin.exit(execution.report.completedAllCommands ? 0 : 42)
                #endif
            } else if let command = env["SYNCLAB_PROBE_COMMAND"] {
                let result = try await probe.runOnce(command)
                status = result.id + ": " + result.status + " " + (result.errorCode ?? "")
            } else if let address = env["SYNCLAB_PROBE_BRIDGE"], let token = env["SYNCLAB_PROBE_TOKEN"] {
                status = "受限合成测试入口已启动；仅接受本机测试指令"
                try await probe.runBridge(address, token: token) { self.status = $0 }
            } else { throw LabError.blocked }
            } catch {
                await probe.shutdown(); throw error
            }
            await probe.shutdown()
        } catch { status = "合成测试入口停止；原数据保留" }
        #endif
    }
    #if DEBUG
    func runImportedManualPlan() async {
        let environment = ProcessInfo.processInfo.environment
        guard !manualProbeRunning, environment["SYNCLAB_PROBE_RUN"] == nil,
              environment["SYNCLAB_ENABLE_DEVELOPMENT"] != "YES", driver == nil else { return }
        manualProbeRunning = true; probeStarted = true; manualProbeResultURL = nil; snapshotURL = nil
        defer { manualProbeRunning = false }
        do {
            let documents = URL.documentsDirectory
            let bytes = try importedBundle.map { try $0.bytes(for: selectedPlanID) } ?? ManualProbePlan.readImportedPlan(documents: documents)
            let plan = try ManualProbePlan.decode(bytes)
            summary = "合成测试文件：" + plan.id + "\n数据集：" + plan.dataset
            // This method is invoked only by the explicit Debug button below.
            // The imported document cannot grant authority or supply paths/URLs.
            let probe = try DevelopmentProbe(base: base, dataset: plan.dataset, runID: plan.runID,
                                             authorization: .afterExplicitManualConsent())
            status = "正在执行合成测试，请保持本页打开：" + plan.id
            let execution = try await probe.runManualPlan(bytes, documents: documents)
            manualProbeResultURL = execution.exportURL
            status = execution.report.completedAllCommands
                ? "测试指令执行完成；请导出结果核验，尚不代表双端通过。"
                : "测试已停止，原证据保留：" + (execution.report.errorCode ?? "UNKNOWN")
            if execution.reusedOriginal { status = "已读取此前的原始结果，未重新执行。\n" + status }
        } catch let error as LabError { status = "测试未启动或已停止；原证据保留：LAB_" + String(describing: error) }
        catch { status = "无法执行导入的测试文件；请核对文件，原数据保留。" }
    }
    #endif
}
struct LabScreen: View {
    @StateObject private var model = LabViewModel()
    var body: some View {
        NavigationStack {
            Form {
                #if DEBUG
                if ProcessInfo.processInfo.environment["SYNCLAB_PROBE_RUN"] == nil && ProcessInfo.processInfo.environment["SYNCLAB_ENABLE_DEVELOPMENT"] != "YES" {
                    Section("手机合成测试 · Debug") {
                        Text("仅访问 SyncLab Development 实验容器和合成数据。导入和选择步骤不会自动运行；点击启动才会执行该步骤。")
                        Button("载入已导入的测试批次") { model.loadBundle() }.disabled(model.manualProbeRunning)
                        if let bundle = model.importedBundle {
                            Picker("当前测试步骤", selection: $model.selectedPlanID) {
                                ForEach(bundle.items, id: \.plan.id) { item in Text(item.title).tag(item.plan.id) }
                            }.disabled(model.manualProbeRunning)
                        }
                        Button(manualProbeRunningLabel) { Task { await model.runImportedManualPlan() } }
                            .disabled(model.manualProbeRunning)
                        if let url = model.manualProbeResultURL { ShareLink("导出测试结果", item: url) }
                    }
                }
                #endif
                Section("SyncLab · 仅合成数据") {
                    Text("独立数据库、独立容器。Development 真实验证尚未完成。")
                    TextField("Dataset", text: $model.dataset).disabled(model.store != nil)
                    TextField("合成文字", text: $model.text)
                    Button("离线保存文字和合成原图") { model.save() }
                    Button("显式用当前文字解决全部候选") { model.save(resolve: true) }
                    Button("保存删除意图", role: .destructive) { model.save(deleted: true, resolve: true) }
                }.disabled(model.probeStarted)
                Section("验证状态") { Text(model.summary).textSelection(.enabled); Text(model.status).textSelection(.enabled); Button("导出合成实验快照") { model.export() }.disabled(model.probeStarted); if let url = model.snapshotURL { ShareLink("保存快照副本", item: url) } }
                Section("需先完成签名与账户门禁") {
                    Button("停止网络并重开本地分区") { Task { await model.reopenLocally() } }
                    Button("打开当前测试账户分区") { Task { await model.connect() } }
                    Button("手动发送与获取") { Task { await model.sync() } }
                    Text("默认禁止云访问。只在核对 Development 签名后，按 README 显式启用运行参数；不切换系统账户。")
                }.disabled(model.probeStarted)
            }.navigationTitle("PersonalGrowthOS SyncLab").task {
                if ProcessInfo.processInfo.environment["SYNCLAB_PROBE_RUN"] == nil { model.openOffline() }
                else { await model.runProbeIfRequested() }
            }
        }
    }
    private var manualProbeRunningLabel: String {
        model.manualProbeRunning ? "正在执行…" : "启动导入的合成 Development 测试"
    }
}
