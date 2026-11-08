import Foundation
import FormalProbeCore

public enum FormalDevelopmentLockedHost {
    /// No live flag, environment override, CKContainer or transport factory.
    /// A valid plan or ticket cannot authorize a network operation.
    public static func inspect(planURL: URL, expectedSHA256: String, output: URL) throws {
        try FormalProbeReplay.verifySchemaPin()
        let fixture = try ProbeFixture.load(from: planURL, expectedSHA256: expectedSHA256)
        let directory = try ProbeDirectory(output, create: true)
        let report: [String: Any] = ["mode": "OFFLINE_ONLY", "status": "NOT_READY", "failure": "EXTERNAL_GATE_NOT_COMPLETE",
            "planSHA256": expectedSHA256, "container": fixture.plan.container, "environment": fixture.plan.environment,
            "run": fixture.plan.run.uuidString, "dataset": fixture.plan.dataset.uuidString,
            "networkOperations": 0, "networkAuthorized": false, "p0Passed": false,
            "missingFactory": "SIGNING_ACCOUNT_ENVIRONMENT_AND_OWNER_WINDOW_AUTHORITY"]
        try directory.write("report.json", bytes: JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]))
        try directory.requirePathBinding()
    }
}
