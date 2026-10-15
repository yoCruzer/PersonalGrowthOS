import Foundation

struct ImportantDayWidgetRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let rule: ImportantDayDateRule
    let photoStyle: Bool
    let cropX: Double
    let cropY: Double
    let coverFilename: String?
}
struct ImportantDayWidgetSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1
    let version: Int
    let generation: UUID
    let generatedAt: Date
    let records: [ImportantDayWidgetRecord]
    func validate() throws {
        guard version == Self.currentVersion, records.count <= 2000, Set(records.map(\.id)).count == records.count else { throw ImportantWidgetSnapshotError.invalid }
        for record in records {
            guard !record.title.isEmpty, record.title.count <= 80, record.cropX.isFinite, record.cropY.isFinite,
                  (0...1).contains(record.cropX), (0...1).contains(record.cropY),
                  record.coverFilename.map({ $0 == record.id.uuidString.lowercased() + ".jpg" }) ?? true else { throw ImportantWidgetSnapshotError.invalid }
            try record.rule.validate()
        }
    }
}
enum ImportantWidgetSnapshotError: Error { case unavailable, invalid, tooLarge }

/// Widget reads only this projection; no SwiftData dependency or primary-store path.
struct ImportantDayWidgetSnapshotStore {
    static let appGroup = "group.com.yocruzer.PersonalGrowthOS"
    let root: URL
    var manifest: URL { root.appendingPathComponent("snapshot.json") }
    static func shared() throws -> Self {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { throw ImportantWidgetSnapshotError.unavailable }
        return Self(root: group.appendingPathComponent("ImportantDays", isDirectory: true))
    }
    func read() throws -> ImportantDayWidgetSnapshot {
        let attrs = try FileManager.default.attributesOfItem(atPath: manifest.path)
        guard ((attrs[.size] as? NSNumber)?.intValue ?? Int.max) <= 2_000_000 else { throw ImportantWidgetSnapshotError.tooLarge }
        let snapshot = try JSONDecoder().decode(ImportantDayWidgetSnapshot.self, from: Data(contentsOf: manifest))
        try snapshot.validate(); return snapshot
    }
    func coverURL(record: ImportantDayWidgetRecord, generation: UUID) -> URL? {
        guard let name = record.coverFilename, name == record.id.uuidString.lowercased() + ".jpg" else { return nil }
        return root.appendingPathComponent(generation.uuidString.lowercased(), isDirectory: true).appendingPathComponent(name)
    }
    /// Revoke first. A failed later publication must never keep an old readable private projection.
    func revoke() throws {
        if FileManager.default.fileExists(atPath: manifest.path) { try FileManager.default.removeItem(at: manifest) }
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
    }
    func publish(_ snapshot: ImportantDayWidgetSnapshot, covers: [UUID: Data]) throws {
        try snapshot.validate()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let generationRoot = root.appendingPathComponent(snapshot.generation.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: generationRoot, withIntermediateDirectories: true)
        do {
            for record in snapshot.records {
                if let filename = record.coverFilename {
                    guard let data = covers[record.id], data.count <= 700_000 else { throw ImportantWidgetSnapshotError.invalid }
                    try data.write(to: generationRoot.appendingPathComponent(filename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
            }
            let data = try JSONEncoder().encode(snapshot)
            guard data.count <= 2_000_000 else { throw ImportantWidgetSnapshotError.tooLarge }
            try data.write(to: manifest, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { try? FileManager.default.removeItem(at: generationRoot); throw error }
    }
}

enum ImportantDayRoute {
    static func url(id: UUID) -> URL { URL(string: "suixinlog://important-day/" + id.uuidString.lowercased())! }
    static func parse(_ url: URL) -> UUID? {
        guard url.scheme == "suixinlog", url.host == "important-day", url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2 else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
