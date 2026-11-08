import Foundation
import Darwin
import FormalProbeCore
import SyncFoundation
#if os(macOS)
import Security
#endif

enum GuardedEntryError: String, Error {
    case wrongPurpose, unsupportedPlatform, osSessionUnavailable, osSessionChanged, outputUnavailable, busy, fatalEvidence, attemptConsumed
}

/// One production attempt per process, including enrollment. No reset API.
/// This is a local lifetime fence, not a replacement for the durable ledger.
@MainActor final class ProductionAttemptLatch {
    private var consumed = false
    func check() throws { guard !consumed else { throw GuardedEntryError.attemptConsumed } }
    func consume() throws { try check(); consumed = true }
}

/// Local process/session binding only. It grants no signing or CloudKit authority.
struct OSExecutionSession: Equatable {
    let userID: UInt32
    let securitySessionID: UInt32
    let attributes: UInt32
    let bootSession: UUID
    static func validated(userID: UInt32, effectiveUserID: UInt32, securitySessionID: UInt32,
                          attributes: UInt32, bootSession: UUID) throws -> Self {
        // Fixed Mac console-test-session contract: no root or remote session.
        guard userID > 0, userID == effectiveUserID, securitySessionID != 0,
              securitySessionID != UInt32.max, securitySessionID != UInt32.max - 1,
              attributes & 0x0001 == 0, attributes & 0x1000 == 0, attributes & 0x0010 != 0 else {
            throw GuardedEntryError.osSessionUnavailable
        }
        return Self(userID: userID, securitySessionID: securitySessionID, attributes: attributes, bootSession: bootSession)
    }
    var digest: String {
        syncDigest(Data("PGOS.OSExecutionSession.v1\0\(userID)\0\(securitySessionID)\0\(attributes)\0\(bootSession.uuidString.lowercased())".utf8))
    }
    static func current() throws -> Self {
        #if os(macOS)
        var session: SecuritySessionId = 0
        var attributes: SessionAttributeBits = []
        guard SessionGetInfo(callerSecuritySession, &session, &attributes) == errSecSuccess else {
            throw GuardedEntryError.osSessionUnavailable
        }
        var bytes = [CChar](repeating: 0, count: 128), size = 128
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0,
              size > 1, size <= bytes.count, bytes[size - 1] == 0,
              let boot = UUID(uuidString: String(cString: bytes)) else { throw GuardedEntryError.osSessionUnavailable }
        return try validated(userID: getuid(), effectiveUserID: geteuid(), securitySessionID: session,
                             attributes: attributes.rawValue, bootSession: boot)
        #else
        throw GuardedEntryError.unsupportedPlatform
        #endif
    }
    func recheck() throws {
        guard try Self.current() == self else { throw GuardedEntryError.osSessionChanged }
    }
}

/// OS-selected Application Support only. Inspection never creates anything;
/// enrollment may create only its missing final component under an existing,
/// verified parent. Existing state is never repaired or permission-adjusted.
enum GuardedExecutionPaths {
    private static func selectedRoot() throws -> URL {
        let roots = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard roots.count == 1, let root = roots.first, root.isFileURL, root.path.hasPrefix("/") else {
            throw GuardedEntryError.outputUnavailable
        }
        return root
    }
    static func inspectApplicationSupport() throws -> URL { try checkedRoot(selectedRoot(), createMissingLeaf: false) }
    static func prepareEnrollmentApplicationSupport() throws { _ = try checkedRoot(selectedRoot(), createMissingLeaf: true) }

    // Internal fd primitive accepts synthetic test roots; production callers only
    // use selectedRoot() above and expose no path parameter to the CLI.
    static func checkedRoot(_ root: URL, createMissingLeaf: Bool) throws -> URL {
        let parent = root.deletingLastPathComponent(), leaf = root.lastPathComponent
        guard !leaf.isEmpty, leaf != ".", leaf != "..", parent.path != root.path else { throw GuardedEntryError.outputUnavailable }
        let parentFD = try ExecutionLedgerFiles.directory(parent)
        defer { close(parentFD) }
        var before = stat()
        guard fstat(parentFD, &before) == 0, before.st_uid == getuid() else { throw GuardedEntryError.outputUnavailable }
        var existing = stat()
        if fstatat(parentFD, leaf, &existing, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT, createMissingLeaf, mkdirat(parentFD, leaf, 0o700) == 0,
                  fsync(parentFD) == 0 else { throw GuardedEntryError.outputUnavailable }
        }
        let rootFD = try ExecutionLedgerFiles.directory(root)
        defer { close(rootFD) }
        var info = stat()
        guard fstat(rootFD, &info) == 0, info.st_uid == getuid() else { throw GuardedEntryError.outputUnavailable }
        let currentParent = try ExecutionLedgerFiles.directory(parent)
        defer { close(currentParent) }
        let currentRoot = try ExecutionLedgerFiles.directory(root)
        defer { close(currentRoot) }
        var after = stat(), final = stat()
        guard fstat(currentParent, &after) == 0, before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              fstat(currentRoot, &final) == 0, info.st_dev == final.st_dev, info.st_ino == final.st_ino,
              final.st_uid == getuid() else { throw GuardedEntryError.outputUnavailable }
        return root
    }
}

