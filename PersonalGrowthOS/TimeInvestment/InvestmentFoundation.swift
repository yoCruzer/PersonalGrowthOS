import Foundation
import SwiftData

// These models are additive. Never add fields to a model used by a historical schema.
@Model final class InvestmentParticipant {
    @Attribute(.unique) var id: UUID
    var name: String
    var isDefault: Bool
    var isArchived: Bool
    var sortOrder: Int
    init(id: UUID = UUID(), name: String = "Me", isDefault: Bool = false) {
        self.id = id; self.name = name; self.isDefault = isDefault; isArchived = false; sortOrder = 0
    }
}
@Model final class InvestmentActivity {
    @Attribute(.unique) var id: UUID
    var participantID: UUID
    var name: String
    var isArchived: Bool
    init(id: UUID = UUID(), participantID: UUID, name: String) {
        self.id = id; self.participantID = participantID; self.name = name; isArchived = false
    }
}
@Model final class InvestmentSession {
    @Attribute(.unique) var id: UUID // Stable operation identity, also after deletion.
    var participantID: UUID
    var activityID: UUID
    var valueData: Data
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    init(id: UUID, participantID: UUID, activityID: UUID, values: InvestmentValues, now: Date) throws {
        self.id = id; self.participantID = participantID; self.activityID = activityID
        valueData = try JSONEncoder().encode(values); createdAt = now; updatedAt = now; revision = 0
    }
    func values() throws -> InvestmentValues { try JSONDecoder().decode(InvestmentValues.self, from: valueData) }
}
@Model final class InvestmentOperation {
    @Attribute(.unique) var id: UUID
    var participantID: UUID
    var activityID: UUID
    var payload: Data
    var revision: Int
    var createdAt: Date
    var updatedAt: Date
    init(id: UUID, participantID: UUID, activityID: UUID, timer: InvestmentTimer, now: Date) throws {
        self.id = id; self.participantID = participantID; self.activityID = activityID
        payload = try JSONEncoder().encode(timer); revision = 0; createdAt = now; updatedAt = now
    }
    func timer() throws -> InvestmentTimer { try JSONDecoder().decode(InvestmentTimer.self, from: payload) }
}

enum InvestmentFailure: Error, LocalizedError {
    case invalid, conflict, missing, unfinished, archived, duplicate
    var errorDescription: String? {
        switch self {
        case .invalid: String(localized: "Check the activity, date, duration and time evidence.")
        case .conflict: String(localized: "This item changed elsewhere. Your input is retained; reopen it to compare.")
        case .missing: String(localized: "This item is no longer available.")
        case .unfinished: String(localized: "Handle the unfinished timer before starting another.")
        case .archived: String(localized: "Restore this activity before starting or recording.")
        case .duplicate: String(localized: "Possible duplicate or overlapping time. Review the matching records or explicitly confirm.")
        }
    }
}

struct InvestmentSpan: Codable, Equatable {
    @TodoTransferInstant var start: Date
    @TodoTransferInstant var end: Date
    var seconds: Double { end.timeIntervalSince(start) }
}
enum InvestmentEvidence: String, Codable { case intervals, dateDuration, correctedDuration }
enum InvestmentSource: String, Codable { case timer, manual }
struct InvestmentValues: Codable, Equatable {
    var day: String
    var timeZoneID: String
    var seconds: Double
    var evidence: InvestmentEvidence
    var source: InvestmentSource
    var spans: [InvestmentSpan] = []
    var feeling: Int? = nil
    var note = ""
    var corrected = false
    // The V1 feeling is always the participant's self report, never an inferred middle score.
    var feedbackSource = "selfReport"

