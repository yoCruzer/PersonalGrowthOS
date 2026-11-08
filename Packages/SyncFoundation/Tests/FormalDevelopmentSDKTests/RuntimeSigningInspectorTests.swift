import XCTest
import Foundation
#if os(macOS)
import Security
#endif
@testable import FormalDevelopmentSDK

final class RuntimeSigningInspectorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let device = "00000000-0000-0000-0000-000000000001"
    let leaf = Data("synthetic certificate bytes, not a real certificate".utf8)
    func entitlements() -> [String: Any] {
        ["com.apple.application-identifier":RuntimeSigningInspector.team+"."+RuntimeSigningInspector.bundle,
         "com.apple.developer.team-identifier":RuntimeSigningInspector.team,
         "com.apple.developer.icloud-container-identifiers":[RuntimeSigningInspector.container],
         "com.apple.developer.icloud-services":["CloudKit"],
         "com.apple.developer.icloud-container-environment":"Development",
         "com.apple.security.app-sandbox":true,"com.apple.security.network.client":true]
    }
    func profile() -> [String: Any] {
        var ent=entitlements();ent["com.apple.developer.icloud-services"]="*"
        ent["com.apple.developer.icloud-container-environment"]=["Production","Development"]
        return ["Platform":["OSX"],"TeamIdentifier":[RuntimeSigningInspector.team],"Entitlements":ent,
                "CreationDate":now.addingTimeInterval(-100),"ExpirationDate":now.addingTimeInterval(100),
                "DeveloperCertificates":[leaf],"ProvisionedDevices":[device]]
    }
    func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys,.withoutEscapingSlashes]) }
    func binding(receipt: Data, pins: Data) throws -> RuntimeSigningExpectation {
        try RuntimeSigningExpectation(signedBinarySHA256:String(repeating:"a",count:64),codeDirectoryHash:String(repeating:"b",count:40),
            profileSHA256:String(repeating:"c",count:64),packagingReceiptSHA256:RuntimeSigningInspector.digest(receipt),sourcePinsSHA256:RuntimeSigningInspector.digest(pins))
    }
    func receipt() throws -> (Data,Data) {
        let pins=["Package.swift":String(repeating:"1",count:64),"Sources/FormalDevelopmentSDK/RuntimeSigningInspector.swift":String(repeating:"2",count:64)]
        let bytes=try json(["formatVersion":1,"bundle":RuntimeSigningInspector.bundle,"container":RuntimeSigningInspector.container,
            "environment":"Development","status":"UNPROVISIONED_NO_DEVELOPER_SIGNATURE","binarySHA256":String(repeating:"d",count:64),
            "infoSHA256":String(repeating:"e",count:64),"sourceSHA256":pins] as [String:Any])
        return (bytes,try json(pins))
    }
    func testExactRuntimeEntitlementsAndNoProfileWildcardInClaims() throws {
        XCTAssertNoThrow(try RuntimeSigningInspector.validateEntitlements(entitlements()))
        let variants:[(String,Any)]=[("com.apple.developer.icloud-services","*"),("com.apple.developer.icloud-services",["*"]),
            ("com.apple.developer.icloud-container-environment",["Development"]),("com.apple.developer.icloud-container-environment","Production"),
            ("com.apple.security.app-sandbox",NSNumber(value:1)),("com.apple.security.network.client",false),
            ("com.apple.developer.icloud-container-identifiers",[RuntimeSigningInspector.container,"iCloud.synthetic"]),
            ("com.apple.application-identifier",RuntimeSigningInspector.team+".*"),("com.apple.security.files.user-selected.read-write",true)]
        for (key,value) in variants {var e=entitlements();e[key]=value;XCTAssertThrowsError(try RuntimeSigningInspector.validateEntitlements(e),key)}
    }
    func testSyntheticProfileAllowanceAndLocalMembership() throws {
        let p=profile()
        XCTAssertEqual(try RuntimeSigningInspector.validateProfile(p,signingLeaf:leaf,provisioningUDID:device,now:now),now.addingTimeInterval(100))
        for format in [PropertyListSerialization.PropertyListFormat.xml,.binary] {
            let b=try PropertyListSerialization.data(fromPropertyList:p,format:format,options:0)
            let parsed=try XCTUnwrap(PropertyListSerialization.propertyList(from:b,format:nil) as? [String:Any])
            XCTAssertNoThrow(try RuntimeSigningInspector.validateProfile(parsed,signingLeaf:leaf,provisioningUDID:device,now:now))
        }
    }
    func testWrongProfilePlatformTeamWildcardContainerAndProductionOnlyReject() throws {
        for (key,value) in [("Platform",["iOS"]),("Platform",["OSX","iOS"]),("TeamIdentifier",["SYNTHETIC_OTHER"])] {
            var p=profile();p[key]=value;XCTAssertThrowsError(try RuntimeSigningInspector.validateProfile(p,signingLeaf:leaf,provisioningUDID:device,now:now))
        }
        let variants:[(String,Any)]=[("com.apple.application-identifier",RuntimeSigningInspector.team+".*"),
            ("com.apple.developer.icloud-container-identifiers",["*"]),("com.apple.developer.icloud-container-environment",["Production"]),
            ("com.apple.developer.icloud-services",["CloudKit",true])]
        for (key,value) in variants {var p=profile();var e=try XCTUnwrap(p["Entitlements"] as? [String:Any]);e[key]=value;p["Entitlements"]=e
            XCTAssertThrowsError(try RuntimeSigningInspector.validateProfile(p,signingLeaf:leaf,provisioningUDID:device,now:now))}
    }
    func testProfileDatesAndCertificateDeviceMembershipFailClosed() throws {
        let variants:[(String,Any)]=[("CreationDate",now.addingTimeInterval(1)),("ExpirationDate",now),("ExpirationDate",now.addingTimeInterval(-1)),
            ("DeveloperCertificates",[Data([0])]),("ProvisionedDevices",["SYNTHETIC_OTHER"]),("ProvisionedDevices",[device,device]),
            ("ProvisionedDevices",[]),("ProvisionsAllDevices",true)]
        for (key,value) in variants {var p=profile();p[key]=value;XCTAssertThrowsError(try RuntimeSigningInspector.validateProfile(p,signingLeaf:leaf,provisioningUDID:device,now:now),key)}
        XCTAssertThrowsError(try RuntimeSigningInspector.validateProfile(profile(),signingLeaf:Data(),provisioningUDID:device,now:now))
        XCTAssertThrowsError(try RuntimeSigningInspector.validateProfile(profile(),signingLeaf:leaf,provisioningUDID:"",now:now))
    }
    func testExplicitDeviceFieldOnlyNoHardwareUUIDFallback() throws {
        XCTAssertEqual(try RuntimeSigningInspector.provisioningUDID(from:json(["SPHardwareDataType":[["provisioning_UDID":device]]])),device)
        let variants:[[String:Any]]=[[:],["SPHardwareDataType":[["platform_UUID":device]]],
            ["SPHardwareDataType":[["provisioning_UDID":device,"provisioningUDID":device]]],
            ["SPHardwareDataType":[["provisioning_UDID":true]]],["SPHardwareDataType":[["provisioning_UDID":"not-a-device"]]],
            ["SPHardwareDataType":[["provisioning_UDID":device],["provisioning_UDID":device]]]]
        for v in variants {XCTAssertThrowsError(try RuntimeSigningInspector.provisioningUDID(from:json(v)))}
        XCTAssertThrowsError(try RuntimeSigningInspector.provisioningUDID(from:Data(repeating:32,count:262_145)))
    }
    func testReviewedReceiptAndPinsBindBytesWithoutEquatingSignedAndUnsignedHashes() throws {
        let (r,p)=try receipt();let e=try binding(receipt:r,pins:p)
        XCTAssertNoThrow(try RuntimeSigningInspector.validateReceipt(r,sourcePins:p,expected:e))
        XCTAssertThrowsError(try RuntimeSigningInspector.validateReceipt(r+Data([32]),sourcePins:p,expected:e))
        XCTAssertThrowsError(try RuntimeSigningInspector.validateReceipt(r,sourcePins:p+Data([32]),expected:e))
        let wrong=try json(["Package.swift":String(repeating:"9",count:64)])
        XCTAssertThrowsError(try RuntimeSigningInspector.validateReceipt(r,sourcePins:wrong,expected:binding(receipt:r,pins:wrong)))
    }
    func testReceiptIdentityAndVersionRejectEvenWhenHashUpdated() throws {
        let (r,p)=try receipt();let parsed=try XCTUnwrap(JSONSerialization.jsonObject(with:r) as? [String:Any])
        for (key,value) in [("environment","Production" as Any),("bundle","wrong"),("formatVersion",true),("status","SIGNED"),("binarySHA256","short")] {
            var object=parsed;object[key]=value;let changed=try json(object)
            XCTAssertThrowsError(try RuntimeSigningInspector.validateReceipt(changed,sourcePins:p,expected:binding(receipt:changed,pins:p)))
        }
    }
    func testExpectedBindingsRejectMalformedOrUppercaseHashes() throws {
        for bad in ["",String(repeating:"A",count:64),String(repeating:"a",count:63),String(repeating:"g",count:64)] {
            XCTAssertThrowsError(try RuntimeSigningExpectation(signedBinarySHA256:bad,codeDirectoryHash:String(repeating:"b",count:40),profileSHA256:String(repeating:"c",count:64),packagingReceiptSHA256:String(repeating:"d",count:64),sourcePinsSHA256:String(repeating:"e",count:64)))
        }
    }
    func testActualUnqualifiedSelfCannotMintQualification() throws {
        let (r,p)=try receipt()
        XCTAssertThrowsError(try RuntimeSigningInspector.inspect(expected:binding(receipt:r,pins:p),packagingReceipt:r,sourcePins:p)) { error in
            #if os(macOS)
            if let diagnostic = error as? RuntimeSigningDiagnosticFailure {
                XCTAssertEqual(diagnostic.reason, .selfSignatureInvalid)
                XCTAssertNotEqual(diagnostic.status, 0)
                XCTAssertNotEqual(diagnostic.status, errSecCSInvalidFlags, "A flag API error is not evidence of signature rejection")
                XCTAssertEqual(diagnostic.stage, .dynamicValidity)
            } else {
                XCTAssertTrue([RuntimeSigningError.selfSignatureInvalid,.selfSignatureUnavailable].contains { $0 == error as? RuntimeSigningError })
            }
            #else
            XCTAssertEqual(error as? RuntimeSigningError,.unsupportedPlatform)
            #endif
        }
    }
    #if os(macOS)
    func testPublicAppleRootCannotActAsProfileSigningLeaf() throws {
        // Public Apple PKI root, fetched 2026-11-08 from AppleIncRootCertificate.cer.
        // SHA256 b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024.
        let bytes = try XCTUnwrap(Data(base64Encoded: "MIIEuzCCA6OgAwIBAgIBAjANBgkqhkiG9w0BAQUFADBiMQswCQYDVQQGEwJVUzETMBEGA1UEChMKQXBwbGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxFjAUBgNVBAMTDUFwcGxlIFJvb3QgQ0EwHhcNMDYwNDI1MjE0MDM2WhcNMzUwMjA5MjE0MDM2WjBiMQswCQYDVQQGEwJVUzETMBEGA1UEChMKQXBwbGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxFjAUBgNVBAMTDUFwcGxlIFJvb3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDkkakJH5HbHkdQ6wXtXnmELes2oldMVeyLGYne+Uts9QerIjAC6Bg++FAJ039BqJj50cpmnCRrEdCju+QbKsMflZ56DKRHi1vUFjczy8QPTc4UadHJGXL1XQ7Vf1+b8iUDulWPTV0N8WQ1IxVLFVkds5T39pyez1C6wVhQZ48ItCD3y6wsIG9wtj8BMIy3Q88PnT3zK0koGsj+zrW5DtleHNbLPbU6rfQPDgCSC7EhFi501TwN22IWq6NxkkdTVcGvL0Gz+PvjcM3mo0xFfh9Ma1CWQYnEdGILEINBhzOKgbEwWOxaBDKMaLOPHd5lc/9nXmW8Sdh2nzMUZaF3lMktAgMBAAGjggF6MIIBdjAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUK9BpR5R2Cf70a40uQKb3R01/CF4wHwYDVR0jBBgwFoAUK9BpR5R2Cf70a40uQKb3R01/CF4wggERBgNVHSAEggEIMIIBBDCCAQAGCSqGSIb3Y2QFATCB8jAqBggrBgEFBQcCARYeaHR0cHM6Ly93d3cuYXBwbGUuY29tL2FwcGxlY2EvMIHDBggrBgEFBQcCAjCBthqBs1JlbGlhbmNlIG9uIHRoaXMgY2VydGlmaWNhdGUgYnkgYW55IHBhcnR5IGFzc3VtZXMgYWNjZXB0YW5jZSBvZiB0aGUgdGhlbiBhcHBsaWNhYmxlIHN0YW5kYXJkIHRlcm1zIGFuZCBjb25kaXRpb25zIG9mIHVzZSwgY2VydGlmaWNhdGUgcG9saWN5IGFuZCBjZXJ0aWZpY2F0aW9uIHByYWN0aWNlIHN0YXRlbWVudHMuMA0GCSqGSIb3DQEBBQUAA4IBAQBcNplMLXi37Yyb3PN3m/J20ncwT8EfhYOFG5k9RzfyqZtAjizUsZAS2L70c5vu0mQPy3lPNNiiPvl4/2vIB+x9OYOLUyDTOMSxv5pPCmv/K/xZpwUJfBdAVhEedNO3iyM7R6PVbyTi69G3cN8PReEnyvFteO3ntRcXqNx+IjXKJdXZD9Zr1KIkIxH3oayPc4FgxhtbCS+SsvhESPBgOJ4V9T0mZyCKM2r3DYLP3uujL/lTaltkwGMzd/c6ByxW69oPIQ7aunMZT7XZNn/Bh1XZp5m5MkL72NVxnn6hUrcbvZNCJBIqxw8dtk2cXmPIS4AXUKqK1drk/NAJBzewdXUh"))
        let root = try XCTUnwrap(SecCertificateCreateWithData(nil, bytes as CFData))
        XCTAssertThrowsError(try RuntimeSigningInspector.validateProfileSignerChain([]))
        XCTAssertThrowsError(try RuntimeSigningInspector.validateProfileSignerChain([root]))
        // Correct known root does not compensate for a leaf lacking profile-signing purpose.
        XCTAssertThrowsError(try RuntimeSigningInspector.validateProfileSignerChain([root,root]))
        XCTAssertThrowsError(try RuntimeSigningInspector.validateCodeSignerChain([]))
        XCTAssertThrowsError(try RuntimeSigningInspector.validateCodeSignerChain([root]))
    }
    func testEmptyMalformedAndPlaintextProfilesAreNotTrustedCMS() {
        for bytes in [Data(),Data([0,1,2]),Data("<?xml version=\"1.0\"?><plist><dict/></plist>".utf8)] {
            XCTAssertThrowsError(try RuntimeSigningInspector.trustedProfile(bytes))
        }
    }
    #endif
