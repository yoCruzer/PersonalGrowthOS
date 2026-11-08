import XCTest
import Foundation
import CryptoKit
import Darwin
@testable import FormalDevelopmentSDK

@MainActor final class FakeExecutionAnchor: ExecutionAnchorStore {
    var bytes: Data?
    var failNextReplace = false
    var afterReplace: (() throws -> Void)?
    func load() throws -> Data? { bytes }
    func create(_ data: Data) throws { guard bytes == nil else { throw LedgerFailure.anchorFailure }; bytes = data }
    func replace(expected: Data, with data: Data) throws {
        guard bytes == expected else { throw LedgerFailure.anchorFailure }
        if failNextReplace { failNextReplace = false; throw LedgerFailure.anchorFailure }
        bytes = data; try afterReplace?()
    }
}
@MainActor final class FakeExecutionClock: LedgerClock {
    var wall: Int64 = 1_800_000_000_000
    var uptime: UInt64 = 10_000
    func now() -> LedgerTime { LedgerTime(wallMS: wall, uptimeNS: uptime) }
}
@MainActor final class ExecutionLedgerTests: XCTestCase {
    let digest = String(repeating: "a", count: 64)
    @MainActor struct Context {
        let parent: URL, root: URL, store: FakeExecutionAnchor, clock: FakeExecutionClock
        func open() throws -> ExecutionLedger { try .openForTesting(root: root, anchorStore: store, clock: clock) }
    }
    func context() throws -> Context {
        let parent = URL(fileURLWithPath: "/private/tmp/pgos-ledger-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return Context(parent: parent, root: parent.appendingPathComponent("guard"), store: FakeExecutionAnchor(), clock: FakeExecutionClock())
    }
    func enroll(_ c: Context) throws -> ExecutionLedger {
        try .enrollForTesting(root: c.root, anchorStore: c.store, clock: c.clock, ownerDecisionSHA256: digest)
    }
    func binding(_ c: Context, run: UUID = UUID(), dataset: UUID = UUID(), plan: String? = nil, account: String? = nil,
                 owner: String? = nil, end: Int64? = nil, window: UUID = UUID(), approval: String? = nil) -> ExecutionBinding {
        ExecutionBinding(ownerWindow: window, approvalInputSHA256: approval ?? SHA256.hash(data: Data(window.uuidString.utf8)).map { String(format: "%02x", $0) }.joined(), ownerDecisionSHA256: owner ?? digest, windowStartMS: c.clock.wall - 1_000, windowEndMS: end ?? c.clock.wall + 60_000,
            planSHA256: plan ?? digest, run: run, dataset: dataset,
            schemaSHA256: "6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003",
            binarySHA256: digest, codeDirectoryHash: String(repeating: "b", count: 40), profileSHA256: digest, packagingReceiptSHA256: digest, sourcePinsSHA256: digest,
            osUserID: getuid(), osSessionSHA256: digest, ownerConfirmedAccountSessionSHA256: digest, accountSHA256: account)
    }
    func batchBinding(_ b: ExecutionBinding, account: String) -> ExecutionBinding {
        ExecutionBinding(ownerWindow: b.ownerWindow, approvalInputSHA256: b.approvalInputSHA256, ownerDecisionSHA256: b.ownerDecisionSHA256, windowStartMS: b.windowStartMS, windowEndMS: b.windowEndMS,
            planSHA256: b.planSHA256, run: b.run, dataset: b.dataset, schemaSHA256: b.schemaSHA256, binarySHA256: b.binarySHA256,
            codeDirectoryHash: b.codeDirectoryHash, profileSHA256: b.profileSHA256, packagingReceiptSHA256: b.packagingReceiptSHA256, sourcePinsSHA256: b.sourcePinsSHA256, osUserID: b.osUserID,
            osSessionSHA256: b.osSessionSHA256, ownerConfirmedAccountSessionSHA256: b.ownerConfirmedAccountSessionSHA256, accountSHA256: account)
    }
    func roundtrip(_ op: LedgerOperation, ledger: ExecutionLedger, permit: ExecutionPermit, account: String? = nil) throws {
        try ledger.intent(op, permit: permit)
        try ledger.returned(op, status: .success, summarySHA256: digest, accountSHA256: account, permit: permit)
        try ledger.validated(op, permit: permit)
    }
    func qualify(_ c: Context, ledger: ExecutionLedger, binding: ExecutionBinding) throws -> String {
        let account = try ledger.accountDigest("opaque synthetic record")
        let permit = try ledger.consume(.qualificationRead, binding: binding)
        try roundtrip(.accountStatus, ledger: ledger, permit: permit)
        try roundtrip(.userRecordID, ledger: ledger, permit: permit, account: account)
        try ledger.finishQualification(accountSHA256: account, permit: permit); return account
    }
    func testFullDurableQualificationAndFiveStagesWithTenAccountChecks() throws {
        let c = try context(); var ledger: ExecutionLedger? = try enroll(c); let b = binding(c)
        let account = try qualify(c, ledger: ledger!, binding: b)
        let permit = try ledger!.consume(.developmentBatch, binding: batchBinding(b, account: account))
        for stage in LedgerStage.allCases {
            try roundtrip(.accountCheckBefore(stage), ledger: ledger!, permit: permit, account: account)
            try ledger!.intent(.transport(stage), permit: permit)
            try ledger!.returned(.transport(stage), status: .success, summarySHA256: digest, permit: permit)
            XCTAssertThrowsError(try ledger!.validated(.transport(stage), permit: permit))
            try roundtrip(.accountCheckAfter(stage), ledger: ledger!, permit: permit, account: account)
            try ledger!.validated(.transport(stage), permit: permit)
        }
        try ledger!.finishBatch(permit: permit); XCTAssertFalse(ledger!.hasUnresolvedExecutions)
        ledger = nil; let reopened = try c.open(); XCTAssertFalse(reopened.hasUnresolvedExecutions)
        XCTAssertThrowsError(try reopened.consume(.qualificationRead, binding: b))
        XCTAssertThrowsError(try reopened.consume(.developmentBatch, binding: batchBinding(b, account: account)))
    }
    func testFirstQualificationNeedsConsumedPermitAndStrictOrder() throws {
        let c = try context(), ledger = try enroll(c), b = binding(c)
        XCTAssertThrowsError(try ledger.consume(.developmentBatch, binding: batchBinding(b, account: digest)))
        let permit = try ledger.consume(.qualificationRead, binding: b)
        XCTAssertThrowsError(try ledger.intent(.userRecordID, permit: permit))
        try ledger.intent(.accountStatus, permit: permit)
        XCTAssertThrowsError(try ledger.intent(.accountStatus, permit: permit))
        XCTAssertThrowsError(try ledger.intent(.userRecordID, permit: permit))
        XCTAssertThrowsError(try ledger.validated(.accountStatus, permit: permit))
        try ledger.terminateUnknown(reason: .interrupted, permit: permit)
        XCTAssertThrowsError(try ledger.intent(.accountStatus, permit: permit))
    }
    func testReplayCannotChangeOwnerWindowPlanOrOutput() throws {
        let c = try context(), ledger = try enroll(c), b = binding(c)
        let permit = try ledger.consume(.qualificationRead, binding: b)
        try ledger.terminateUnknown(reason: .cancelled, permit: permit)
        for changed in [binding(c, run: b.run, dataset: b.dataset, owner: String(repeating: "c", count: 64)),
                        binding(c, run: b.run, dataset: b.dataset, end: c.clock.wall + 90_000),
                        binding(c, run: b.run, dataset: UUID(), plan: String(repeating: "d", count: 64)),
                        binding(c, run: UUID(), dataset: b.dataset, plan: String(repeating: "e", count: 64))] {
            XCTAssertThrowsError(try ledger.consume(.qualificationRead, binding: changed))
        }
        let other = c.parent.appendingPathComponent("different-output")
        XCTAssertThrowsError(try ExecutionLedger.openForTesting(root: other, anchorStore: c.store, clock: c.clock))
        XCTAssertThrowsError(try ExecutionLedger.enrollForTesting(root: other, anchorStore: c.store, clock: c.clock, ownerDecisionSHA256: digest))
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.path))
    }
    func testSameProcessAndIndependentProcessCannotAcquireHeldLock() throws {
        let c = try context(), ledger = try enroll(c)
        XCTAssertThrowsError(try c.open())
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import fcntl,os,sys\nf=os.open(sys.argv[1],os.O_RDWR)\ntry: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)\nexcept BlockingIOError: sys.exit(9)\nsys.exit(0)", c.root.appendingPathComponent("guard.lock").path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 9)
        withExtendedLifetime(ledger) {}
    }
    func testLockReplacementAndSymlinkRootReject() throws {
        let c = try context(), ledger = try enroll(c), lock = c.root.appendingPathComponent("guard.lock")
        try FileManager.default.moveItem(at: lock, to: c.root.appendingPathComponent("old-lock"))
        FileManager.default.createFile(atPath: lock.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        XCTAssertThrowsError(try ledger.consume(.qualificationRead, binding: binding(c)))
        let link = c.parent.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: c.root)
        XCTAssertThrowsError(try ExecutionLedger.openForTesting(root: link, anchorStore: c.store, clock: c.clock))
    }
    func testRootReplacementEvenWithCopiedJournalAndAnchorRejects() throws {
        let c = try context(); var ledger: ExecutionLedger? = try enroll(c)
        _ = try ledger!.consume(.qualificationRead, binding: binding(c)); ledger = nil
        let old = c.parent.appendingPathComponent("old")
        try FileManager.default.moveItem(at: c.root, to: old); try FileManager.default.copyItem(at: old, to: c.root)
        XCTAssertThrowsError(try c.open())
    }
    func testMissingAnchorJournalAndCorruptAnchorFailClosedWithoutRepair() throws {
        for fault in ["anchor-missing", "anchor-corrupt", "journal-missing", "journal-corrupt"] {
            let c = try context(); var ledger: ExecutionLedger? = try enroll(c)
            _ = try ledger!.consume(.qualificationRead, binding: binding(c)); ledger = nil
            let file = c.root.appendingPathComponent("00000001.json")
            switch fault {
            case "anchor-missing": c.store.bytes = nil
            case "anchor-corrupt": c.store.bytes = Data("bad".utf8)
            case "journal-missing": try FileManager.default.removeItem(at: file)
            default: try Data("bad".utf8).write(to: file)
            }
            let before = c.store.bytes
            XCTAssertThrowsError(try c.open()); XCTAssertEqual(c.store.bytes, before)
            XCTAssertThrowsError(try enroll(c))
        }
    }
    func testJournalDurableButAnchorUpdateFailurePoisonsAndNeverRetries() throws {
        let c = try context(); var ledger: ExecutionLedger? = try enroll(c); let old = c.store.bytes
        c.store.failNextReplace = true
        XCTAssertThrowsError(try ledger!.consume(.qualificationRead, binding: binding(c)))
        XCTAssertEqual(c.store.bytes, old)
        XCTAssertTrue(FileManager.default.fileExists(atPath: c.root.appendingPathComponent("00000001.json").path))
        XCTAssertThrowsError(try ledger!.consume(.qualificationRead, binding: binding(c)))
        ledger = nil; XCTAssertThrowsError(try c.open())
    }
    func testAnchorCommittedThenJournalChangedBeforePermitReturnRejects() throws {
        let c = try context(), ledger = try enroll(c)
        c.store.afterReplace = { try Data("tampered after commit".utf8).write(to: c.root.appendingPathComponent("00000001.json")) }
        XCTAssertThrowsError(try ledger.consume(.qualificationRead, binding: binding(c)))
        XCTAssertThrowsError(try ledger.accountDigest("synthetic"))
    }
    func testCrashAfterIntentIsUnresolvedAndCannotResumeOrStartNewRun() throws {
        let c = try context(); var ledger: ExecutionLedger? = try enroll(c); let b = binding(c)
        let permit = try ledger!.consume(.qualificationRead, binding: b)
        try ledger!.intent(.accountStatus, permit: permit); ledger = nil
        let reopened = try c.open(); XCTAssertTrue(reopened.hasUnresolvedExecutions)
        XCTAssertThrowsError(try reopened.consume(.qualificationRead, binding: b))
        XCTAssertThrowsError(try reopened.consume(.qualificationRead, binding: binding(c, plan: String(repeating: "e", count: 64))))
        XCTAssertThrowsError(try reopened.returned(.accountStatus, status: .success, summarySHA256: digest, permit: permit))
    }
    func testCancellationLateObservationCannotAdvanceOrAttachToAnotherPermit() throws {
        let c = try context(), ledger = try enroll(c), permit = try ledger.consume(.qualificationRead, binding: binding(c))
        let id = try ledger.intent(.accountStatus, permit: permit)
        try ledger.recordObservation(operationID: id, event: .cancellationRequested, summarySHA256: digest, permit: permit)
        try ledger.terminateUnknown(reason: .cancelled, permit: permit)
        try ledger.recordObservation(operationID: id, event: .lateCallback, summarySHA256: digest, permit: permit)
        XCTAssertThrowsError(try ledger.returned(.accountStatus, status: .success, summarySHA256: digest, permit: permit))
        XCTAssertThrowsError(try ledger.recordObservation(operationID: UUID(), event: .lateCallback, summarySHA256: digest, permit: permit))
        let next = try ledger.consume(.qualificationRead, binding: binding(c, plan: String(repeating: "f", count: 64)))
        XCTAssertThrowsError(try ledger.recordObservation(operationID: id, event: .lateCallback, summarySHA256: digest, permit: next))
    }
    func testWrongAccountCannotValidateAndExpiredWindowStillPreservesReturns() throws {
        let c = try context(), ledger = try enroll(c), b = binding(c)
        let account = try qualify(c, ledger: ledger, binding: b)
        let permit = try ledger.consume(.developmentBatch, binding: batchBinding(b, account: account))
        try ledger.intent(.accountCheckBefore(.zoneProbe), permit: permit)
        try ledger.returned(.accountCheckBefore(.zoneProbe), status: .success, summarySHA256: digest, accountSHA256: digest, permit: permit)
        XCTAssertThrowsError(try ledger.validated(.accountCheckBefore(.zoneProbe), permit: permit))
        try ledger.terminateUnknown(reason: .accountChanged, permit: permit)
        let nextBinding = binding(c, plan: String(repeating: "d", count: 64))
        let next = try ledger.consume(.qualificationRead, binding: nextBinding)
        try ledger.intent(.accountStatus, permit: next); c.clock.wall = nextBinding.windowEndMS + 1
        try ledger.returned(.accountStatus, status: .success, summarySHA256: digest, permit: next)
        XCTAssertThrowsError(try ledger.validated(.accountStatus, permit: next))
        try ledger.terminateUnknown(reason: .expired, permit: next)
    }
    func testFailureAndUnknownReturnNeverValidateOrStartNextRequest() throws {
        for status in [LedgerReturnStatus.failure, .unknown] {
            let c = try context(), ledger = try enroll(c), permit = try ledger.consume(.qualificationRead, binding: binding(c))
            try ledger.intent(.accountStatus, permit: permit)
            try ledger.returned(.accountStatus, status: status, summarySHA256: digest, permit: permit)
            XCTAssertThrowsError(try ledger.validated(.accountStatus, permit: permit))
            XCTAssertThrowsError(try ledger.intent(.userRecordID, permit: permit))
            try ledger.terminateUnknown(reason: .transportFailed, permit: permit)
        }
    }
    func testAccountHMACStablePrivateDomainAndNeverStoredPlaintext() throws {
        let c = try context(); var ledger: ExecutionLedger? = try enroll(c)
        let opaque = "synthetic-account-record-name", a = try ledger!.accountDigest(opaque)
        XCTAssertNotEqual(a, digest); XCTAssertEqual(a.count, 64)
        XCTAssertThrowsError(try ledger!.accountDigest("")); XCTAssertThrowsError(try ledger!.accountDigest(String(repeating: "a", count: 1_025)))
        ledger = nil; let reopened = try c.open(); XCTAssertEqual(try reopened.accountDigest(opaque), a)
        let other = try context(), second = try enroll(other); XCTAssertNotEqual(try second.accountDigest(opaque), a)
        XCTAssertFalse(String(decoding: c.store.bytes!, as: UTF8.self).contains(opaque))
    }
    func testWallAndMonotonicClockRollbackCannotGrantNewIntent() throws {
        for wall in [true, false] {
            let c = try context(), ledger = try enroll(c), permit = try ledger.consume(.qualificationRead, binding: binding(c))
            if wall { c.clock.wall -= 1 } else { c.clock.uptime -= 1 }
            XCTAssertThrowsError(try ledger.intent(.accountStatus, permit: permit))
            try ledger.terminateUnknown(reason: .expired, permit: permit)
        }
    }
    func testValidAnchorWithTruncatedOrReorderedJournalCannotRollback() throws {
        for truncate in [true, false] {
            let c = try context(); var ledger: ExecutionLedger? = try enroll(c)
            let permit = try ledger!.consume(.qualificationRead, binding: binding(c))
            try ledger!.intent(.accountStatus, permit: permit); ledger = nil
            let first = c.root.appendingPathComponent("00000001.json"), second = c.root.appendingPathComponent("00000002.json")
            if truncate { try FileManager.default.removeItem(at: second) }
            else { let a = try Data(contentsOf: first), b = try Data(contentsOf: second); try b.write(to: first); try a.write(to: second) }
            XCTAssertThrowsError(try c.open())
        }
    }
    func testFrozenWallCannotExtendWindowPastMonotonicDeadline() throws {
        let c = try context(), ledger = try enroll(c), b = binding(c)
        let permit = try ledger.consume(.qualificationRead, binding: b)
        XCTAssertEqual(try ledger.binding(for: permit, requiring: .qualificationRead), b)
        XCTAssertThrowsError(try ledger.binding(for: permit, requiring: .developmentBatch))
        c.clock.uptime += 61_000_000_000
        XCTAssertThrowsError(try ledger.intent(.accountStatus, permit: permit))
        XCTAssertThrowsError(try ledger.binding(for: permit, requiring: .qualificationRead))
        try ledger.terminateUnknown(reason: .expired, permit: permit)
    }
    func testWallMonotonicDriftRejectsEvenBeforeEnd() throws {
        let c = try context(), ledger = try enroll(c), b = binding(c)
        let permit = try ledger.consume(.qualificationRead, binding: b)
        c.clock.uptime += 6_000_000_000
        XCTAssertThrowsError(try ledger.intent(.accountStatus, permit: permit))
        try ledger.terminateUnknown(reason: .expired, permit: permit)
    }

    func testAbruptSubprocessExitPreservesConsumedAndIntentOrRejectsCommitGap() throws {
        let parent = try context().parent
        let source = parent.appendingPathComponent("LedgerCrashChild.swift")
        let helper = #"""
        import Foundation
        import Darwin
        @MainActor final class FileAnchor: ExecutionAnchorStore {
            let path: URL
            let interrupt: Bool
            init(_ path: URL, interrupt: Bool) { self.path = path; self.interrupt = interrupt }
            func load() throws -> Data? { FileManager.default.fileExists(atPath: path.path) ? try Data(contentsOf: path) : nil }
            func save(_ bytes: Data) throws {
                let fd = open(path.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
                guard fd >= 0 else { throw LedgerFailure.io }; defer { close(fd) }
                try bytes.withUnsafeBytes { b in
                    guard write(fd, b.baseAddress, b.count) == b.count, fsync(fd) == 0 else { throw LedgerFailure.io }
                }
                let dir = open(path.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY)
                guard dir >= 0 else { throw LedgerFailure.io }; defer { close(dir) }
                guard fsync(dir) == 0 else { throw LedgerFailure.io }
            }
            func create(_ bytes: Data) throws { guard try load() == nil else { throw LedgerFailure.anchorFailure }; try save(bytes) }
            func replace(expected: Data, with bytes: Data) throws {
                guard try load() == expected else { throw LedgerFailure.anchorFailure }
                if interrupt { _exit(74) }
                try save(bytes)
            }
        }
        @main struct CrashChild {
            @MainActor static func main() throws {
                let parent = URL(fileURLWithPath: CommandLine.arguments[1]), cut = CommandLine.arguments[2]
                let store = FileAnchor(parent.appendingPathComponent("anchor.json"), interrupt: cut == "gap")
                let ledger = try ExecutionLedger.enrollForTesting(root: parent.appendingPathComponent("guard"), anchorStore: store,
                    clock: SystemLedgerClock(), ownerDecisionSHA256: String(repeating: "a", count: 64))
                let now = Int64(Date().timeIntervalSince1970 * 1000), d = String(repeating: "a", count: 64)
                let binding = ExecutionBinding(ownerWindow: UUID(), approvalInputSHA256: d, ownerDecisionSHA256: d, windowStartMS: now - 1000, windowEndMS: now + 60000,
                    planSHA256: d, run: UUID(), dataset: UUID(), schemaSHA256: "6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003",
                    binarySHA256: d, codeDirectoryHash: String(repeating: "b", count: 40), profileSHA256: d, packagingReceiptSHA256: d, sourcePinsSHA256: d,
                    osUserID: getuid(), osSessionSHA256: d, ownerConfirmedAccountSessionSHA256: d, accountSHA256: nil)
                let permit = try ledger.consume(.qualificationRead, binding: binding)
                if cut == "intent" { try ledger.intent(.accountStatus, permit: permit) }
                _exit(73)
            }
        }
        """#
        try Data(helper.utf8).write(to: source)
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sdk = package.appendingPathComponent("Sources/FormalDevelopmentSDK")
        let names = ["ExecutionLedger.swift", "ExecutionLedgerTypes.swift", "ExecutionLedgerFiles.swift", "ExecutionAnchorStore.swift"]
        let binary = parent.appendingPathComponent("ledger-crash-child")
        let build = Process(); build.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        build.arguments = ["swiftc", "-parse-as-library"] + names.map { sdk.appendingPathComponent($0).path } + [source.path, "-o", binary.path]
        let log = parent.appendingPathComponent("build.log")
        FileManager.default.createFile(atPath: log.path, contents: Data())
        let output = try FileHandle(forWritingTo: log); build.standardOutput = output; build.standardError = output
        try build.run(); build.waitUntilExit(); try output.close(); XCTAssertEqual(build.terminationStatus, 0)
        guard build.terminationStatus == 0 else { return }
        for cut in ["consumed", "intent", "gap"] {
            let fixture = parent.appendingPathComponent(cut)
            try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let child = Process(); child.executableURL = binary; child.arguments = [fixture.path, cut]
            try child.run(); child.waitUntilExit(); XCTAssertEqual(child.terminationStatus, cut == "gap" ? 74 : 73)
            let store = FakeExecutionAnchor(); store.bytes = try Data(contentsOf: fixture.appendingPathComponent("anchor.json"))
            let root = fixture.appendingPathComponent("guard"), clock = FakeExecutionClock()
            clock.wall = Int64(Date().timeIntervalSince1970 * 1_000)
            let snapshot = try Data(contentsOf: root.appendingPathComponent("00000001.json"))
            if cut == "gap" {
                XCTAssertThrowsError(try ExecutionLedger.openForTesting(root: root, anchorStore: store, clock: clock))
            } else {
                let recovered = try ExecutionLedger.openForTesting(root: root, anchorStore: store, clock: clock)
                XCTAssertTrue(recovered.hasUnresolvedExecutions)
                let dummy = Context(parent: fixture, root: root, store: store, clock: clock)
                XCTAssertThrowsError(try recovered.consume(.qualificationRead, binding: binding(dummy)))
            }
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("00000001.json")), snapshot)
        }
    }

    func testOwnerWindowAndApprovalInputCannotBeReusedWithNewPlanAndIDs() throws {
        let c = try context(), ledger = try enroll(c), b = binding(c)
        let permit = try ledger.consume(.qualificationRead, binding: b)
        try ledger.terminateUnknown(reason: .cancelled, permit: permit)
        XCTAssertThrowsError(try ledger.consume(.qualificationRead,
            binding: binding(c, plan: String(repeating: "c", count: 64), window: b.ownerWindow)))
        XCTAssertThrowsError(try ledger.consume(.qualificationRead,
            binding: binding(c, plan: String(repeating: "d", count: 64), approval: b.approvalInputSHA256)))
        XCTAssertThrowsError(try ledger.consume(.qualificationRead, binding: binding(c, end: c.clock.wall + 900_001)))
    }
    func testReopeningAfterQualificationCannotResetMonotonicWindow() throws {
        let c = try context(); var ledger: ExecutionLedger? = try enroll(c); let b = binding(c)
        let account = try qualify(c, ledger: ledger!, binding: b); ledger = nil
        c.clock.uptime += 61_000_000_000 // wall deliberately frozen within the apparent window
        let reopened = try c.open()
        XCTAssertThrowsError(try reopened.consume(.developmentBatch, binding: batchBinding(b, account: account)))
    }

    func testRecreatedLockCannotLetSecondOpenerBypassOriginalHeldLock() throws {
        let c = try context(), held = try enroll(c), lock = c.root.appendingPathComponent("guard.lock")
        try FileManager.default.removeItem(at: lock)
        FileManager.default.createFile(atPath: lock.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        XCTAssertThrowsError(try c.open())
        XCTAssertThrowsError(try held.consume(.qualificationRead, binding: binding(c)))
    }

}
