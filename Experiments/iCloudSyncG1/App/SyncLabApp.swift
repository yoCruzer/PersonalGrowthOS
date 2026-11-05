import SwiftUI
import CloudKit

@main struct SyncLabApp: App {
    var body: some Scene { WindowGroup { LabScreen() } }
}
@MainActor final class LabViewModel: ObservableObject {
    @Published var status = "离线实验；尚未连接 CloudKit"
    @Published var text = "SYNTHETIC G1"
    @Published var dataset = ProcessInfo.processInfo.environment["SYNCLAB_DATASET"] ?? "synthetic-g1-001"
    @Published var summary = ""
    @Published var snapshotURL: URL?
    var store: LabStore?
    var driver: CloudDriver?
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
}
struct LabScreen: View {
    @StateObject private var model = LabViewModel()
    var body: some View {
        NavigationStack {
            Form {
                Section("SyncLab · 仅合成数据") {
                    Text("独立数据库、独立容器。Development 真实验证尚未完成。")
                    TextField("Dataset", text: $model.dataset).disabled(model.store != nil)
                    TextField("合成文字", text: $model.text)
                    Button("离线保存文字和合成原图") { model.save() }
                    Button("显式用当前文字解决全部候选") { model.save(resolve: true) }
                    Button("保存删除意图", role: .destructive) { model.save(deleted: true, resolve: true) }
                }
                Section("验证状态") { Text(model.summary).textSelection(.enabled); Text(model.status).textSelection(.enabled); Button("导出合成实验快照") { model.export() }; if let url = model.snapshotURL { ShareLink("保存快照副本", item: url) } }
                Section("需先完成签名与账户门禁") {
                    Button("停止网络并重开本地分区") { Task { await model.reopenLocally() } }
                    Button("打开当前测试账户分区") { Task { await model.connect() } }
                    Button("手动发送与获取") { Task { await model.sync() } }
                    Text("默认禁止云访问。只在核对 Development 签名后，按 README 显式启用运行参数；不切换系统账户。")
                }
            }.navigationTitle("PersonalGrowthOS SyncLab").task { model.openOffline() }
        }
    }
}