private struct GuardedEntryReport: Encodable {
    let mode: String
    let status: String
    let run: UUID
    let dataset: UUID
    let ownerWindow: UUID
    let approvalInputSHA256: String
    let planSHA256: String
    let p0Passed = false
    let independentlyReviewedCloudResult = false
    let accountAPICalls: Int
    let transportMethodInvocations: Int
    let observationPersistence = "STDOUT_DERIVED_NOT_LEDGER_ANCHORED"
    let batchObservationSHA256: String?
    let batchObservation: GuardedBatchReport?
}

/// The only production composition. No caller database, provider, path, runtime
/// boolean or fake signing capability can be supplied. A reviewed Owner decision
/// is still an external prerequisite: canonical JSON is not proof of human consent.
@MainActor public enum FormalDevelopmentGuardedExecution {
    private static var busy = false
    private static let attempt = ProductionAttemptLatch()

    /// Explicit local closeout only. No container or account provider is created.
    /// The original ledger/anchor is authenticated, never reset or re-enrolled.
    public static func closeoutUnknown(approval bytes: Data, expectedSHA256: String) throws -> Data {
        guard !busy else { throw GuardedEntryError.busy }; try attempt.check()
        busy = true; defer { busy = false }
        let (window, target) = try OwnerCloseoutApproval.validate(bytes, expectedSHA256: expectedSHA256)
        _ = try qualify(window)
        let session = try OSExecutionSession.current()
        guard session.userID == window.approval.osUserID else { throw OwnerWindowError.wrongUser }
        _ = try GuardedExecutionPaths.inspectApplicationSupport()
        try session.recheck(); try window.check(); try Task.checkCancellation()
        try attempt.consume()
        let ledger = try ExecutionLedger.openProduction()
        try session.recheck(); try window.check(); try Task.checkCancellation()
        let result = try ledger.closeoutUnknown(target: target)
        try session.recheck(); try window.check()
        return try json(LocalCloseoutReport(closeout: result))
    }

    /// Shared pure preflight. Defaults are used by the production entry; explicit
    /// time/user arguments exist only for synthetic rejection tests, not the CLI.
    static func validateApproval(_ bytes: Data, expectedSHA256: String, purpose: String,
                                 now: Date = Date(), userID: UInt32 = getuid()) throws -> ValidatedOwnerWindow {
        let window = try OwnerExecutionApproval.validate(bytes, expectedSHA256: expectedSHA256, now: now, userID: userID)
        guard window.approval.purpose == purpose else { throw GuardedEntryError.wrongPurpose }
        return window
    }
    private static func qualify(_ window: ValidatedOwnerWindow) throws -> RuntimeSigningQualification {
        try window.check(); try Task.checkCancellation()
        let owner = window.approval
        let qualification = try RuntimeSigningInspector.inspect(expected: owner.runtime.expectation(),
            packagingReceipt: owner.packagingReceipt, sourcePins: owner.sourcePins)
        try window.check(); try Task.checkCancellation()
        guard qualification.profileExpiresAt.timeIntervalSince1970 > Double(owner.expiresAt) else {
            throw RuntimeSigningError.profileExpired
        }
        return qualification
    }
    private static func output(run: UUID) throws -> URL {
        let root = try GuardedExecutionPaths.inspectApplicationSupport()
        // Runner exclusively creates this leaf and rejects existing paths/symlinks.
        // Run never creates or repairs Application Support; only explicit enrollment may create its leaf.
        return root.appendingPathComponent("com.yocruzer.PersonalGrowthOS.FormalSyncProbe.Run-" + run.uuidString.lowercased(), isDirectory: true)
    }
    private static func binding(window: ValidatedOwnerWindow, session: OSExecutionSession) throws -> ExecutionBinding {
        let owner = window.approval
        let (start, startOverflow) = owner.startsAt.multipliedReportingOverflow(by: 1_000)
        let (end, endOverflow) = owner.expiresAt.multipliedReportingOverflow(by: 1_000)
        guard !startOverflow, !endOverflow, session.userID == owner.osUserID else { throw OwnerWindowError.bindingMismatch }
        return ExecutionBinding(ownerWindow: owner.window, approvalInputSHA256: window.inputSHA256,
            ownerDecisionSHA256: owner.ownerDecisionSHA256, windowStartMS: start, windowEndMS: end,
            planSHA256: owner.planSHA256, run: owner.run, dataset: owner.dataset, schemaSHA256: owner.schemaSHA256,
            binarySHA256: owner.runtime.signedBinarySHA256, codeDirectoryHash: owner.runtime.codeDirectoryHash,
            profileSHA256: owner.runtime.profileSHA256, packagingReceiptSHA256: owner.runtime.packagingReceiptSHA256,
            sourcePinsSHA256: owner.runtime.sourcePinsSHA256, osUserID: session.userID,
            osSessionSHA256: session.digest, ownerConfirmedAccountSessionSHA256: owner.ownerSessionSHA256, accountSHA256: nil)
    }

