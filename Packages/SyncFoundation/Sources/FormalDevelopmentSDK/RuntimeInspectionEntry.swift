import Foundation

private struct OfflineRuntimeInspectionRequest: Codable {
    let mode: String
    let runtime: ApprovedRuntimeBinding
    let packagingReceipt: Data
    let sourcePins: Data
}
private struct OfflineRuntimeInspectionReport: Encodable {
    let mode = "OFFLINE_ONLY"
    let operation = "RUNNING_SELF_QUALIFICATION"
    let status: String
    let rejection: String?
    let diagnosticStage: String?
    let diagnosticStatus: Int32?
    let signatureProfileDeviceVerified: Bool
    let osSessionVerified: Bool
    let applicationSupportParentVerified: Bool
    let networkOperations = 0
    let networkAuthorized = false
    let ownerApprovalVerified = false
    let accountQualification = "NOT_RUN"
    let actualServiceAccess = "NOT_RUN"
    let p0Passed = false
}

/// Data-only offline entry. It returns a report, never a runtime capability.
/// No paths, caller code, CloudKit container or account operations are accepted.
public enum FormalDevelopmentRuntimeInspection {
    public static func inspect(_ request: Data) throws -> Data {
        var runtimeVerified = false, osVerified = false
        do {
            guard request.count <= 131_072 else { throw OwnerWindowError.malformed }
            let input = try JSONDecoder().decode(OfflineRuntimeInspectionRequest.self, from: request)
            guard try json(input) == request, input.mode == "OFFLINE_RUNTIME_INSPECTION",
                  input.packagingReceipt.count <= 65_536, input.sourcePins.count <= 65_536 else {
                throw OwnerWindowError.malformed
            }
            _ = try RuntimeSigningInspector.inspect(expected: input.runtime.expectation(),
                packagingReceipt: input.packagingReceipt, sourcePins: input.sourcePins)
            runtimeVerified = true
            let session = try OSExecutionSession.current(); try session.recheck(); osVerified = true
            _ = try GuardedExecutionPaths.inspectApplicationSupport()
            return try json(OfflineRuntimeInspectionReport(status: "SELF_QUALIFICATION_PASS",
                rejection: nil, diagnosticStage: nil, diagnosticStatus: nil, signatureProfileDeviceVerified: true, osSessionVerified: true, applicationSupportParentVerified: true))
        } catch {
            let diagnostic = error as? RuntimeSigningDiagnosticFailure
            let rejection = diagnostic?.reason.rawValue ?? (error as? RuntimeSigningError)?.rawValue ?? (error as? GuardedEntryError)?.rawValue ?? (runtimeVerified ? "OS_APPLICATION_SUPPORT_UNAVAILABLE" : "OFFLINE_RUNTIME_INPUT_REJECTED")
            return try json(OfflineRuntimeInspectionReport(status: "NOT_READY",
                rejection: rejection, diagnosticStage: diagnostic?.stage.rawValue,
                diagnosticStatus: diagnostic?.status, signatureProfileDeviceVerified: runtimeVerified,
                osSessionVerified: osVerified, applicationSupportParentVerified: false))
        }
    }
}
