import XCTest
import Foundation
@testable import FormalDevelopmentSDK

// The actual local policy and ledger, synthetic memory anchor only. No session,
// CKContainer, account lookup, Keychain or production qualification is created.
@MainActor final class AccountReadPolicyTests: XCTestCase {
    private let helper = ExecutionLedgerTests()
    private let digest = String(repeating: "a", count: 64)

    func testTwelveReadsAcrossDurableQualificationAndFiveStagesThenStops() throws {
        let c = try helper.context(), ledger = try helper.enroll(c), binding = helper.binding(c)
        let policy = AccountReadPolicy(ledger: ledger, qualificationBinding: binding)
        let account = try ledger.accountDigest("invented-account-read-policy-fixture")
        let qualification = try ledger.consume(.qualificationRead, binding: binding)
        func read(_ op: LedgerOperation, _ permit: ExecutionPermit, account: String? = nil) throws {
            let id = try ledger.intent(op, permit: permit)
            try policy.authorize(op, operationID: id, permit: permit)
            let ticket = try policy.take(status: op == .accountStatus)
            try policy.beforeEnqueue(ticket)
            XCTAssertThrowsError(try policy.beforeEnqueue(ticket), "A pending durable intent cannot spend a ticket twice")
            XCTAssertThrowsError(try policy.authorize(op, operationID: id, permit: permit))
            try ledger.returned(op, status: .success, summarySHA256: digest, accountSHA256: account, permit: permit)
            try ledger.validated(op, permit: permit)
        }
        try read(.accountStatus, qualification)
        try read(.userRecordID, qualification, account: account)
        try ledger.finishQualification(accountSHA256: account, permit: qualification)
        let batch = try ledger.consume(.developmentBatch, binding: helper.batchBinding(binding, account: account))
        for stage in LedgerStage.allCases {
            try read(.accountCheckBefore(stage), batch, account: account)
            try ledger.intent(.transport(stage), permit: batch)
            try ledger.returned(.transport(stage), status: .success, summarySHA256: digest, permit: batch)
            try read(.accountCheckAfter(stage), batch, account: account)
            try ledger.validated(.transport(stage), permit: batch)
        }
        XCTAssertEqual(policy.apiInvocations, 12)
        XCTAssertThrowsError(try policy.authorize(.accountStatus, operationID: UUID(), permit: qualification))
        XCTAssertThrowsError(try policy.take(status: false))
        XCTAssertEqual(policy.apiInvocations, 12)
        try ledger.finishBatch(permit: batch)
        XCTAssertFalse(ledger.hasUnresolvedExecutions)
    }

    func testNoIntentWrongIDWrongKindAndOneShotTicket() throws {
        let c = try helper.context(), ledger = try helper.enroll(c), binding = helper.binding(c)
        let policy = AccountReadPolicy(ledger: ledger, qualificationBinding: binding)
        let permit = try ledger.consume(.qualificationRead, binding: binding)
        XCTAssertThrowsError(try policy.take(status: true))
        XCTAssertThrowsError(try policy.authorize(.accountStatus, operationID: UUID(), permit: permit))
        let id = try ledger.intent(.accountStatus, permit: permit)
        XCTAssertThrowsError(try policy.authorize(.accountStatus, operationID: UUID(), permit: permit))
        XCTAssertThrowsError(try policy.authorize(.userRecordID, operationID: id, permit: permit))
        XCTAssertThrowsError(try policy.authorize(.transport(.zoneProbe), operationID: id, permit: permit))
        try policy.authorize(.accountStatus, operationID: id, permit: permit)
        XCTAssertThrowsError(try policy.take(status: false))
        XCTAssertThrowsError(try policy.authorize(.accountStatus, operationID: id, permit: permit))
        let ticket = try policy.take(status: true)
        XCTAssertThrowsError(try policy.take(status: true))
        try policy.beforeEnqueue(ticket)
        XCTAssertEqual(policy.apiInvocations, 1)
        XCTAssertThrowsError(try policy.beforeEnqueue(ticket))
        XCTAssertEqual(policy.apiInvocations, 1)
    }

