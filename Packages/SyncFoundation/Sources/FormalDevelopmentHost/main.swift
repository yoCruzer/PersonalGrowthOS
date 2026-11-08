import Foundation
import FormalDevelopmentSDK

// Cloud operations require the explicit canonical Owner-window production entry.
// Offline inspect commands remain separate and cannot manufacture that authority.
let arguments = Array(CommandLine.arguments.dropFirst())
let fixtureOnly = arguments == ["inspect-fixture"]
let runtimeOnly = arguments.count == 2 && arguments.first == "inspect-runtime"
let exportOnly = arguments.count == 2 && arguments.first == "export-run"
let guarded = arguments.count == 3 && ["enroll-guard", "run-approved", "closeout-unknown"].contains(arguments[0])
guard exportOnly || guarded || fixtureOnly || runtimeOnly || (arguments.count == 4 && arguments.first == "inspect") else {
    FileHandle.standardError.write(Data("usage: FormalDevelopmentHost inspect PLAN_DIR EXPECTED_SHA NEW_OUTPUT_DIR | inspect-fixture | inspect-runtime BASE64_REQUEST | export-run RUN_UUID | enroll-guard BASE64_APPROVAL EXPECTED_SHA | run-approved BASE64_APPROVAL EXPECTED_SHA | closeout-unknown BASE64_APPROVAL EXPECTED_SHA\n".utf8)); exit(64)
}
do {
    if exportOnly {
        guard let run = UUID(uuidString: arguments[1]) else { exit(64) }
        let bytes = try FormalDevelopmentEvidenceExport.export(run: run)
        FileHandle.standardOutput.write(bytes + Data([10])); exit(0)
    } else if guarded {
        guard arguments[1].utf8.count <= 180_000, let bytes = Data(base64Encoded: arguments[1]) else { exit(64) }
        let report: Data
        if arguments[0] == "enroll-guard" {
            report = try FormalDevelopmentGuardedExecution.enroll(approval: bytes, expectedSHA256: arguments[2])
        } else if arguments[0] == "closeout-unknown" {
            report = try FormalDevelopmentGuardedExecution.closeoutUnknown(approval: bytes, expectedSHA256: arguments[2])
        } else {
            report = try await FormalDevelopmentGuardedExecution.run(approval: bytes, expectedSHA256: arguments[2]) {
                FileHandle.standardError.write(Data("FATAL_EXECUTION_OR_EVIDENCE_UNKNOWN\n".utf8)); exit(74)
            }
        }
        FileHandle.standardOutput.write(report + Data([10])); exit(0)
    } else if runtimeOnly {
        guard arguments[1].utf8.count <= 180_000, let bytes = Data(base64Encoded: arguments[1]) else { exit(64) }
        let report = try FormalDevelopmentRuntimeInspection.inspect(bytes)
        FileHandle.standardOutput.write(report + Data([10]))
        let value = try JSONSerialization.jsonObject(with: report) as? [String: Any]
        exit(value?["status"] as? String == "SELF_QUALIFICATION_PASS" ? 0 : 2)
    } else if fixtureOnly {
        let report = try FormalDevelopmentLockedHost.inspectFixture()
        FileHandle.standardOutput.write(report + Data([10]))
    } else {
        try FormalDevelopmentLockedHost.inspect(planURL: URL(fileURLWithPath: arguments[1]),
            expectedSHA256: arguments[2], output: URL(fileURLWithPath: arguments[3]))
        print("NOT_READY EXTERNAL_GATE_NOT_COMPLETE; networkOperations=0")
    }
    exit(2)
} catch {
    FileHandle.standardError.write(Data((guarded ? "GUARDED_EXECUTION_FAILED\n" : "OFFLINE_VALIDATION_FAILED\n").utf8)); exit(1)
}
