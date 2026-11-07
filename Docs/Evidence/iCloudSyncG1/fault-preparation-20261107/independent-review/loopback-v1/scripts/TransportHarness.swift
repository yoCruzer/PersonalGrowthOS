import Foundation
import CryptoKit

enum LabError: Error { case blocked, limit, invalidWire }
public struct DevelopmentAuthorization { let isEnabled: Bool }
func isHash(_ s: String) -> Bool { s.count == 64 && s.allSatisfy { "0123456789abcdef".contains($0) } }
func digest(_ b: Data) -> String { SHA256.hash(data:b).map {String(format:"%02x",$0)}.joined() }
struct ManualProbePlan { static func decode(_ b:Data) throws -> ManualProbePlan { throw LabError.blocked } } // plan decode not under test
final class ProbeLoopbackSession: NSObject, URLSessionTaskDelegate {
 func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum DevelopmentProbe {
 static func loopbackURL(_ v:String) throws -> URL {
  guard let p=URLComponents(string:v),p.scheme=="http",p.host=="127.0.0.1",let port=p.port,(1024...65535).contains(port),p.user==nil,p.password==nil,p.query==nil,p.fragment==nil,p.path.isEmpty || p.path=="/",let u=p.url else {throw LabError.invalidWire};return u
 }
}
@main struct Harness {
 @MainActor static func main() {
  do {
   let t=try ProbeWindowTransport(address:CommandLine.arguments[1],token:String(repeating:"a",count:64),launchID:"12345678-1234-1234-1234-123456789ABC",authorization:DevelopmentAuthorization(isEnabled:true))
   try t.send("report",bytes:Data("{\"synthetic\":true}".utf8));print("ACCEPTED")
  } catch {print("REJECTED")}
 }
}
