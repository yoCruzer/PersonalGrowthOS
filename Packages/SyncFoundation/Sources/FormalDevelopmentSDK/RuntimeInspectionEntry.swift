import Foundation

private struct OfflineRuntimeInspectionRequest: Codable {
    let mode: String
    let runtime: ApprovedRuntimeBinding
    let packagingReceipt: Data
    let sourcePins: Data
}
private struct OfflineRuntimeInspectionReport: Encodable {
    let evidenceVersion = 2
    let mode = "OFFLINE_ONLY"
    let operation = "RUNNING_SELF_QUALIFICATION"
    let status: String
    let rejection: String?
    let diagnosticStage: String?
    let diagnosticStatus: Int32?
    // Preserve the old key as false: OS provisioning evidence is not an
    // independent exact-UDID membership check of the pinned profile.
    let signatureProfileDeviceVerified = false
    let signatureAndProfileVerified: Bool
    let operatingSystemEntitlementsValidated: Bool
    let operatingSystemCodeStatus: UInt32?
    let deviceEligibilityEvidence: String
    let exactProfileDeviceMembership = "NOT_RECHECKED_AT_RUNTIME"
    let osSessionVerified: Bool
    let applicationSupportParentVerified: Bool
    let networkOperations = 0
    let networkAuthorized = false
    let ownerApprovalVerified = false
    let accountQualification = "NOT_RUN"
    let actualServiceAccess = "NOT_RUN"
    let p0Passed = false
}

private struct AsyncInspectionObservation: Encodable {
    let phase: String
    let onMainThread: Bool
    let report: Data
}
private struct AsyncInspectionReport: Encodable {
    let mode = "OFFLINE_ASYNC_RUNTIME_DIAGNOSTIC"
    let status: String
    let observations: [AsyncInspectionObservation]
    let networkOperations = 0
    let keychainOperations = 0
    let p0Passed = false
}
private struct GuardedRejectionReport: Encodable {
    let status = "GUARDED_EXECUTION_FAILED"
    let failure: String
    let sideEffects = "NOT_INFERRED_FROM_ERROR"
    let p0Passed = false
}

public enum FormalDevelopmentFailureDiagnostics {
    /// Whitelisted codes only. Never include Error descriptions, userInfo,
    /// account/device values, paths, or an inference about prior side effects.
    public static func report(_ error: Error) throws -> Data {
        try json(GuardedRejectionReport(failure: guardedCode(error)))
    }
}

/// Data-only offline entry. It returns a report, never a runtime capability.
/// No paths, caller code, CloudKit container or account operations are accepted.
public enum FormalDevelopmentRuntimeInspection {
    /// Match the production async MainActor entry and continuation boundaries,
    /// while never constructing a CloudKit container or opening an anchor.
    @MainActor public static func inspectAsync(_ request: Data) async throws -> Data {
        var observations: [AsyncInspectionObservation] = []
        for phase in ["async-entry", "after-yield", "continuation", "after-continuation"] {
            if phase == "after-yield" { await Task.yield() }
            let bytes: Data
            if phase == "continuation" {
                bytes = try await withCheckedThrowingContinuation { continuation in
                    do { continuation.resume(returning: try inspect(request)) }
                    catch { continuation.resume(throwing: error) }
                }
            } else { bytes = try inspect(request) }
            observations.append(AsyncInspectionObservation(phase: phase, onMainThread: currentThreadIsMain(), report: bytes))
            let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            if value?["status"] as? String != "SELF_QUALIFICATION_PASS" {
                return try json(AsyncInspectionReport(status: "NOT_READY", observations: observations))
            }
        }
        return try json(AsyncInspectionReport(status: "SELF_QUALIFICATION_PASS", observations: observations))
    }
    private static func currentThreadIsMain() -> Bool { Thread.isMainThread }
    public static func inspect(_ request: Data) throws -> Data {
        var runtimeVerified = false, osVerified = false
        var codeStatus: UInt32?
        do {
            guard request.count <= 131_072 else { throw OwnerWindowError.malformed }
            let input = try JSONDecoder().decode(OfflineRuntimeInspectionRequest.self, from: request)
            guard try json(input) == request, input.mode == "OFFLINE_RUNTIME_INSPECTION",
                  input.packagingReceipt.count <= 65_536, input.sourcePins.count <= 65_536 else {
                throw OwnerWindowError.malformed
            }
            let qualification = try RuntimeSigningInspector.inspect(expected: input.runtime.expectation(),
                packagingReceipt: input.packagingReceipt, sourcePins: input.sourcePins)
            codeStatus = qualification.operatingSystemCodeStatus
            runtimeVerified = true
            let session = try OSExecutionSession.current(); try session.recheck(); osVerified = true
            _ = try GuardedExecutionPaths.inspectApplicationSupport()
            return try json(OfflineRuntimeInspectionReport(status: "SELF_QUALIFICATION_PASS",
                rejection: nil, diagnosticStage: nil, diagnosticStatus: nil, signatureAndProfileVerified: true,
                operatingSystemEntitlementsValidated: true, operatingSystemCodeStatus: codeStatus,
                deviceEligibilityEvidence: "OS_VALIDATED_RESTRICTED_ENTITLEMENTS",
                osSessionVerified: true, applicationSupportParentVerified: true))
        } catch {
            let diagnostic = error as? RuntimeSigningDiagnosticFailure
            let rejection = diagnostic?.reason.rawValue ?? (error as? RuntimeSigningError)?.rawValue ?? (error as? GuardedEntryError)?.rawValue ?? (runtimeVerified ? "OS_APPLICATION_SUPPORT_UNAVAILABLE" : "OFFLINE_RUNTIME_INPUT_REJECTED")
            return try json(OfflineRuntimeInspectionReport(status: "NOT_READY",
                rejection: rejection, diagnosticStage: diagnostic?.stage.rawValue,
                diagnosticStatus: diagnostic?.status, signatureAndProfileVerified: runtimeVerified,
                operatingSystemEntitlementsValidated: runtimeVerified, operatingSystemCodeStatus: codeStatus,
                deviceEligibilityEvidence: runtimeVerified ? "OS_VALIDATED_RESTRICTED_ENTITLEMENTS" : "NOT_VERIFIED",
                osSessionVerified: osVerified, applicationSupportParentVerified: false))
        }
    }
}