    mutating func changeDuration(_ seconds: Double) {
        guard self.seconds != seconds else { return }
        self.seconds = seconds; spans = []; evidence = .correctedDuration; corrected = true
    }
    func validate(now: Date? = nil) throws {
        guard let zone = TimeZone(identifier: timeZoneID), let civil = ImportantCivilDay(identifier: day),
              seconds.isFinite, seconds > 0, seconds <= 366 * 86400,
              note.count <= 4000, feeling.map({ (1...5).contains($0) }) ?? true,
              feedbackSource == "selfReport" else { throw InvestmentFailure.invalid }
        if evidence == .intervals {
            guard !spans.isEmpty, spans.count <= 10000,
                  abs(spans.reduce(0) { $0 + $1.seconds } - seconds) < 0.001,
                  ImportantCivilDay(spans[0].start, timeZone: zone).identifier == day else { throw InvestmentFailure.invalid }
            var previous: Date?
            for span in spans {
                guard span.start.timeIntervalSinceReferenceDate.isFinite, span.end.timeIntervalSinceReferenceDate.isFinite,
                      span.seconds > 0, previous.map({ $0 <= span.start }) ?? true else { throw InvestmentFailure.invalid }
                if let now, span.end > now { throw InvestmentFailure.invalid }
                previous = span.end
            }
        } else { guard spans.isEmpty else { throw InvestmentFailure.invalid } }
        if evidence == .correctedDuration { guard corrected else { throw InvestmentFailure.invalid } }
        if let now, civil > ImportantCivilDay(now, timeZone: zone) { throw InvestmentFailure.invalid }
    }
}

struct InvestmentClock: Equatable {
    var wall: Date
    var uptime: Double
    var processID: String
    private static let currentProcessID = UUID().uuidString
    static func current() -> Self { .init(wall: Date(), uptime: ProcessInfo.processInfo.systemUptime, processID: currentProcessID) }
}
enum InvestmentTimerState: String, Codable {
    case running, paused, targetReached, pendingSave, recoveryRequired, draft, saved, discarded, deleted
    var unfinished: Bool { [.running, .paused, .targetReached, .pendingSave, .recoveryRequired].contains(self) }
    var terminal: Bool { [.saved, .discarded, .deleted].contains(self) }
}
struct InvestmentTimer: Codable, Equatable {
    var state: InvestmentTimerState
    var values: InvestmentValues
    var target: Double?
    @TodoTransferOptionalInstant var anchor: Date? = nil
    var anchorUptime: Double? = nil
    var processID: String? = nil
    @TodoTransferInstant var checkpointAt: Date
    var restoredState: InvestmentTimerState? = nil

    mutating func clearAnchor() { anchor = nil; anchorUptime = nil; processID = nil }
    mutating func resume(at clock: InvestmentClock, asStopwatch: Bool = false) throws {
        guard state.unfinished, state != .running else { throw InvestmentFailure.conflict }
        if asStopwatch || state == .targetReached { target = nil }
        guard values.spans.last.map({ $0.end <= clock.wall }) ?? true else { throw InvestmentFailure.invalid }
        state = .running; anchor = clock.wall; anchorUptime = clock.uptime; processID = clock.processID; checkpointAt = clock.wall
    }
    // Pure projection used by foreground display, checkpoints and the export snapshot.
    // Across processes we retain the last durable checkpoint and require human confirmation.
    func projected(at clock: InvestmentClock) -> Self {
        guard state == .running else { return self }
        var result = self
        guard let anchor, let anchorUptime, processID == clock.processID,
              clock.uptime.isFinite, clock.uptime >= anchorUptime else {
            result.state = .recoveryRequired; result.clearAnchor(); return result
        }
        let delta = clock.uptime - anchorUptime
        guard abs(clock.wall.timeIntervalSince(anchor) - delta) <= 2, delta <= 18 * 3600,
              values.seconds + delta <= 18 * 3600 else {
            result.state = .recoveryRequired; result.clearAnchor(); return result
        }
        let credited = min(delta, max(0, (target ?? .greatestFiniteMagnitude) - values.seconds))
        if credited > 0 {
            result.values.spans.append(.init(start: anchor, end: anchor.addingTimeInterval(credited)))
            result.values.seconds += credited
            result.values.evidence = .intervals
        }
        result.checkpointAt = clock.wall
        if let target, result.values.seconds >= target {
            result.state = .targetReached; result.clearAnchor()
        } else { result.anchor = clock.wall; result.anchorUptime = clock.uptime }
        return result
    }
    func forRestore() -> Self {
        guard state.unfinished else { return self }
        var value = self; value.restoredState = restoredState ?? state
        value.state = .recoveryRequired; value.clearAnchor(); return value
    }
    func validate() throws {
        guard checkpointAt.timeIntervalSinceReferenceDate.isFinite,
              target.map({ $0.isFinite && $0 > 0 && $0 <= 18 * 3600 }) ?? true,
              values.seconds.isFinite, values.seconds >= 0,
              TimeZone(identifier: values.timeZoneID) != nil,
              ImportantCivilDay(identifier: values.day) != nil else { throw InvestmentFailure.invalid }
        if values.seconds > 0 { try values.validate() }
        else { guard values.spans.isEmpty, values.feeling.map({ (1...5).contains($0) }) ?? true,
                     values.note.count <= 4000 else { throw InvestmentFailure.invalid } }
        if state == .running {
            guard let anchor, let anchorUptime, let processID, !processID.isEmpty,
                  anchor.timeIntervalSinceReferenceDate.isFinite, anchorUptime.isFinite, anchorUptime >= 0,
                  anchor == checkpointAt else { throw InvestmentFailure.invalid }
        } else { guard anchor == nil, anchorUptime == nil, processID == nil else { throw InvestmentFailure.invalid } }
        if state == .targetReached { guard let target, values.seconds == target else { throw InvestmentFailure.invalid } }
    }
}

