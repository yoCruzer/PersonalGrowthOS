import Foundation
import SwiftData
import CloudKit
import CryptoKit

// Audit-only types. No application container, account lookup, or network operation.
@Model final class AuditFact {
    @Attribute(.unique) var id: String
    var value: String
    var revision: Int
    init(_ id: String, _ value: String, _ revision: Int) { self.id=id; self.value=value; self.revision=revision }
}
@Model final class AuditOutbox {
    @Attribute(.unique) var key: String
    var revision: Int
    init(_ key: String, _ revision: Int) { self.key=key; self.revision=revision }
}
@Model final class AuditCloudCompatible {
    var id: String = ""
    var body: String = ""
    init(_ id: String,_ body: String) {self.id=id;self.body=body}
}
func require(_ condition: Bool, _ label: String) {
    guard condition else { fatalError("FAIL: " + label) }
    print("PASS: " + label)
}
@main struct AuditMain {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        let root = URL(fileURLWithPath: args[2], isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let mode = args[1]
        if mode == "shape-local" || mode == "shape-cloud" {
            let schema = Schema(auditModelTypes)
            let config = ModelConfiguration("IsolatedAudit", schema:schema,
                url:root.appendingPathComponent("shape.sqlite"),
                cloudKitDatabase:mode == "shape-cloud" ? .private("iCloud.invalid.pgos.architecture.audit") : .none)
            do {
                let container = try ModelContainer(for:schema,configurations:[config])
                require(container.schema.entities.count == 39, "V16 shape has 39 native entities")
                require(mode == "shape-local", "local-only configuration opens without CloudKit")
            } catch {
                guard mode == "shape-cloud" else { throw error }
                print("EXPECTED_CLOUD_OPEN_REJECTION: \(error)")
                // Framework's detailed model-validation error is captured on stderr.
            }
            return
        }
        if mode == "compatible-local" {
            let config=ModelConfiguration(url:root.appendingPathComponent("compatible.sqlite"),cloudKitDatabase:.none)
            let c=try ModelContainer(for:AuditCloudCompatible.self,configurations:config)
            let context=ModelContext(c);context.autosaveEnabled=false
            context.insert(AuditCloudCompatible("same-business-id","device-A"))
            context.insert(AuditCloudCompatible("same-business-id","device-B"))
            try context.save()
            let rows=try context.fetch(FetchDescriptor<AuditCloudCompatible>())
            require(rows.count == 2 && Set(rows.map(\.body)) == ["device-A","device-B"],"removing unique permits duplicate business identity; explicit reconciliation required")
            return
        }
        let schema=Schema([AuditFact.self,AuditOutbox.self])
        let config=ModelConfiguration("OutboxAudit",schema:schema,url:root.appendingPathComponent("outbox.sqlite"),cloudKitDatabase:.none)
        let container=try ModelContainer(for:schema,configurations:[config])
        let context=ModelContext(container);context.autosaveEnabled=false
        if mode == "write" {
            context.insert(AuditFact("entry:synthetic", "original", 1))
            context.insert(AuditOutbox("entry:synthetic",1))
            try context.save()
            print("PASS: fact and outbox committed in one SwiftData save")
        } else if mode == "rollback" {
            let fact=try context.fetch(FetchDescriptor<AuditFact>()).first!
            fact.value="uncommitted";fact.revision=2
            context.insert(AuditOutbox("never-committed",2))
            context.rollback()
            print("PASS: injected pre-save failure rolled back")
        } else if mode == "crash-before-save" {
            let fact=try context.fetch(FetchDescriptor<AuditFact>()).first!
            fact.value="crashed";fact.revision=9
            context.insert(AuditOutbox("crashed",9))
            // Simulate abrupt process death; parent expects 73.
            _exit(73)
        } else if mode == "verify" {
            let facts=try context.fetch(FetchDescriptor<AuditFact>())
            let pending=try context.fetch(FetchDescriptor<AuditOutbox>())
            require(facts.count == 1 && facts[0].value == "original" && facts[0].revision == 1,"fresh process retains original fact")
            require(pending.count == 1 && pending[0].revision == 1,"fresh process retains exact outbox")
            // A local edit overtakes the acknowledgement of an older upload.
            facts[0].value="newer"; facts[0].revision=2; pending[0].revision=2
            try context.save()
            let acknowledgedRevision=1
            if pending[0].revision == acknowledgedRevision {context.delete(pending[0])}
            try context.save()
            require(try context.fetchCount(FetchDescriptor<AuditOutbox>()) == 1,"stale acknowledgement cannot erase newer mutation")
            let zone=CKRecordZone.ID(zoneName:"SyntheticAudit",ownerName:CKCurrentUserDefaultName)
            let recordID=CKRecord.ID(recordName:"entry:synthetic",zoneID:zone)
            let record=CKRecord(recordType:"AuditEnvelope",recordID:recordID)
            record["body"]="synthetic" as CKRecordValue
            let file=root.appendingPathComponent("synthetic-asset.bin")
            let bytes=Data([0,1,2,3,255]);try bytes.write(to:file,options:.atomic)
            record["asset"]=CKAsset(fileURL:file)
            let archiver=NSKeyedArchiver(requiringSecureCoding:true)
            record.encodeSystemFields(with:archiver);archiver.finishEncoding()
            let unarchiver=try NSKeyedUnarchiver(forReadingFrom:archiver.encodedData)
            unarchiver.requiresSecureCoding=true
            let restored=CKRecord(coder:unarchiver)!;unarchiver.finishDecoding()
            require(restored.recordID == recordID,"native CKRecord stable identity and system-fields archive round-trip")
            let asset=record["asset"] as! CKAsset
            require(try Data(contentsOf:asset.fileURL!) == bytes,"CKAsset references exact staged bytes locally")
            require(record.recordChangeTag == nil,"no server tag fabricated by local PoC")
            print("NOT_RUN: CKSyncEngine networking, actual server conflict, account changes, two-device delivery")
        } else {fatalError("Unknown mode")}
    }
}