#if os(macOS)
    func testStandaloneProfileMarkersAndDigitalSignatureUsage() throws {
        // Original self-signed certificates generated for this test; no Owner certificate/profile.
        let fixtures: [String: String] = [
            "correct":"MIIC8DCCAdigAwIBAgIJAMk05QWP9L87MA0GCSqGSIb3DQEBCwUAMCUxIzAhBgNVBAMMGlBHT1MgU3ludGhldGljIE1hcmtlciBUZXN0MB4XDTI2MTEwODA2MTQzN1oXDTI2MTEwOTA2MTQzN1owJTEjMCEGA1UEAwwaUEdPUyBTeW50aGV0aWMgTWFya2VyIFRlc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDaStq4kdghMgJ/U4AMu2gq/DiEZ0KKYiCekuqymRIHrU0rWNmlAHvUYY+cRXZayQTlHlQoYHiue0bqdy/uo+60jjaLkFztBOk7+09n65zn8fqVceTM6J0M0/b1yMcr15D8rlHHyHAgf1p0c0KwqzDDulcRY3ojH/v9ukwgC3h8a4LSQePzOm5Skvx1qcw2aeuwdMH0sjczz9ulAAXW6bvDq5fus3QbI1aY8KS7CKGoBTHJJA6Q44yWmgDafWC5kVAy5gmaGbrIfoL7aW0iNAuLfe9UfuSJB1a2z5k3xkg89TViVBjfygEqkSz01HtvVvcp4juHIx4jnW4wzevR1GsJAgMBAAGjIzAhMA4GA1UdDwEB/wQEAwIHgDAPBgkqhkiG92NkBAsEAgUAMA0GCSqGSIb3DQEBCwUAA4IBAQCvlzc8TZw7og8eVs0eTiLLqNpH4oqSC0FfeTiXjD+hcMq2dURBXHGnuvAZ/HWm/n3VwFGYulu2IcC0cRmHXkGtxDrPcWFOhmPFQVxjMdFFVe7yl1LQJLXOzSEBW4Rj2tvCienL6nqd8ezSoKsasNQalniM5D1mQdzazgNhZesKu5qTnJ2Po09Z+U5FUuW37mn4JUVLYZ95FHtdH7XeNBGLVSqHjDstzyQcWD78bQvkfojU1w4tCZ6VfpWRR32SILy6qbVfUvxLTrNssivUHBcTYDZ3uf/fHjZSHsCqiDRYB8eyRXDvKPzvBdWvCtM9t0mrM6VR11KkPws691eGTIvr",
            "shortened":"MIIC7zCCAdegAwIBAgIJAMYJ8csAA06/MA0GCSqGSIb3DQEBCwUAMCUxIzAhBgNVBAMMGlBHT1MgU3ludGhldGljIE1hcmtlciBUZXN0MB4XDTI2MTEwODA2MTQzN1oXDTI2MTEwOTA2MTQzN1owJTEjMCEGA1UEAwwaUEdPUyBTeW50aGV0aWMgTWFya2VyIFRlc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDaStq4kdghMgJ/U4AMu2gq/DiEZ0KKYiCekuqymRIHrU0rWNmlAHvUYY+cRXZayQTlHlQoYHiue0bqdy/uo+60jjaLkFztBOk7+09n65zn8fqVceTM6J0M0/b1yMcr15D8rlHHyHAgf1p0c0KwqzDDulcRY3ojH/v9ukwgC3h8a4LSQePzOm5Skvx1qcw2aeuwdMH0sjczz9ulAAXW6bvDq5fus3QbI1aY8KS7CKGoBTHJJA6Q44yWmgDafWC5kVAy5gmaGbrIfoL7aW0iNAuLfe9UfuSJB1a2z5k3xkg89TViVBjfygEqkSz01HtvVvcp4juHIx4jnW4wzevR1GsJAgMBAAGjIjAgMA4GA1UdDwEB/wQEAwIHgDAOBggqhkiG92MECwQCBQAwDQYJKoZIhvcNAQELBQADggEBAE55Sjl15Y2qod/53P+pAHVWYJlcvLrNDCNKPSHoqzTlwuw7iKxj+pQpQDe9leF7VK5yyxG9L1EOjarmGJMCVVlpnyWY7LKkb7cIEgUh5BHn9NbuA07uI+EhkbVD1kCLEMaNezwbBNXZQCAPrgOa2EvwCELQgeVEOOaXvLjQ5+1l+rUJWbOpYtaqpyAnIH0opFkOPpnQtQLFrlgJMk1gdEb9QIySrQ/8sEpaxFkvSFS2n4ZNETwcnJGO5PErQzCPOi71rL8EdIfq5lZ4+EHnQRud9cGwsDflWSuKR2Jgt8szM/hsvooIf/LFzR5uMqKMnMFvK/w/LBVWN60Gsb8kGV0=",
            "eku":"MIIC9TCCAd2gAwIBAgIJAKr6Z+hanGorMA0GCSqGSIb3DQEBCwUAMCUxIzAhBgNVBAMMGlBHT1MgU3ludGhldGljIE1hcmtlciBUZXN0MB4XDTI2MTEwODA2MTQzN1oXDTI2MTEwOTA2MTQzN1owJTEjMCEGA1UEAwwaUEdPUyBTeW50aGV0aWMgTWFya2VyIFRlc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDaStq4kdghMgJ/U4AMu2gq/DiEZ0KKYiCekuqymRIHrU0rWNmlAHvUYY+cRXZayQTlHlQoYHiue0bqdy/uo+60jjaLkFztBOk7+09n65zn8fqVceTM6J0M0/b1yMcr15D8rlHHyHAgf1p0c0KwqzDDulcRY3ojH/v9ukwgC3h8a4LSQePzOm5Skvx1qcw2aeuwdMH0sjczz9ulAAXW6bvDq5fus3QbI1aY8KS7CKGoBTHJJA6Q44yWmgDafWC5kVAy5gmaGbrIfoL7aW0iNAuLfe9UfuSJB1a2z5k3xkg89TViVBjfygEqkSz01HtvVvcp4juHIx4jnW4wzevR1GsJAgMBAAGjKDAmMA4GA1UdDwEB/wQEAwIHgDAUBgNVHSUEDTALBgkqhkiG92NkBAswDQYJKoZIhvcNAQELBQADggEBABVAl0Iw4usBc+tXziPQcSakRMPBNbX5VZm5K4CFs+MDFu55IKqdKjbd3e5kybIZEKtc+Cs9PzJNObiphmfSXezZvvO+vgBMSXrWI9Mk6JHJY4iN+o9tArvoZqDHGKsIFoak/ip+n8ta3ryS/hyPkUnfflbgIeHJkkl+gp/k7NIhmBfaxtJN2abpe0j8vaeq6CWGcl4d0vCsFtA5rAMRLUL4YpdjDIs2BecCTbcug7U7M3siVzookwWrG+3C1tAyzQUXGjANlZAV7NpuRMx8vGtmy1Hlx5XKWMp6JR25giuwkF7ykssnCes636zFktQK8JdZwLCVy0pCdlzcPri7yFA=",
            "intermediate":"MIIC8TCCAdmgAwIBAgIJAMY79spW+KjKMA0GCSqGSIb3DQEBCwUAMCUxIzAhBgNVBAMMGlBHT1MgU3ludGhldGljIE1hcmtlciBUZXN0MB4XDTI2MTEwODA2MTQzN1oXDTI2MTEwOTA2MTQzN1owJTEjMCEGA1UEAwwaUEdPUyBTeW50aGV0aWMgTWFya2VyIFRlc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDaStq4kdghMgJ/U4AMu2gq/DiEZ0KKYiCekuqymRIHrU0rWNmlAHvUYY+cRXZayQTlHlQoYHiue0bqdy/uo+60jjaLkFztBOk7+09n65zn8fqVceTM6J0M0/b1yMcr15D8rlHHyHAgf1p0c0KwqzDDulcRY3ojH/v9ukwgC3h8a4LSQePzOm5Skvx1qcw2aeuwdMH0sjczz9ulAAXW6bvDq5fus3QbI1aY8KS7CKGoBTHJJA6Q44yWmgDafWC5kVAy5gmaGbrIfoL7aW0iNAuLfe9UfuSJB1a2z5k3xkg89TViVBjfygEqkSz01HtvVvcp4juHIx4jnW4wzevR1GsJAgMBAAGjJDAiMA4GA1UdDwEB/wQEAwIHgDAQBgoqhkiG92NkBgIBBAIFADANBgkqhkiG9w0BAQsFAAOCAQEADiReCPpLm9yVeYQDXLoCYRzbpgMMiX1ySRrzs0uPGqRWBZT3qe198H5lBhsF9cJV4dPo3/Ic2PIUV1AHa+oCLIjxZiV2n9fFteQ3AJ7NA99w8oHmBFKTAn1t60onKdUsTWYvq02n7Pr76Gr6Xu3lr0TqmZhPMCoPDaRjZrWy45QxTBYgRRlUylfsPo7JxJmQJwcygyOlnvl6e+C8m+06DkECo3qvRp7fyYZ6ZwaV2Byt13wUGvM+ItYTtMzMh2S/34UvZcbyT4KVoyz3fkUtdyGXxfvWjh5Fq6yTwOECXWfpTNp7RoXZtWb7C3u7vqJEr1yp0McbA1O/LX1+lYVIoQ==",
            "wrongku":"MIIC8DCCAdigAwIBAgIJAKuJFbA6rOmCMA0GCSqGSIb3DQEBCwUAMCUxIzAhBgNVBAMMGlBHT1MgU3ludGhldGljIE1hcmtlciBUZXN0MB4XDTI2MTEwODA2MTQzN1oXDTI2MTEwOTA2MTQzN1owJTEjMCEGA1UEAwwaUEdPUyBTeW50aGV0aWMgTWFya2VyIFRlc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDaStq4kdghMgJ/U4AMu2gq/DiEZ0KKYiCekuqymRIHrU0rWNmlAHvUYY+cRXZayQTlHlQoYHiue0bqdy/uo+60jjaLkFztBOk7+09n65zn8fqVceTM6J0M0/b1yMcr15D8rlHHyHAgf1p0c0KwqzDDulcRY3ojH/v9ukwgC3h8a4LSQePzOm5Skvx1qcw2aeuwdMH0sjczz9ulAAXW6bvDq5fus3QbI1aY8KS7CKGoBTHJJA6Q44yWmgDafWC5kVAy5gmaGbrIfoL7aW0iNAuLfe9UfuSJB1a2z5k3xkg89TViVBjfygEqkSz01HtvVvcp4juHIx4jnW4wzevR1GsJAgMBAAGjIzAhMA4GA1UdDwEB/wQEAwIFIDAPBgkqhkiG92NkBAsEAgUAMA0GCSqGSIb3DQEBCwUAA4IBAQBrOeqbfaEvQ/0cM44uLJ+jP8BTBtJXnM9Gy9TrHrn+zwxPBi6zZXs4FUjIA/Z5sUozb/FjdORP3uZECCDAw8xD5DZh9PTg9dHQNm8TtRW81+qV+ko/PSsEge6txmldad41ogBvdIWjZDTxRcI8pe6YHLcURyMLlmwdVbMM7jHx8k26782GVS/r+/TtI5xUl71bnwyrH6U9PgLpYkTNa6MOimXLdos2K0ArnaJuYzYDBOAH53UJPJW11jbxkALOjHLBnWDakaW7VSfnz8QTAXFh/2C7SPQApkTM2+xxBGQkLJqGGonOHg8hOf3TToMGVX+Rbf2BC+IsWEtyp/8KVeYw"
        ]
        func certificate(_ name: String) throws -> SecCertificate {
            try XCTUnwrap(SecCertificateCreateWithData(nil, try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixtures[name]))) as CFData))
        }
        let correct = try certificate("correct")
        XCTAssertTrue(RuntimeSigningInspector.hasCertificateMarker(correct, oid: "1.2.840.113635.100.4.11"))
        XCTAssertTrue(RuntimeSigningInspector.certificateAllowsDigitalSignature(correct))
        for wrong in ["shortened", "eku", "intermediate"] {
            XCTAssertFalse(RuntimeSigningInspector.hasCertificateMarker(try certificate(wrong), oid: "1.2.840.113635.100.4.11"), wrong)
        }
        XCTAssertTrue(RuntimeSigningInspector.hasCertificateMarker(try certificate("intermediate"), oid: "1.2.840.113635.100.6.2.1"))
        XCTAssertFalse(RuntimeSigningInspector.certificateAllowsDigitalSignature(try certificate("wrongku")))
        XCTAssertThrowsError(try RuntimeSigningInspector.validateProfileSignerChain([correct, try certificate("intermediate"), correct]))
    }
