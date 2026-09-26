import Foundation

// Uses the production staging implementation in a separate process, without an app store.
@main
struct CaptureStagingTerminationFixture {
    static func main() throws {
        let arguments = CommandLine.arguments
        let root = URL(fileURLWithPath: arguments[2], isDirectory: true)
        if arguments[1] == "hold" {
            let session = try CaptureStagingSession(root: root)
            try Data("Unpublished synthetic content".utf8).write(to: session.directory.appendingPathComponent("copy"))
            FileHandle.standardOutput.write(Data((session.directory.lastPathComponent + "\n").utf8))
            withExtendedLifetime(session) {
                while true { Thread.sleep(forTimeInterval: 60) }
            }
        } else {
            let expected = Int(arguments[3])!
            let count = try CaptureStagingSession.reclaimAbandoned(root: root)
            guard count == expected else { throw CaptureError.invalidPayload }
            print("reclaimed=\(count), expected=\(expected)")
        }
    }
}