    /// Local persistent enrollment only; this method never creates a CKContainer.
    public static func enroll(approval bytes: Data, expectedSHA256: String) throws -> Data {
        guard !busy else { throw GuardedEntryError.busy }; try attempt.check()
        busy = true; defer { busy = false }
        let window = try validateApproval(bytes, expectedSHA256: expectedSHA256, purpose: "LOCAL_GUARD_ENROLLMENT")
        _ = try qualify(window)
        let session = try OSExecutionSession.current()
        guard session.userID == window.approval.osUserID else { throw OwnerWindowError.wrongUser }
        try session.recheck(); try window.check(); try Task.checkCancellation()
        // First Keychain/state access is after canonical purpose/window and real self qualification.
        try attempt.consume()
        try GuardedExecutionPaths.prepareEnrollmentApplicationSupport()
        try session.recheck(); try window.check(); try Task.checkCancellation()
        let ledger = try ExecutionLedger.enrollProduction(ownerDecisionSHA256: window.approval.ownerDecisionSHA256)
        try session.recheck(); try window.check()
        guard !ledger.hasUnresolvedExecutions else { throw LedgerFailure.corrupt }
        return try json(GuardedEntryReport(mode: "REAL_LOCAL_GUARD_ENROLLMENT", status: "LOCAL_GUARD_ENROLLED",
            run: window.approval.run, dataset: window.approval.dataset, ownerWindow: window.approval.window,
            approvalInputSHA256: window.inputSHA256, planSHA256: window.approval.planSHA256,
            accountAPICalls: 0, transportMethodInvocations: 0, batchObservationSHA256: nil, batchObservation: nil))
    }

    /// onEvidenceFatal is notification only, never an authority/factory. CLI must
    /// terminate nonzero when notified, including after a previously returned report.
    /// No process can observe callbacks after it has exited; success is an observation
    /// at report publication, not a claim that future/remote events are impossible.
    public static func run(approval bytes: Data, expectedSHA256: String,
                           onEvidenceFatal: @escaping () -> Void) async throws -> Data {
        guard !busy else { throw GuardedEntryError.busy }; try attempt.check()
        busy = true; defer { busy = false }
        let window = try validateApproval(bytes, expectedSHA256: expectedSHA256, purpose: "FIXED_SYNTHETIC_DEVELOPMENT_BATCH")
        let qualification = try qualify(window)
        let osSession = try OSExecutionSession.current()
        let binding = try binding(window: window, session: osSession)
        let destination = try output(run: window.approval.run)
        try osSession.recheck(); try window.check(); try Task.checkCancellation()
        try attempt.consume()
        let ledger = try ExecutionLedger.openProduction()
        try osSession.recheck(); try window.check(); try Task.checkCancellation()
        let permit = try ledger.consume(.qualificationRead, binding: binding)
        var session: GuardedAccountSession?
        var fatal = false
        let runner = GuardedBatchRunner()
        func evidenceFailed() { fatal = true; session?.requestCancellation(); onEvidenceFatal() }
        do {
            try osSession.recheck(); try window.check(); try Task.checkCancellation()
            let account = try GuardedAccountSession.create(qualification: qualification, window: window,
                ledger: ledger, permit: permit, expectedBinding: binding,
                sink: { _ in throw TransportOperationFailure.evidenceNotBound }, onFailure: { _ in evidenceFailed() })
            session = account
            func recheck() throws {
                guard !fatal else { throw GuardedEntryError.fatalEvidence }
                try osSession.recheck()
                _ = try qualify(window)
                try osSession.recheck(); try account.checkEpoch()
            }
            let report = try await runner.run(window: window, ledger: ledger, qualificationPermit: permit,
                binding: binding, output: destination, accountProvider: account,
                transportFactory: { permit, binding in
                    try recheck()
                    return try account.batchTransport(ledger: ledger, permit: permit, expectedBinding: binding)
                }, runtimeRecheck: recheck, onEvidenceFatal: evidenceFailed)
            // Drain callbacks already queued before publishing the outer real-path observation.
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            guard !fatal, !runner.evidenceFatal else { throw GuardedEntryError.fatalEvidence }
            try recheck()
            return try json(GuardedEntryReport(mode: "REAL_FIXED_DEVELOPMENT_BATCH", status: "REAL_BATCH_OBSERVED_VERIFIED",
                run: window.approval.run, dataset: window.approval.dataset, ownerWindow: window.approval.window,
                approvalInputSHA256: window.inputSHA256, planSHA256: window.approval.planSHA256,
                accountAPICalls: account.apiInvocations, transportMethodInvocations: report.transportMethodInvocations,
                batchObservationSHA256: syncDigest(try json(report)), batchObservation: report))
        } catch {
            session?.requestCancellation()
            // Before runner setup, preserve the consumed permit even if construction
            // fails. A runner-terminal permit correctly rejects this second transition.
            try? ledger.terminateUnknown(reason: .validationFailed, permit: permit)
            throw error
        }
    }
}