    func testIntentMustStillBePendingAtTakeAndAtEnqueue() throws {
        for afterTake in [false, true] {
            let c = try helper.context(), ledger = try helper.enroll(c), binding = helper.binding(c)
            let policy = AccountReadPolicy(ledger: ledger, qualificationBinding: binding)
            let permit = try ledger.consume(.qualificationRead, binding: binding)
            let id = try ledger.intent(.accountStatus, permit: permit)
            try policy.authorize(.accountStatus, operationID: id, permit: permit)
            let ticket = afterTake ? try policy.take(status: true) : nil
            try ledger.returned(.accountStatus, status: .success, summarySHA256: digest, permit: permit)
            if let ticket { XCTAssertThrowsError(try policy.beforeEnqueue(ticket)) }
            else { XCTAssertThrowsError(try policy.take(status: true)) }
            XCTAssertEqual(policy.apiInvocations, 0)
        }
    }

    func testTamperedJournalAtEveryBoundaryCannotAuthorizeRead() throws {
        for boundary in [0, 1, 2] {
            let c = try helper.context(), ledger = try helper.enroll(c), binding = helper.binding(c)
            let policy = AccountReadPolicy(ledger: ledger, qualificationBinding: binding)
            let permit = try ledger.consume(.qualificationRead, binding: binding)
            let id = try ledger.intent(.accountStatus, permit: permit)
            if boundary > 0 { try policy.authorize(.accountStatus, operationID: id, permit: permit) }
            let ticket = boundary == 2 ? try policy.take(status: true) : nil
            try Data("synthetic corrupt journal".utf8).write(to: c.root.appendingPathComponent("00000002.json"))
            if let ticket { XCTAssertThrowsError(try policy.beforeEnqueue(ticket)) }
            else if boundary == 1 { XCTAssertThrowsError(try policy.take(status: true)) }
            else { XCTAssertThrowsError(try policy.authorize(.accountStatus, operationID: id, permit: permit)) }
            XCTAssertEqual(policy.apiInvocations, 0)
        }
    }

    func testEveryApprovalBindingFieldIsComparedNotOnlyOwnerWindow() throws {
        let c = try helper.context(), ledger = try helper.enroll(c), binding = helper.binding(c)
        let permit = try ledger.consume(.qualificationRead, binding: binding)
        let id = try ledger.intent(.accountStatus, permit: permit)
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: ledgerEncode(binding)) as? [String: Any])
        XCTAssertEqual(Set(base.keys), Set(["ownerWindow", "approvalInputSHA256", "ownerDecisionSHA256", "windowStartMS", "windowEndMS", "planSHA256", "run", "dataset", "schemaSHA256", "binarySHA256", "codeDirectoryHash", "profileSHA256", "packagingReceiptSHA256", "sourcePinsSHA256", "osUserID", "osSessionSHA256", "ownerConfirmedAccountSessionSHA256"]), "All non-account binding fields must be exercised")
        for (key, value) in base {
            var changed = base
            if let number = value as? NSNumber { changed[key] = number.int64Value + 1 }
            else if ["ownerWindow", "run", "dataset"].contains(key) { changed[key] = UUID().uuidString }
            else { changed[key] = String(repeating: "f", count: (value as? String)?.count ?? 64) }
            let other = try JSONDecoder().decode(ExecutionBinding.self, from: JSONSerialization.data(withJSONObject: changed))
            XCTAssertFalse(binding.sameApproval(as: other), key)
            let policy = AccountReadPolicy(ledger: ledger, qualificationBinding: other)
            XCTAssertThrowsError(try policy.authorize(.accountStatus, operationID: id, permit: permit), key)
            XCTAssertEqual(policy.apiInvocations, 0)
        }
        let valid = AccountReadPolicy(ledger: ledger, qualificationBinding: binding)
        XCTAssertNoThrow(try valid.authorize(.accountStatus, operationID: id, permit: permit))
    }
}