struct InvestmentOperationSnapshot: Identifiable, Equatable {
    var id: UUID
    var participantID: UUID
    var activityID: UUID
    var revision: Int
    var timer: InvestmentTimer
    init(_ model: InvestmentOperation) throws {
        id = model.id; participantID = model.participantID; activityID = model.activityID
        revision = model.revision; timer = try model.timer()
    }
}
extension Notification.Name { static let investmentChanged = Notification.Name("investmentChanged") }

/// One serialized main-actor transaction with a fresh context per command. No foreign draft is saved or rolled back.
@MainActor final class InvestmentService {
    private let container: ModelContainer
    private let clock: () -> InvestmentClock
    private let commit: (ModelContext) throws -> Void
    init(context: ModelContext, clock: @escaping () -> InvestmentClock = InvestmentClock.current,
         commit: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        container = context.container; self.clock = clock; self.commit = commit
    }
    private func transaction<T>(_ body: (ModelContext, InvestmentClock) throws -> T) throws -> T {
        let store = container.configurations.first!.url
        let parent = store.deletingLastPathComponent()
        let root = parent.lastPathComponent == "Store" ? parent.deletingLastPathComponent() : parent
        let result = try StorePublication.perform(at: root) {
            let context = ModelContext(container); context.autosaveEnabled = false
            do { let result = try body(context, clock()); try commit(context); return result }
            catch { context.rollback(); throw error }
        }
        NotificationCenter.default.post(name: .investmentChanged, object: container)
        return result
    }
    private func participant(_ id: UUID?, in context: ModelContext) throws -> UUID {
        let all = try context.fetch(FetchDescriptor<InvestmentParticipant>())
        if let id { guard all.contains(where: { $0.id == id && !$0.isArchived }) else { throw InvestmentFailure.missing }; return id }
        let defaults = all.filter(\.isDefault)
        guard defaults.count <= 1 else { throw InvestmentFailure.invalid }
        if let existing = defaults.first { return existing.id }
        let model = InvestmentParticipant(isDefault: true); context.insert(model); return model.id
    }
    func createActivity(name: String, participantID: UUID? = nil, id: UUID = UUID()) throws -> UUID {
        try transaction { context, _ in
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 100 else { throw InvestmentFailure.invalid }
            if let existing = try context.fetch(FetchDescriptor<InvestmentActivity>()).first(where: { $0.id == id }) { return existing.id }
            context.insert(InvestmentActivity(id: id, participantID: try participant(participantID, in: context), name: name)); return id
        }
    }
    func updateActivity(id: UUID, name: String, archived: Bool) throws {
        try transaction { context, _ in
            guard let model = try context.fetch(FetchDescriptor<InvestmentActivity>()).first(where: { $0.id == id }) else { throw InvestmentFailure.missing }
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 100 else { throw InvestmentFailure.invalid }
            model.name = name; model.isArchived = archived
        }
    }
    func operations() throws -> [InvestmentOperationSnapshot] {
        try ModelContext(container).fetch(FetchDescriptor<InvestmentOperation>()).map(InvestmentOperationSnapshot.init)
    }
    func start(activityID: UUID, participantID: UUID, operationID: UUID, target: Double? = nil, zone: TimeZone = .current) throws -> UUID {
        try transaction { context, now in
            let all = try context.fetch(FetchDescriptor<InvestmentOperation>())
            if let existing = all.first(where: { $0.id == operationID }) {
                guard existing.participantID == participantID, existing.activityID == activityID else { throw InvestmentFailure.conflict }
                return operationID // Even terminal IDs remain consumed; an old callback cannot resurrect them.
            }
            guard !(try all.filter { $0.participantID == participantID }.contains { try $0.timer().state.unfinished }) else { throw InvestmentFailure.unfinished }
            try activity(activityID, participantID: participantID, context: context, allowArchived: false)
            var timer = InvestmentTimer(state: .paused, values: .init(day: ImportantCivilDay(now.wall, timeZone: zone).identifier,
                timeZoneID: zone.identifier, seconds: 0, evidence: .intervals, source: .timer), target: target, checkpointAt: now.wall)
            try timer.resume(at: now); try timer.validate()
            context.insert(try InvestmentOperation(id: operationID, participantID: participantID, activityID: activityID, timer: timer, now: now.wall))
            return operationID
        }
    }
    private func activity(_ id: UUID, participantID: UUID, context: ModelContext, allowArchived: Bool) throws {
        guard let activity = try context.fetch(FetchDescriptor<InvestmentActivity>()).first(where: { $0.id == id && $0.participantID == participantID }) else { throw InvestmentFailure.missing }
        if !allowArchived && activity.isArchived { throw InvestmentFailure.archived }
    }
    enum Command { case checkpoint, pause, resume, finish, discard }
    func command(_ command: Command, id: UUID, revision: Int) throws {
        try transaction { context, clock in
            guard let op = try context.fetch(FetchDescriptor<InvestmentOperation>()).first(where: { $0.id == id }) else { throw InvestmentFailure.missing }
            var timer = try op.timer()
            guard !timer.state.terminal else { return }
            guard op.revision == revision else { throw InvestmentFailure.conflict }
            timer = timer.projected(at: clock)
            switch command {
            case .checkpoint: break
            case .pause:
                if timer.state == .running { timer.state = .paused; timer.clearAnchor() }
            case .resume: try timer.resume(at: clock, asStopwatch: timer.state == .targetReached)
            case .finish:
                guard timer.state.unfinished else { throw InvestmentFailure.conflict }
                // Recovery stays visibly uncertain until the user confirms or corrects it.
                if timer.state != .recoveryRequired { timer.state = .pendingSave }
                timer.clearAnchor()
            case .discard: timer.state = .discarded; timer.clearAnchor()
            }
            try timer.validate(); op.payload = try JSONEncoder().encode(timer); op.revision += 1
            op.updatedAt = max(op.updatedAt, clock.wall)
        }
    }
    @discardableResult func saveTimer(id: UUID, revision: Int, values: InvestmentValues, confirmDuplicate: Bool = false) throws -> UUID {
        try transaction { context, now in
            guard let op = try context.fetch(FetchDescriptor<InvestmentOperation>()).first(where: { $0.id == id }) else { throw InvestmentFailure.missing }
            var timer = try op.timer()
            if timer.state == .saved { return id }
            guard op.revision == revision, [.pendingSave, .targetReached, .recoveryRequired].contains(timer.state) else { throw InvestmentFailure.conflict }
            try values.validate(now: now.wall)
            guard values.source == .timer else { throw InvestmentFailure.invalid }
            try duplicates(values: values, participantID: op.participantID, excluding: id, context: context, confirmed: confirmDuplicate)
            context.insert(try InvestmentSession(id: id, participantID: op.participantID, activityID: op.activityID, values: values, now: now.wall))
            timer.values = values; timer.state = .saved; timer.clearAnchor()
            op.payload = try JSONEncoder().encode(timer); op.revision += 1; op.updatedAt = max(op.updatedAt, now.wall)
            return id
        }
    }
    private func duplicates(values: InvestmentValues, participantID: UUID, excluding: UUID, context: ModelContext, confirmed: Bool) throws {
        guard !confirmed else { return }
        for model in try context.fetch(FetchDescriptor<InvestmentSession>()) where model.participantID == participantID && model.id != excluding {
            let other = try model.values()
            if values.evidence == .intervals && other.evidence == .intervals {
                if values.spans.contains(where: { a in other.spans.contains { b in a.start < b.end && b.start < a.end } }) { throw InvestmentFailure.duplicate }
            } else if values.day == other.day && values.seconds == other.seconds { throw InvestmentFailure.duplicate }
        }
    }
    @discardableResult func saveManual(id: UUID, participantID: UUID, activityID: UUID, values: InvestmentValues, expectedRevision: Int? = nil, confirmDuplicate: Bool = false) throws -> UUID {
        try transaction { context, now in
            let records = try context.fetch(FetchDescriptor<InvestmentSession>())
            let operations = try context.fetch(FetchDescriptor<InvestmentOperation>())
            let existing = records.first { $0.id == id }
            if existing == nil, let consumed = operations.first(where: { $0.id == id }), try consumed.timer().state.terminal { throw InvestmentFailure.conflict }
            if let existing { guard existing.revision == expectedRevision else { throw InvestmentFailure.conflict } }
            else { guard expectedRevision == nil else { throw InvestmentFailure.missing } }
            try activity(activityID, participantID: participantID, context: context, allowArchived: existing?.activityID == activityID)
            try values.validate(now: now.wall)
            if let existing, try existing.values() == values, existing.activityID == activityID { return id }
            try duplicates(values: values, participantID: participantID, excluding: id, context: context, confirmed: confirmDuplicate)
            if let existing {
                guard existing.participantID == participantID else { throw InvestmentFailure.conflict }
                existing.activityID = activityID; existing.valueData = try JSONEncoder().encode(values); existing.revision += 1
                existing.updatedAt = max(existing.updatedAt, existing.createdAt, now.wall)
            } else { context.insert(try InvestmentSession(id: id, participantID: participantID, activityID: activityID, values: values, now: now.wall)) }
            if let op = operations.first(where: { $0.id == id }) {
                var timer = try op.timer(); timer.state = .saved; timer.values = values; timer.clearAnchor()
                op.payload = try JSONEncoder().encode(timer); op.revision += 1; op.updatedAt = max(op.updatedAt, now.wall)
            } else {
                context.insert(try InvestmentOperation(id: id, participantID: participantID, activityID: activityID,
                    timer: .init(state: .saved, values: values, target: nil, checkpointAt: now.wall), now: now.wall))
            }
            return id
        }
    }
    func delete(id: UUID, revision: Int) throws {
        try transaction { context, clock in
            guard let model = try context.fetch(FetchDescriptor<InvestmentSession>()).first(where: { $0.id == id }) else { throw InvestmentFailure.missing }
            guard model.revision == revision else { throw InvestmentFailure.conflict }
            guard let op = try context.fetch(FetchDescriptor<InvestmentOperation>()).first(where: { $0.id == id }) else { throw InvestmentFailure.invalid }
            var timer = try op.timer(); timer.state = .deleted; timer.clearAnchor(); timer.values.note = ""; timer.values.feeling = nil
            op.payload = try JSONEncoder().encode(timer); op.revision += 1; op.updatedAt = max(op.updatedAt, clock.wall); context.delete(model)
        }
    }
}

