#if DEBUG
import Foundation

private final class ProbeWindowReply: @unchecked Sendable {
    private let lock = NSLock()
    private var accepted = false
    func set(_ value: Bool) { lock.lock(); accepted = value; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return accepted }
}

/// Explicit launcher-only loopback output. A deliberate exit cannot proceed
/// until the receiver confirms the exact bytes were durably published.
@MainActor public final class ProbeWindowTransport {
    let endpoint: URL
    let token: String
    let launchID: String
    public init(address: String, token: String, launchID: String, authorization: DevelopmentAuthorization) throws {
        guard authorization.isEnabled, isHash(token), UUID(uuidString: launchID) != nil else { throw LabError.blocked }
        endpoint = try DevelopmentProbe.loopbackURL(address)
        self.token = token; self.launchID = launchID
    }
    public static func planBytes(_ encoded: String) throws -> Data {
        guard encoded.utf8.count <= 349_528, let bytes = Data(base64Encoded: encoded) else { throw LabError.limit }
        _ = try ManualProbePlan.decode(bytes)
        return bytes
    }
    public func send(_ kind: String, bytes: Data) throws {
        guard ["observation", "report", "failure"].contains(kind), bytes.count <= 32_000_000 else { throw LabError.limit }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5; configuration.timeoutIntervalForResource = 6
        configuration.connectionProxyDictionary = [:]; configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: ProbeLoopbackSession(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint.appendingPathComponent(kind))
        request.httpMethod = "POST"; request.httpBody = bytes
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(launchID, forHTTPHeaderField: "X-SyncLab-Launch")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let semaphore = DispatchSemaphore(value: 0), reply = ProbeWindowReply(), expected = digest(bytes)
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
                  let data, data.count <= 1024,
                  let value = try? JSONDecoder().decode([String: String].self, from: data),
                  value["acceptedSHA256"] == expected else { return }
            reply.set(true)
        }
        task.resume()
        // URLSession's completion queue is independent of MainActor. This bounded
        // wait is intentional inside synchronous commit/SDK fault hooks only.
        guard semaphore.wait(timeout: .now() + 7) == .success, reply.get() else { task.cancel(); throw LabError.blocked }
    }
}
#endif
