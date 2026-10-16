import Foundation
import SwiftData

struct InvestmentParticipantTransfer: Codable, Equatable {
    var id: UUID; var name: String; var isDefault: Bool; var isArchived: Bool; var sortOrder: Int
    init(_ m: InvestmentParticipant) { id = m.id; name = m.name; isDefault = m.isDefault; isArchived = m.isArchived; sortOrder = m.sortOrder }
    func model() -> InvestmentParticipant { let m = InvestmentParticipant(id: id, name: name, isDefault: isDefault); m.isArchived = isArchived; m.sortOrder = sortOrder; return m }
}
struct InvestmentActivityTransfer: Codable, Equatable {
    var id: UUID; var participantID: UUID; var name: String; var isArchived: Bool
    init(_ m: InvestmentActivity) { id = m.id; participantID = m.participantID; name = m.name; isArchived = m.isArchived }
    func model() -> InvestmentActivity { let m = InvestmentActivity(id: id, participantID: participantID, name: name); m.isArchived = isArchived; return m }
}
struct InvestmentSessionTransfer: Codable, Equatable {
    var id: UUID; var participantID: UUID; var activityID: UUID; var values: InvestmentValues; var revision: Int
    @TodoTransferInstant var createdAt: Date
    @TodoTransferInstant var updatedAt: Date
    init(_ m: InvestmentSession) throws {
        id = m.id; participantID = m.participantID; activityID = m.activityID; values = try m.values(); revision = m.revision; createdAt = m.createdAt; updatedAt = m.updatedAt
    }
    func model() throws -> InvestmentSession {
        let m = try InvestmentSession(id: id, participantID: participantID, activityID: activityID, values: values, now: createdAt)
        m.updatedAt = updatedAt; m.revision = revision; return m
    }
}
struct InvestmentOperationTransfer: Codable, Equatable {
    var id: UUID; var participantID: UUID; var activityID: UUID; var timer: InvestmentTimer; var revision: Int
    @TodoTransferInstant var createdAt: Date
    @TodoTransferInstant var updatedAt: Date
    init(_ m: InvestmentOperation, clock: InvestmentClock? = nil) throws {
        id = m.id; participantID = m.participantID; activityID = m.activityID; revision = m.revision
        let stored = try m.timer(); timer = clock.map { stored.projected(at: $0) } ?? stored
        createdAt = m.createdAt; updatedAt = m.updatedAt
    }
    func model(restoring: Bool) throws -> InvestmentOperation {
        let m = try InvestmentOperation(id: id, participantID: participantID, activityID: activityID,
            timer: restoring ? timer.forRestore() : timer, now: createdAt)
        m.updatedAt = updatedAt; m.revision = revision; return m
    }
}
extension TransferData {
    func validateInvestment(packageVersion: Int) throws {
        func unique(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count }
        guard packageVersion >= 10 || (investmentParticipants.isEmpty && investmentActivities.isEmpty && investmentSessions.isEmpty && investmentOperations.isEmpty),
              unique(investmentParticipants.map(\.id)), unique(investmentActivities.map(\.id)),
              unique(investmentSessions.map(\.id)), unique(investmentOperations.map(\.id)),
              investmentParticipants.filter(\.isDefault).count <= 1 else { throw InvestmentFailure.invalid }
        let participants = Set(investmentParticipants.map(\.id))
        let activities = Dictionary(uniqueKeysWithValues: investmentActivities.map { ($0.id, $0) })
        let sessions = Dictionary(uniqueKeysWithValues: investmentSessions.map { ($0.id, $0) })
        let operations = Dictionary(uniqueKeysWithValues: investmentOperations.map { ($0.id, $0) })
        for p in investmentParticipants { guard !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, p.name.count <= 100, p.sortOrder >= 0 else { throw InvestmentFailure.invalid } }
        for a in investmentActivities { guard participants.contains(a.participantID), !a.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, a.name.count <= 100 else { throw InvestmentFailure.invalid } }
        func validateIdentity(_ participantID: UUID, _ activityID: UUID, _ createdAt: Date, _ updatedAt: Date, _ revision: Int) throws {
            guard participants.contains(participantID), activities[activityID]?.participantID == participantID,
                  createdAt.timeIntervalSinceReferenceDate.isFinite, updatedAt.timeIntervalSinceReferenceDate.isFinite,
                  updatedAt >= createdAt, revision >= 0 else { throw InvestmentFailure.invalid }
        }
        for s in investmentSessions {
            try validateIdentity(s.participantID, s.activityID, s.createdAt, s.updatedAt, s.revision); try s.values.validate()
            guard let op = operations[s.id], op.timer.state == .saved, op.participantID == s.participantID,
                  op.activityID == s.activityID, op.timer.values == s.values else { throw InvestmentFailure.invalid }
        }
        var busy = Set<UUID>()
        for op in investmentOperations {
            try validateIdentity(op.participantID, op.activityID, op.createdAt, op.updatedAt, op.revision); try op.timer.validate()
            if op.timer.state.unfinished { guard busy.insert(op.participantID).inserted else { throw InvestmentFailure.invalid } }
            if op.timer.state == .saved { guard sessions[op.id] != nil else { throw InvestmentFailure.invalid } }
            else { guard sessions[op.id] == nil else { throw InvestmentFailure.invalid } }
        }
    }
    func insertInvestment(into context: ModelContext) throws {
        for p in investmentParticipants { try Task.checkCancellation(); context.insert(p.model()) }
        for a in investmentActivities { try Task.checkCancellation(); context.insert(a.model()) }
        for s in investmentSessions { try Task.checkCancellation(); context.insert(try s.model()) }
        for op in investmentOperations { try Task.checkCancellation(); context.insert(try op.model(restoring: true)) }
    }
}
enum InvestmentIntegrity {
    static func validate(context: ModelContext) throws {
        let data = TransferData(entries: [], images: [], tags: [], links: [], habits: [], habitLogs: [], goals: [], goalEvents: [],
            investmentParticipants: try context.fetch(FetchDescriptor<InvestmentParticipant>()).map(InvestmentParticipantTransfer.init),
            investmentActivities: try context.fetch(FetchDescriptor<InvestmentActivity>()).map(InvestmentActivityTransfer.init),
            investmentSessions: try context.fetch(FetchDescriptor<InvestmentSession>()).map(InvestmentSessionTransfer.init),
            investmentOperations: try context.fetch(FetchDescriptor<InvestmentOperation>()).map { try InvestmentOperationTransfer($0) })
        try data.validateInvestment(packageVersion: 10)
    }
}
