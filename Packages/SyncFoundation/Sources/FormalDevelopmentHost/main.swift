import Foundation
import FormalDevelopmentSDK

// Deliberately cannot launch CloudKit. Exit 2 is the expected external gate result.
guard CommandLine.arguments.count == 5, CommandLine.arguments[1] == "inspect" else {
    FileHandle.standardError.write(Data("usage: FormalDevelopmentHost inspect PLAN_DIR EXPECTED_SHA NEW_OUTPUT_DIR\n".utf8)); exit(64)
}
do {
    try FormalDevelopmentLockedHost.inspect(planURL: URL(fileURLWithPath: CommandLine.arguments[2]),
        expectedSHA256: CommandLine.arguments[3], output: URL(fileURLWithPath: CommandLine.arguments[4]))
    print("NOT_READY EXTERNAL_GATE_NOT_COMPLETE; networkOperations=0"); exit(2)
} catch {
    FileHandle.standardError.write(Data("OFFLINE_VALIDATION_FAILED\n".utf8)); exit(1)
}
