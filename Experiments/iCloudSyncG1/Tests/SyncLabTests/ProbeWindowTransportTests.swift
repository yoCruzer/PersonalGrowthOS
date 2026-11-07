#if DEBUG
import XCTest
@testable import SyncLab

final class ProbeWindowTransportTests: XCTestCase {
    @MainActor func testEndpointAndPlanAreBoundedAndRequireAuthorization() throws {
        XCTAssertThrowsError(try ProbeWindowTransport(address: "http://127.0.0.1:12345", token: String(repeating: "a", count: 64), launchID: UUID().uuidString, authorization: .fromEnvironment()))
        for address in ["https://example.com", "http://localhost:12345", "http://127.0.0.1:12345/other", "http://user@127.0.0.1:12345"] {
            XCTAssertThrowsError(try ProbeWindowTransport(address: address, token: String(repeating: "a", count: 64), launchID: UUID().uuidString, authorization: .afterExplicitManualConsent()))
        }
        XCTAssertThrowsError(try ProbeWindowTransport.planBytes(String(repeating: "A", count: 349529)))
        XCTAssertThrowsError(try ProbeWindowTransport.planBytes(Data("{}".utf8).base64EncodedString()))
        for stage in try FaultBatch.stages(dataset: "synthetic-g1-transport-test", runID: "probe-transport-test") {
            let bytes = try canonical(stage.plan)
            XCTAssertLessThan(bytes.base64EncodedString().utf8.count, 32768)
            XCTAssertEqual(try ProbeWindowTransport.planBytes(bytes.base64EncodedString()), bytes)
        }
    }
    @MainActor func testActualURLSessionRequiresExactACKAndDoesNotRedirect() async throws {
        let script = """
import sys,json,hashlib
from pathlib import Path
from http.server import HTTPServer,BaseHTTPRequestHandler
port=Path(sys.argv[1]);mode=sys.argv[2]
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  port.with_suffix('.redirected').write_text('FOLLOWED')
  self.send_response(400);self.end_headers()
 def do_POST(self):
  data=self.rfile.read(int(self.headers['Content-Length']))
  if mode=='redirect':
   self.send_response(302);self.send_header('Location','http://127.0.0.1:'+str(self.server.server_port)+'/redirected');self.end_headers();return
  answer=json.dumps({'acceptedSHA256':hashlib.sha256(data).hexdigest() if mode=='ok' else '0'*64}).encode()
  self.send_response(200);self.send_header('Content-Length',str(len(answer)));self.end_headers();self.wfile.write(answer)
server=HTTPServer(('127.0.0.1',0),Handler)
port.write_text(str(server.server_port))
server.serve_forever()
"""
        for mode in ["ok", "wrong", "redirect"] {
            let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            let port = root.appendingPathComponent("port")
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c", script, port.path, mode]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
            defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
            for _ in 0..<150 where !FileManager.default.fileExists(atPath: port.path) { try await Task.sleep(nanoseconds: 20_000_000) }
            let number = try String(contentsOf: port)
            let transport = try ProbeWindowTransport(address: "http://127.0.0.1:" + number, token: String(repeating: "a", count: 64), launchID: UUID().uuidString, authorization: .afterExplicitManualConsent())
            let bytes = Data("{\"code\":\"WINDOW_FAILED\"}".utf8)
            if mode == "ok" { XCTAssertNoThrow(try transport.send("failure", bytes: bytes)) }
            else { XCTAssertThrowsError(try transport.send("failure", bytes: bytes)) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: port.appendingPathExtension("redirected").path))
            let binding = try Binding(accountHash: digest(Data("SYNTHETIC TRANSPORT".utf8)), dataset: "synthetic-g1-transport")
            let store = try LabStore(base: root.appendingPathComponent("store"), binding: binding)
            let journal = try ProbeFaultJournal(base: root, dataset: binding.dataset, runID: "probe-transport", source: ProbeFaultSource(commandID: "probe-command", commandDigest: digest(bytes)), transport: transport)
            if mode == "ok" { XCTAssertNoThrow(try journal.record("boundary", store: store)) }
            else { XCTAssertThrowsError(try journal.record("boundary", store: store)) }
            // Failed delivery still retains the immutable native observation.
            XCTAssertEqual(try journal.read().count, 1)
        }
    }
}
#endif