#endif

    func testDeviceDiagnosticsExposeOnlyFixedStageAndNumericReason() throws {
        let samples: [(Data, Int32)] = [
            (Data("SYNTHETIC_PRIVATE_TEXT_MUST_NOT_APPEAR".utf8), 1),
            (try json(["SPHardwareDataType": []]), 2),
            (try json(["SPHardwareDataType": [["platform_UUID": device]]]), 3),
            (try json(["SPHardwareDataType": [["provisioning_UDID": "SYNTHETIC_PRIVATE_TEXT_MUST_NOT_APPEAR"]]]), 4)
        ]
        for (bytes, code) in samples {
            XCTAssertThrowsError(try RuntimeSigningInspector.provisioningUDID(from: bytes)) { error in
                let diagnostic = error as? RuntimeSigningDiagnosticFailure
                XCTAssertEqual(diagnostic?.stage, .deviceParse); XCTAssertEqual(diagnostic?.status, code)
                XCTAssertEqual(diagnostic?.reason, .deviceEvidenceUnavailable)
                XCTAssertFalse(String(describing: error).contains("SYNTHETIC_PRIVATE_TEXT_MUST_NOT_APPEAR"))
                XCTAssertFalse(String(describing: error).contains(self.device))
            }
        }
        XCTAssertThrowsError(try RuntimeSigningInspector.provisioningUDID(from: Data(repeating: 32, count: 262_145))) { error in
            XCTAssertEqual((error as? RuntimeSigningDiagnosticFailure)?.stage, .deviceOutputLimit)
        }
        XCTAssertEqual(RuntimeSigningDiagnosticFailure(stage: .dynamicValidity, status: -1).reason, .selfSignatureInvalid)
        for stage: RuntimeSigningDiagnosticFailure.Stage in [.deviceReadConfiguration, .deviceLaunch, .deviceRead, .deviceOutputLimit, .deviceTimeout, .deviceExit] {
            XCTAssertEqual(RuntimeSigningDiagnosticFailure(stage: stage, status: 1).reason, .deviceEvidenceUnavailable)
        }
    }

}
