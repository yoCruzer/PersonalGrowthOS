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
        var item=try XCTUnwrap(s.read().items.first);item.name="Renamed current";_ = try s.saveItem(item)
        XCTAssertEqual(try s.read().history.first,first)
        past=try s.begin(day:first.day,editingID:first.id);past.note="Correction"
        past=try s.saveDraft(past);XCTAssertEqual(try s.read().history.first,first)
        let corrected=try s.confirm(past);XCTAssertEqual(corrected.id,first.id);XCTAssertEqual(corrected.note,"Correction")
        let future=try s.begin(day:"2099-01-01");XCTAssertThrowsError(try s.confirm(future));try s.delete(id:future.id,revision:future.revision)
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
        let (source,root)=try store();let lease=try await ImportExportService(context:source.mainContext,mediaStore:MediaStore(rootURL:root),availableCapacity:{.max}).exportPackage();defer {lease.cleanup()}
        let extracted=root.appendingPathComponent("extracted");try FileManager.default.createDirectory(at:extracted,withIntermediateDirectories:true)
        try ZIPArchiveReader(archiveURL: lease.url, availableCapacity: .max).extractAll(to: extracted)
        let original=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:extracted.appendingPathComponent("data.json"))) as? [String:Any])
        let originalManifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:extracted.appendingPathComponent("manifest.json"))) as? [String:Any])
        for scenario in 0..<3 {
            var payload=original,manifest=originalManifest
            if scenario < 2 {payload.removeValue(forKey:scenario == 0 ? "netWorthItems":"netWorthSnapshots")}
            else {manifest["packageSchemaVersion"]=11}
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
}
