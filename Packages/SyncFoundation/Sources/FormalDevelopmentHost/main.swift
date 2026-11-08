import Foundation
import FormalDevelopmentSDK

// Deliberately cannot launch CloudKit. Exit 2 is the expected external gate result.
let arguments = Array(CommandLine.arguments.dropFirst())
let fixtureOnly = arguments == ["inspect-fixture"]
guard fixtureOnly || (arguments.count == 4 && arguments.first == "inspect") else {
    FileHandle.standardError.write(Data("usage: FormalDevelopmentHost inspect PLAN_DIR EXPECTED_SHA NEW_OUTPUT_DIR | inspect-fixture\n".utf8)); exit(64)
}
do {
    if fixtureOnly {
        let report = try FormalDevelopmentLockedHost.inspectFixture()
        FileHandle.standardOutput.write(report + Data([10]))
    } else {
        try FormalDevelopmentLockedHost.inspect(planURL: URL(fileURLWithPath: arguments[1]),
            expectedSHA256: arguments[2], output: URL(fileURLWithPath: arguments[3]))
        print("NOT_READY EXTERNAL_GATE_NOT_COMPLETE; networkOperations=0")
    }
    exit(2)
} catch {
    FileHandle.standardError.write(Data("OFFLINE_VALIDATION_FAILED\n".utf8)); exit(1)
}
