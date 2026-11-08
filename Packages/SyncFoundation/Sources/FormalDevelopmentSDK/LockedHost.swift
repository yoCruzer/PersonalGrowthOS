import Foundation
import Darwin
import FormalProbeCore

public enum FormalDevelopmentLockedHost {
    /// No caller paths, payloads, identifiers, ticket or transport. A fresh private
    /// directory under the system-provided process temporary directory contains
    /// only our fixed synthetic fixture and the same locked inspection report.
    /// No cleanup: failed/partial evidence remains in this unique directory.
    public static func inspectFixture() throws -> Data {
        // Canonicalize only the system-provided temporary location (macOS /var
        // is a symlink). Foundation URL resolution may preserve that alias.
        guard let path = realpath(FileManager.default.temporaryDirectory.path, nil) else { throw FormalProbeError.invalidPath }
        defer { free(path) }
        let temporary = URL(fileURLWithPath: String(cString: path), isDirectory: true)
        let root = try ProbeDirectory(temporary.appendingPathComponent("FormalDevelopmentHost-" + UUID().uuidString, isDirectory: true), create: true)
        let planURL = root.url.appendingPathComponent("plan", isDirectory: true)
        let plan = try ProbeFixture.prepare(at: planURL)
        let report = try inspect(planURL: planURL, expectedSHA256: plan.digest,
            output: root.url.appendingPathComponent("inspection", isDirectory: true))
        try root.requirePathBinding()
        return report
    }

    /// No live flag, environment override, CKContainer or transport factory.
    /// A valid plan or ticket cannot authorize a network operation.
    @discardableResult
    public static func inspect(planURL: URL, expectedSHA256: String, output: URL) throws -> Data {
        try FormalProbeReplay.verifySchemaPin()
        let fixture = try ProbeFixture.load(from: planURL, expectedSHA256: expectedSHA256)
        let directory = try ProbeDirectory(output, create: true)
        let report: [String: Any] = ["mode": "OFFLINE_ONLY", "status": "NOT_READY", "failure": "EXTERNAL_GATE_NOT_COMPLETE",
            "planSHA256": expectedSHA256, "container": fixture.plan.container, "environment": fixture.plan.environment,
            "run": fixture.plan.run.uuidString, "dataset": fixture.plan.dataset.uuidString,
            "networkOperations": 0, "networkAuthorized": false, "p0Passed": false,
            "missingFactory": "SIGNING_ACCOUNT_ENVIRONMENT_AND_OWNER_WINDOW_AUTHORITY"]
        let bytes = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        try directory.write("report.json", bytes: bytes)
        try directory.requirePathBinding()
        return bytes
    }
}
