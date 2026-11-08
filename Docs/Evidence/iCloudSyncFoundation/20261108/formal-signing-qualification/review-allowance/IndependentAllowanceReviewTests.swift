import XCTest
import Foundation
import FormalProbeCore

final class IndependentAllowanceReviewTests: XCTestCase {
    func testCrossProductUsesAnIndependentExplicitOracle() {
        let services: [(Any?, Bool)] = [("*",true),(["CloudKit"],true),(nil,false),(NSNull(),false),(true,false),(NSNumber(value:1),false),(Data([42]),false),(NSSet(array:["CloudKit"]),false),(["CloudKit":true],false),("CloudKit",false),(["*"],false),(["CloudKit","CloudDocuments"],false),(["CloudKit",NSNull()],false),("*\u{0}",false),("＊",false),(["CloudKit","CloudKit"],false)]
        let environments: [(Any?,Bool,Bool)] = [("Development",true,true),(["Development"],true,true),(["Production","Development"],true,true),(["Development","Production"],true,true),("Production",true,false),(["Production"],true,false),(nil,false,false),([],false,false),("development",false,false),("Development\n",false,false),(["Development","*"],false,false),(["Development","Development"],false,false),(["Development",NSNumber(value:1)],false,false),(["Development",NSNull()],false,false),(["environment":"Development"],false,false),(NSSet(array:["Development"]),false,false),("Development\u{0}",false,false)]
        for (i,s) in services.enumerated() {for (j,e) in environments.enumerated() {
            let parsed=ProbeProfileCloudAllowance(services:s.0,environment:e.0)
            XCTAssertEqual(parsed.isWellFormed,s.1 && e.1,"shape \(i),\(j)")
            XCTAssertEqual(parsed.permitsDevelopmentCloudKit,s.1 && e.2,"permission \(i),\(j)")
        }}
    }
    func testSerializedAllowancesRoundTripWithoutBroadening() throws {
        for format in [PropertyListSerialization.PropertyListFormat.binary,.xml] {
            for services:Any in ["*",["CloudKit"],["*"],["CloudKit","CloudDocuments"]] {
                let d:[String:Any] = ["s":services,"e":["Production","Development"]]
                let b=try PropertyListSerialization.data(fromPropertyList:d,format:format,options:0)
                let round=try XCTUnwrap(PropertyListSerialization.propertyList(from:b,format:nil) as? [String:Any])
                let valid = services as? String == "*" || services as? [String] == ["CloudKit"]
                XCTAssertEqual(ProbeProfileCloudAllowance(services:round["s"],environment:round["e"]).permitsDevelopmentCloudKit,valid)
            }
        }
    }
    func testProfileAllowanceCannotReplaceActualSignatureOrExactClaims() throws {
        let p=try ProbeFixture.make(run:UUID(),dataset:UUID()).plan
        func evidence(_ variant:Int)->ProbeSigningEvidence {
            ProbeSigningEvidence(signatureVerified:variant != 1,codeIdentifier:variant == 2 ? "wrong" : p.candidateBundle,codeTeam:p.team,
                applicationIdentifier:p.team+"."+p.candidateBundle,entitlementTeam:p.team,containers:variant == 3 ? [p.container,"iCloud.syntheticExtra"]:[p.container],
                services:variant == 4 ? ["*"] : ["CloudKit"],environment:variant == 5 ? "Production":"Development",sandbox:true,networkClient:true,
                profilePresent:variant != 6,profileApplicationIdentifier:variant == 7 ? p.team+".*":p.team+"."+p.candidateBundle,
                profileTeam:variant == 8 ? "SYNTHETIC":p.team,profileContainers:variant == 9 ? ["*"]:[p.container],
                profileServices:"*",profileEnvironment:variant == 10 ? ["Production"]:["Production","Development"],profileUnexpired:variant != 11)
        }
        XCTAssertEqual(evidence(0).rejectionCodes(for:p),[])
        for variant in 1...11 {XCTAssertFalse(evidence(variant).rejectionCodes(for:p).isEmpty,"variant \(variant)")}
    }
}