struct InvestmentContribution: Identifiable, Equatable {
    var sessionID: UUID
    var activityID: UUID
    var day: String
    var seconds: Double
    var id: String { sessionID.uuidString + day }
}
enum InvestmentReview {
    static func contributions(id: UUID, activityID: UUID, values: InvestmentValues) throws -> [InvestmentContribution] {
        try values.validate()
        if values.evidence != .intervals { return [.init(sessionID: id, activityID: activityID, day: values.day, seconds: values.seconds)] }
        var totals: [String: Double] = [:]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: values.timeZoneID)!
        for span in values.spans {
            var cursor = span.start
            while cursor < span.end {
                guard let boundary = calendar.dateInterval(of: .day, for: cursor)?.end, boundary > cursor else { throw InvestmentFailure.invalid }
                let end = min(boundary, span.end), day = ImportantCivilDay(cursor, timeZone: calendar.timeZone).identifier
                totals[day, default: 0] += end.timeIntervalSince(cursor); cursor = end
            }
        }
        return totals.keys.sorted().map { .init(sessionID: id, activityID: activityID, day: $0, seconds: totals[$0]!) }
    }
    static func window(_ rows: [InvestmentContribution], days: Int?, today: ImportantCivilDay, activityID: UUID? = nil) -> [InvestmentContribution] {
        let lower = days.flatMap { today.adding(days: 1 - $0)?.identifier }
        return rows.filter { (activityID == nil || $0.activityID == activityID) && (lower == nil || ($0.day >= lower! && $0.day <= today.identifier)) }
    }
    static func count(_ rows: [InvestmentContribution]) -> Int { Set(rows.map(\.sessionID)).count }
}
