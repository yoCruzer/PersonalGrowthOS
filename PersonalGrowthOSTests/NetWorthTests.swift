import XCTest
import SwiftData
import CryptoKit
@testable import PersonalGrowthOS

@MainActor final class NetWorthTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_600_000)
    func store() throws -> (ModelContainer, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NetWorthSynthetic-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (try PersistenceContainerFactory.makeOnDisk(at: root.appendingPathComponent("store.sqlite")), root)
    }
    func service(_ container: ModelContainer) -> NetWorthService { NetWorthService(context: container.mainContext, now: { self.now }) }
    func seeded(_ service: NetWorthService, day: String = "2026-09-30") throws -> NetWorthSnapshotValue {
        let names = ["Synthetic bank", "Synthetic investments", "Synthetic property", "Synthetic vehicle", "Synthetic mortgage", "Synthetic credit"]
        let categories: [NetWorthCategory] = [.cash, .investments, .property, .valuables, .mortgage, .credit]
        let amounts = ["100000", "200000", "2000000", "100000", "1000000", "10000"]
        for i in names.indices { _ = try service.saveItem(.init(name: names[i], side: categories[i].side, category: categories[i])) }
        var draft = try service.begin(day: day)
        for i in draft.items.indices {
            let index = try XCTUnwrap(names.firstIndex(of: draft.items[i].name))
            try draft.items[i].enter(amounts[index], day: day)
        }
        draft.assetsConfirmed = true; draft.liabilitiesConfirmed = true
        return try service.confirm(service.saveDraft(draft))
    }
    func testExactMoneyAndInvalidPairs() throws {
        XCTAssertNil(try NetWorthMoney.parse("")); XCTAssertEqual(try NetWorthMoney.parse("0"), 0)
        XCTAssertEqual(try NetWorthMoney.parse("100.01"), 10001)
        XCTAssertEqual(try NetWorthMoney.parse("0,29", locale: Locale(identifier: "de_DE")), 29)
        for invalid in ["-1", "+1", "1e3", "NaN", "1.001", "1,000", ".", "1.", "90000000000000.01", "999999999999999999999"] { XCTAssertThrowsError(try NetWorthMoney.parse(invalid, locale: Locale(identifier: "en_US")), invalid) }
        XCTAssertEqual(try NetWorthMoney.sum([10,20]),30)
        XCTAssertThrowsError(try NetWorthMoney.sum([NetWorthMoney.maximum,1]))
        XCTAssertEqual(NetWorthMoney.decimal(-10001), "-100.01")
        XCTAssertEqual(NetWorthMoney.display(123456,locale:Locale(identifier:"en_US")),"1,234.56")
        XCTAssertEqual(NetWorthMoney.display(123456,locale:Locale(identifier:"zh_CN")),"1,234.56")
    }
    func testIndependentTruthTransfersRepaymentUnknownAndNegative() throws {
        let (container, _) = try store(); let s = service(container); let first = try seeded(s)
        XCTAssertEqual(try first.totals(), .init(assets:240000000,liabilities:101000000,assetsComplete:true,liabilitiesComplete:true))
        XCTAssertEqual(try first.totals().net,139000000)
        var transfer = first
        for i in transfer.items.indices {
            if transfer.items[i].category == .cash { try transfer.items[i].enter("90000",day:first.day) }
            if transfer.items[i].category == .investments { try transfer.items[i].enter("210000",day:first.day) }
        }
        XCTAssertEqual(try transfer.totals().net,139000000)
        var repayment = first
        for i in repayment.items.indices {
            if repayment.items[i].category == .cash { try repayment.items[i].enter("80000",day:first.day) }
            if repayment.items[i].category == .mortgage { try repayment.items[i].enter("980000",day:first.day) }
        }
        XCTAssertEqual(try repayment.totals().assets,238000000);XCTAssertEqual(try repayment.totals().liabilities,99000000);XCTAssertEqual(try repayment.totals().net,139000000)
        var unknown = first; let mortgage = try XCTUnwrap(unknown.items.firstIndex { $0.category == .mortgage })
        try unknown.items[mortgage].enter("",day:first.day); XCTAssertNil(try unknown.totals().net)
        var debt = first;debt.items=first.items.filter {$0.category == .credit};XCTAssertEqual(try debt.totals().net,-1000000)
        debt.assetsConfirmed=false;XCTAssertNil(try debt.totals().net)
    }
    func testRepeatedCarryKeepsOriginalDateAndNewAccountDoesNotBreakComparison() throws {
        let (c, _) = try store();let s=service(c);let first=try seeded(s)
        _ = try s.saveItem(.init(name:"New bank",side:.asset,category:.cash))
        var draft=try s.begin(day:"2026-10-31")
        XCTAssertEqual(try s.begin(day:"2026-10-30").id,draft.id)
        XCTAssertTrue(draft.items.allSatisfy(\.pending));XCTAssertNil(try draft.totals().net)
        draft.carryRemaining();draft.assetsConfirmed=true;draft.liabilitiesConfirmed=true
        let new=try XCTUnwrap(draft.items.firstIndex {$0.name == "New bank"})
        try draft.items[new].enter("0",day:draft.day)
        let saved=try s.confirm(s.saveDraft(draft))
        XCTAssertEqual(try saved.totals().net,139000000)
        XCTAssertEqual(saved.items.filter {$0.id != draft.items[new].id}.compactMap(\.amountDay),Array(repeating:first.day,count:6))
        XCTAssertEqual(Set(NetWorthTrend.points([first,saved]).map(\.segment)).count,1)
    }
    func testDraftInvalidTextReopenFailureRetryAndStaleConflict() throws {
        let (c,root)=try store();let s=service(c);_ = try seeded(s)
        var draft=try s.begin(day:"2026-10-31");draft.items[0].inputText="1..2";draft=try s.saveDraft(draft)
        let reopened=try PersistenceContainerFactory.makeOnDisk(at:root.appendingPathComponent("store.sqlite"))
        XCTAssertEqual(try service(reopened).read().draft?.items[0].inputText,"1..2")
        XCTAssertThrowsError(try s.confirm(draft));XCTAssertEqual(try s.read().history.count,1)
        let faulty=NetWorthService(context:c.mainContext,now:{self.now},commit:{_ in throw NetWorthFailure.invalid})
        var next=draft;next.items[0].inputText="123.45"
        XCTAssertThrowsError(try faulty.saveDraft(next));XCTAssertEqual(try s.read().draft,draft)
        next=try s.saveDraft(next);XCTAssertThrowsError(try s.saveDraft(draft))
        _ = try s.confirm(next);XCTAssertThrowsError(try s.confirm(next));XCTAssertEqual(try s.read().history.count,2)
    }
    func testBackdateCorrectionSameDayFutureAndFrozenMetadata() throws {
        let (c,_)=try store();let s=service(c);let first=try seeded(s)
        XCTAssertThrowsError(try s.begin(day:first.day))
        var past=try s.begin(day:"2026-08-31");XCTAssertTrue(past.items.allSatisfy {$0.cents == nil});try s.delete(id:past.id,revision:past.revision)
        var item=try XCTUnwrap(s.read().items.first);item.name="Renamed current";item.note="Synthetic revised note";_ = try s.saveItem(item)
        XCTAssertEqual(try s.read().history.first,first)
        past=try s.begin(day:first.day,editingID:first.id);past.note="Correction"
        past=try s.saveDraft(past);XCTAssertEqual(try s.read().history.first,first)
        let corrected=try s.confirm(past);XCTAssertEqual(corrected.id,first.id);XCTAssertEqual(corrected.note,"Correction")
        let future=try s.begin(day:"2099-01-01");XCTAssertEqual(future.items.first {$0.id == item.id}?.note,"Synthetic revised note");XCTAssertThrowsError(try s.confirm(future));try s.delete(id:future.id,revision:future.revision)
        try s.delete(id:corrected.id,revision:corrected.revision);XCTAssertTrue(try s.read().history.isEmpty)
    }
    func testArchiveRequiresZeroAndPreservesHistory() throws {
        let (c,_)=try store();let s=service(c);let first=try seeded(s)
        var item=try XCTUnwrap(s.read().items.first);item.archived=true;XCTAssertThrowsError(try s.saveItem(item))
        var draft=try s.begin(day:"2026-10-31");let i=try XCTUnwrap(draft.items.firstIndex {$0.id == item.id})
        try draft.items[i].enter("0",day:draft.day);draft.carryRemaining();_ = try s.confirm(s.saveDraft(draft))
        _ = try s.saveItem(item);XCTAssertEqual(try s.read().history.first,first)
        XCTAssertFalse(try s.begin(day:"2026-11-01").items.contains {$0.id == item.id})
    }
    func testScopeAndUnknownBreakLinesWithoutInventingDates() throws {
        let (c,_)=try store();let first=try seeded(service(c));var adjusted=first;adjusted.id=UUID();adjusted.day="2026-10-31";adjusted.scopeAdjusted=true
        var next=first;next.id=UUID();next.day="2026-11-01"
        let points=NetWorthTrend.points([first,adjusted,next]);XCTAssertEqual(points.count,3);XCTAssertEqual(Set(points.map(\.segment)).count,3)
        adjusted.scopeAdjusted=false;adjusted.assetsConfirmed=false
        let incomplete=NetWorthTrend.points([first,adjusted,next]);XCTAssertNil(incomplete[1].cents);XCTAssertNotEqual(incomplete[0].segment,incomplete[2].segment)
        XCTAssertEqual(NetWorthTrend.points([first]).count,1)
    }
    func testArchivedZeroCannotBeRewrittenOrDeletedAndBackdateKeepsPastBalance() throws {
        let (c,_)=try store();let s=service(c);let first=try seeded(s)
        var item=try XCTUnwrap(s.read().items.first)
        var closing=try s.begin(day:"2026-10-31");let index=try XCTUnwrap(closing.items.firstIndex {$0.id == item.id})
        closing.carryRemaining();try closing.items[index].enter("0",day:closing.day)
        let zero=try s.confirm(s.saveDraft(closing));item.archived=true;item=try s.saveItem(item)
        let backdate=try s.begin(day:"2026-10-01")
        XCTAssertEqual(backdate.items.first {$0.id == item.id}?.cents,first.items.first {$0.id == item.id}?.cents)
        try s.delete(id:backdate.id,revision:backdate.revision)
        XCTAssertThrowsError(try s.delete(id:zero.id,revision:zero.revision)) {XCTAssertEqual(($0 as? NetWorthFailure)?.errorDescription,NetWorthFailure.archivedHistory.errorDescription)}
        var correction=try s.begin(day:zero.day,editingID:zero.id)
        try correction.items[index].enter("100",day:zero.day);correction=try s.saveDraft(correction)
        XCTAssertThrowsError(try s.confirm(correction))
        XCTAssertEqual(try s.read().history.last,zero);XCTAssertEqual(try s.read().draft,correction)
        var invalid=zero;invalid.items[index].cents=10000
        XCTAssertThrowsError(try NetWorthLedger(items:s.read().items,snapshots:[first,invalid]).validate())
        item.archived=false;_ = try s.saveItem(item)
        let changed=try s.confirm(correction);XCTAssertEqual(changed.items[index].cents,10000)
        XCTAssertTrue(try s.begin(day:"2026-11-01").items.contains {$0.id == item.id})
    }
    func testInvalidValuesRejectDuplicateIDsDatesAndEnums() throws {
        let (c,_)=try store();let first=try seeded(service(c));let ledger=try service(c).read()
        var duplicate=first;duplicate.id=UUID();XCTAssertThrowsError(try NetWorthLedger(items:ledger.items,snapshots:[first,duplicate]).validate())
        duplicate=first;duplicate.items.append(first.items[0]);XCTAssertThrowsError(try duplicate.validate())
        duplicate=first;duplicate.day="2026-02-30";XCTAssertThrowsError(try duplicate.validate())
        duplicate=first;duplicate.items[0].cents = -1;XCTAssertThrowsError(try duplicate.validate())
        duplicate=first;duplicate.items[0].amountDay="2099-01-01";XCTAssertThrowsError(try duplicate.validate())
        duplicate=first;duplicate.version=2;XCTAssertThrowsError(try duplicate.validate())
        let encoded=String(decoding:try JSONEncoder().encode(first),as:UTF8.self).replacingOccurrences(of:"\"asset\"",with:"\"invalidSide\"")
        XCTAssertThrowsError(try JSONDecoder().decode(NetWorthSnapshotValue.self,from:Data(encoded.utf8)))
    }
    func testCSVUnknownZeroFormulaAndEmptySnapshot() throws {
        let (c,_)=try store();let s=service(c);_ = try s.saveItem(.init(name:"=SUM(A1)",side:.asset,category:.cash))
        var draft=try s.begin(day:"2026-09-30");draft.assetsConfirmed=true;draft.liabilitiesConfirmed=true;_ = try s.confirm(draft)
        draft=try s.begin(day:"2026-10-31");try draft.items[0].enter("0",day:draft.day);_ = try s.confirm(s.saveDraft(draft))
        let csv=try NetWorthCSV.make(s.read());XCTAssertTrue(csv.contains("'=SUM(A1)"));XCTAssertTrue(csv.contains("\"0.00\""));XCTAssertTrue(csv.contains("\"unknown\""));XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        let (empty,_)=try store();let e=service(empty);_ = try e.confirm(e.begin(day:"2026-09-30"))
        XCTAssertEqual(try NetWorthCSV.make(e.read()).components(separatedBy:"\r\n").count,3)
    }
    func testActualV12ZIPDraftAndHistoryRoundTripWithNonemptyProtection() async throws {
        let (c,root)=try store();let s=service(c);_ = try seeded(s)
        var draft=try s.begin(day:"2026-10-31");draft.items[0].inputText="invalid";_ = try s.saveDraft(draft)
        let expected=try TransferSnapshot.make(context:ModelContext(c))
        let exporter=ImportExportService(context:c.mainContext,mediaStore:MediaStore(rootURL:root),availableCapacity:{.max})
        let lease=try await exporter.exportPackage();defer {lease.cleanup()}
        let (target,targetRoot)=try store()
        let importer=ImportExportService(context:target.mainContext,mediaStore:MediaStore(rootURL:targetRoot),availableCapacity:{.max})
        _ = try await importer.importPackage(from:lease.url)
        let reopened=try PersistenceContainerFactory.makeOnDisk(at:targetRoot.appendingPathComponent("store.sqlite"))
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(reopened)),expected)
        XCTAssertEqual(try service(reopened).read().draft?.items[0].inputText,"invalid")
        XCTAssertEqual(try NetWorthCSV.make(service(reopened).read()),try NetWorthCSV.make(s.read()))
        for onlyDraft in [false,true] {
            let (nonempty,folder)=try store();let n=service(nonempty)
            if onlyDraft { _ = try n.begin(day:"2026-09-30") } else { _ = try n.saveItem(.init(name:"Preserve",side:.asset,category:.cash)) }
            do { _ = try await ImportExportService(context:nonempty.mainContext,mediaStore:MediaStore(rootURL:folder),availableCapacity:{.max}).importPackage(from:lease.url);XCTFail("Nonempty target accepted") }
            catch { XCTAssertEqual(error as? TransferPackageError,.targetNotEmpty) }
        }
    }
    func testExactBASEV15MigrationProtectionReopenAndActualLegacyZIP() async throws {
        let source = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"NetWorthBaselineV15Fixture",withExtension:nil))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NetWorthMigration-\(UUID())")
        try FileManager.default.copyItem(at:source,to:root)
        let storeURL=root.appendingPathComponent("Store/PersonalGrowthOS.sqlite")
        try FileManager.default.createDirectory(at:storeURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        try FileManager.default.moveItem(at:root.appendingPathComponent("PersonalGrowthOS.sqlite"),to:storeURL)
        let oldBytes=try Data(contentsOf:storeURL)
        let (legacy,legacyRoot)=try store()
        _ = try await ImportExportService(context:legacy.mainContext,mediaStore:MediaStore(rootURL:legacyRoot),availableCapacity:{.max}).importPackage(from:source.appendingPathComponent("expected-v11.zip"))
        let expected=try TransferSnapshot.make(context:ModelContext(legacy))
        XCTAssertEqual(expected.entries.count,1);XCTAssertEqual(expected.habits.count,1);XCTAssertFalse(expected.todoTasks.isEmpty)
        XCTAssertEqual(expected.importantDays.count,1);XCTAssertEqual(expected.sleepRecords.count,1);XCTAssertEqual(expected.investmentSessions.count,1)
        XCTAssertTrue(expected.netWorthItems.isEmpty);XCTAssertTrue(expected.netWorthSnapshots.isEmpty)
        let app=try AppContainer.make(configuration:.init(launchMode:.uiTesting,resetDataOnLaunch:false),rootURLOverride:root)
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(app.modelContainer)),expected)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("Recovery/BeforeMigration/Store/PersonalGrowthOS.sqlite")),oldBytes)
        let reopened=try PersistenceContainerFactory.makeOnDisk(at:storeURL)
        XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(reopened)),expected)
        XCTAssertTrue(StartupStoreProtection.isCurrentStore(at:storeURL))
        for image in expected.images { XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent(image.relativePath)),try Data(contentsOf:legacyRoot.appendingPathComponent(image.relativePath))) }
    }
    func testV12WireRequiredArraysAndDisguisedLegacyRejectWithoutPublication() async throws {
        let (source,root)=try store();let s=service(source);_ = try seeded(s)
        var second=try s.begin(day:"2026-10-31");second.carryRemaining();_ = try s.confirm(second)
        let lease=try await ImportExportService(context:source.mainContext,mediaStore:MediaStore(rootURL:root),availableCapacity:{.max}).exportPackage();defer {lease.cleanup()}
        let extracted=root.appendingPathComponent("extracted");try FileManager.default.createDirectory(at:extracted,withIntermediateDirectories:true)
        try ZIPArchiveReader(archiveURL: lease.url, availableCapacity: .max).extractAll(to: extracted)
        let original=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:extracted.appendingPathComponent("data.json"))) as? [String:Any])
        let originalManifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:extracted.appendingPathComponent("manifest.json"))) as? [String:Any])
        for scenario in 0..<9 {
            var payload=original,manifest=originalManifest
            if scenario < 2 {payload.removeValue(forKey:scenario == 0 ? "netWorthItems":"netWorthSnapshots")}
            else if scenario == 2 {manifest["packageSchemaVersion"]=11}
            else {
                var snapshots=try XCTUnwrap(payload["netWorthSnapshots"] as? [[String:Any]])
                var rows=try XCTUnwrap(snapshots[0]["items"] as? [[String:Any]])
                var items=try XCTUnwrap(payload["netWorthItems"] as? [[String:Any]])
                switch scenario {
                case 3: rows[0]["cents"] = -1
                case 4: snapshots[0]["day"] = "2026-02-30"
                case 5: rows[0]["state"] = "inventedState"
                case 6: items[1]["id"] = items[0]["id"]
                case 7: snapshots[1]["day"] = snapshots[0]["day"]
                default: items[0]["archived"] = true
                }
                snapshots[0]["items"]=rows;payload["netWorthSnapshots"]=snapshots;payload["netWorthItems"]=items
            }
            let bytes=try JSONSerialization.data(withJSONObject:payload,options:.sortedKeys)
            let dataURL=extracted.appendingPathComponent("data.json"),manifestURL=extracted.appendingPathComponent("manifest.json")
            try bytes.write(to:dataURL)
            var file=try XCTUnwrap(manifest["dataFile"] as? [String:Any]);file["byteCount"]=bytes.count;file["sha256"]=SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined();manifest["dataFile"]=file
            try JSONSerialization.data(withJSONObject:manifest,options:.sortedKeys).write(to:manifestURL)
            let archive=root.appendingPathComponent("wire-\(scenario).zip")
            try ZIPArchiveWriter.write(sources:[.init(path:"manifest.json",fileURL:manifestURL),.init(path:"data.json",fileURL:dataURL)],to:archive)
            let (target,targetRoot)=try store()
            do { _ = try await ImportExportService(context:target.mainContext,mediaStore:MediaStore(rootURL:targetRoot),availableCapacity:{.max}).importPackage(from:archive);XCTFail("Invalid wire accepted") } catch {}
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(target)).totalObjectCount,0)
        }
    }

    func testDraftIdentityTimezoneCorrectionConflictAndConcurrentNewItem() throws {
        let (c,_) = try store(); let s = service(c); let first = try seeded(s)
        var draft = try s.begin(day:"2026-10-31")
        XCTAssertThrowsError(try s.begin(day:first.day,editingID:first.id))
        var forged = draft; forged.timeZoneID = "Pacific/Kiritimati"
        if forged.timeZoneID == draft.timeZoneID { forged.timeZoneID = "America/Los_Angeles" }
        XCTAssertThrowsError(try s.saveDraft(forged)); XCTAssertThrowsError(try s.confirm(forged))
        _ = try s.saveItem(.init(name:"Added while draft open",side:.liability,category:.credit))
        draft.carryRemaining(); draft.assetsConfirmed=true; draft.liabilitiesConfirmed=true
        let confirmed = try s.confirm(draft)
        XCTAssertNil(try confirmed.totals().net)
        XCTAssertEqual(confirmed.items.count,7)
        XCTAssertEqual(try s.read().history.first,first)
        let correction = try s.begin(day:first.day,editingID:first.id)
        try s.delete(id:first.id,revision:first.revision)
        XCTAssertThrowsError(try s.confirm(correction))
        XCTAssertEqual(try s.read().draft,correction)
        XCTAssertEqual(try s.read().history,[confirmed])
    }

    func testPublicationBusyAndCancellationKeepDraftExactly() async throws {
        let (c,root) = try store(); let s=service(c); _ = try seeded(s)
        var draft=try s.begin(day:"2026-10-31");draft.items[0].inputText="12..3";draft=try s.saveDraft(draft)
        let held=expectation(description:"Store publication held by independent worker")
        let release=DispatchSemaphore(value:0);defer {release.signal()}
        let worker=Task.detached {try StorePublication.perform(at:root) {held.fulfill();guard release.wait(timeout:.now()+15) == .success else {throw TransferPackageError.interrupted}}}
        await fulfillment(of:[held],timeout:10)
        XCTAssertThrowsError(try s.saveDraft(draft)) {XCTAssertEqual($0 as? StorePublicationFailure,.busy)}
        XCTAssertThrowsError(try s.confirm(draft)) {XCTAssertEqual($0 as? StorePublicationFailure,.busy)}
        release.signal();try await worker.value
        let cancelled=Task {try s.confirm(draft)};cancelled.cancel()
        do {_ = try await cancelled.value;XCTFail("Cancelled write succeeded")} catch {XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(try s.read().draft,draft);XCTAssertEqual(try s.read().history.count,1)
        draft.items[0].inputText="12.30";_ = try s.confirm(s.saveDraft(draft))
        XCTAssertNil(try s.read().draft);XCTAssertEqual(try s.read().history.count,2)
    }

    func testActualFinancialZIPInterruptedRestoreRollbackAndLateNonemptyRecheck() async throws {
        let (source,root)=try store();let s=service(source);_ = try seeded(s)
        var draft=try s.begin(day:"2026-10-31");draft.items[0].inputText="1..2";_ = try s.saveDraft(draft)
        let expected=try TransferSnapshot.make(context:ModelContext(source))
        let lease=try await ImportExportService(context:source.mainContext,mediaStore:MediaStore(rootURL:root),availableCapacity:{.max}).exportPackage();defer {lease.cleanup()}
        for cancelled in [false,true] {
            let (target,targetRoot)=try store()
            let importer=ImportExportService(context:target.mainContext,mediaStore:MediaStore(rootURL:targetRoot),availableCapacity:{.max},publicationCheckpoint:{stage in
                if stage == .beforeSave {if cancelled {throw CancellationError()};throw CocoaError(.fileWriteOutOfSpace)}
            })
            do {_ = try await importer.importPackage(from:lease.url);XCTFail("Interrupted restore succeeded")} catch {if cancelled {XCTAssertTrue(error is CancellationError)}}
            let reopened=try PersistenceContainerFactory.makeOnDisk(at:targetRoot.appendingPathComponent("store.sqlite"))
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(reopened)).totalObjectCount,0)
            _ = try await ImportExportService(context:reopened.mainContext,mediaStore:MediaStore(rootURL:targetRoot),availableCapacity:{.max}).importPackage(from:lease.url)
            XCTAssertEqual(try TransferSnapshot.make(context:ModelContext(reopened)),expected)
        }
        let (target,targetRoot)=try store()
        let installed=expectation(description:"Restore paused before final empty check"),release=DispatchSemaphore(value:0)
        defer {release.signal()}
        let importer=ImportExportService(context:target.mainContext,mediaStore:MediaStore(rootURL:targetRoot),availableCapacity:{.max},publicationCheckpoint:{stage in
            if stage == .afterInstall {installed.fulfill();guard release.wait(timeout:.now()+15) == .success else {throw TransferPackageError.interrupted}}
        })
        let restore=Task {try await importer.importPackage(from:lease.url)}
        await fulfillment(of:[installed],timeout:10)
        XCTAssertThrowsError(try service(target).saveItem(.init(name:"Blocked UI write",side:.asset,category:.cash))) {XCTAssertEqual($0 as? StorePublicationFailure,.busy)}
        // An older writer outside the lease still cannot be overwritten by restore.
        let preserved=NetWorthItemValue(name:"Concurrent independent writer",side:.asset,category:.cash)
        let other=ModelContext(target);other.insert(try NetWorthItem(preserved));try other.save()
        release.signal()
        do {_ = try await restore.value;XCTFail("Late nonempty target accepted")} catch {XCTAssertEqual(error as? TransferPackageError,.targetNotEmpty)}
        let reopened=try PersistenceContainerFactory.makeOnDisk(at:targetRoot.appendingPathComponent("store.sqlite"))
        XCTAssertEqual(try service(reopened).read().items,[preserved]);XCTAssertTrue(try service(reopened).read().snapshots.isEmpty)
    }
}
