import Foundation
import SyncLab
@main struct Probe {
 @MainActor static func main() throws {
  for count in [18, 22, 26, 160] {
   var facts: [Mutation] = []
   for i in 0..<count { facts.append(Mutation(id: "m" + String(i), object: "dag", parents: i < 2 ? [] : ["m" + String(i-1), "m" + String(i-2)], text: "SYNTHETIC")) }
   let start = Date(); _ = try Graph(facts).project("dag")
   print("DAG_N=\(count),SECONDS=\(Date().timeIntervalSince(start))")
  }
  let base = FileManager.default.temporaryDirectory.appendingPathComponent("G1Review-" + UUID().uuidString)
  let binding = try Binding(accountHash: digest(Data("SYNTHETIC-A".utf8)), dataset: "review")
  let s = try LabStore(base: base, binding: binding)
  let image = Data("SYNTHETIC-ORIGINAL".utf8); let hash = digest(image)
  let m = Mutation(id: "original", object: "parent", text: "", imageHash: hash, imageBytes: image.count)
  try s.save(m, image: image)
  try Data("truncated".utf8).write(to: s.imageURL(hash))
  do { try s.receiveImage(image, hash: hash, count: image.count, fields: Data(), ticket: s.epoch); print("REPAIR_SUCCEEDED") }
  catch { print("REPAIR_BLOCKED_BY_EXISTING_CORRUPT_IMAGE") }
  let dest = try LabStore(base: base, binding: Binding(accountHash: digest(Data("SYNTHETIC-B".utf8)), dataset: "review"))
  let encoder = JSONEncoder();encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  try dest.receiveEnvelope(Envelope(object: "parent", mutations: [m]).encoded(), key: "object-parent", fields: Data(), ticket: dest.epoch)
  let child = Mutation(id: "child", object: "link", requires: ["parent"], text: "SYNTHETIC-LINK")
  try dest.receiveEnvelope(Envelope(object: "link", mutations: [child]).encoded(), key: "object-link", fields: Data(), ticket: dest.epoch)
  let p = try dest.projections()
  try dest.receiveImage(image, hash: hash, count: image.count, fields: Data(), ticket: dest.epoch)
  let repaired = try dest.projections()
  print("REPAIRED_PARENT=\(repaired["parent"]!.state),REPAIRED_CHILD=\(repaired["link"]!.state)")
  let restoreBinding = try Binding(accountHash: digest(Data("SYNTHETIC-C".utf8)), dataset: "already-used")
  var restored: LabStore? = try LabStore(base: base, binding: restoreBinding)
  try restored!.importSnapshot(dest.exportSnapshot()); restored = nil
  let reopened = try LabStore(base: base, binding: restoreBinding)
  do { try reopened.check(reopened.epoch); print("RESTORE_NETWORK_WRONGLY_ALLOWED") }
  catch { print("RESTORE_NETWORK_BLOCKED_AFTER_REOPEN") }
  try reopened.save(Mutation(id: "local-new", object: "local", text: "SYNTHETIC-OFFLINE"))
  print("RESTORE_OFFLINE_EDIT_AND_EXPORT=\(try reopened.exportSnapshot().count > 0)")
  print("PARENT_STATE=\(p["parent"]!.state),CHILD_STATE=\(p["link"]!.state),CHILD_COMPLETE=\(p["link"]!.complete)")
 }
}
