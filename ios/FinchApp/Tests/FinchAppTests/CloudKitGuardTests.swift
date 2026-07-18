import XCTest
@testable import FinchApp

/// The CloudKit trap-guard's iOS decision path: entitlements are read from the
/// embedded provisioning profile (the ubiquityIdentityToken heuristic false-
/// passed on an iCloud-signed-in device whose binary had no iCloud
/// entitlements — CKContainer trapped at launch, 2026-07-18).
final class CloudKitGuardTests: XCTestCase {
    private let containerID = "iCloud.com.juchengquan.finch"

    private func profileBlob(entitlements plist: String) -> Data {
        // A provisioning profile is a CMS blob wrapping an XML plist — junk
        // bytes on both sides are the realistic shape.
        var data = Data([0x30, 0x82, 0x0a, 0xff, 0x06, 0x09])   // DER-ish prefix junk
        data.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Name</key><string>iOS Team Provisioning Profile</string>
        <key>Entitlements</key><dict>\(plist)</dict>
        </dict></plist>
        """.utf8))
        data.append(Data([0x00, 0xde, 0xad, 0xbe, 0xef]))       // signature junk
        return data
    }

    func test_parse_extractsEntitlementsFromBlob() throws {
        let blob = profileBlob(entitlements: """
        <key>application-identifier</key><string>TEAM.com.juchengquan.finch</string>
        <key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>
        """)
        let ents = try XCTUnwrap(CloudKitSyncService.parseProvisioningEntitlements(from: blob))
        XCTAssertEqual(ents["application-identifier"] as? String, "TEAM.com.juchengquan.finch")
        XCTAssertEqual(ents["com.apple.developer.icloud-services"] as? [String], ["CloudKit"])
    }

    func test_parse_nilOnGarbage() {
        XCTAssertNil(CloudKitSyncService.parseProvisioningEntitlements(from: Data([0x01, 0x02, 0x03])))
    }

    func test_permitted_requiresServicesANDContainerId() {
        // Full grant → permitted.
        XCTAssertTrue(CloudKitSyncService.cloudKitPermitted(byEntitlements: [
            "com.apple.developer.icloud-services": ["CloudDocuments", "CloudKit"],
            "com.apple.developer.icloud-container-identifiers": [containerID],
        ], containerID: containerID))
        // The stripped personal-team profile (no iCloud keys at all) → denied.
        XCTAssertFalse(CloudKitSyncService.cloudKitPermitted(byEntitlements: [
            "application-identifier": "TEAM.com.juchengquan.finch",
        ], containerID: containerID))
        // Services without our container id → denied (construction traps).
        XCTAssertFalse(CloudKitSyncService.cloudKitPermitted(byEntitlements: [
            "com.apple.developer.icloud-services": ["CloudKit"],
            "com.apple.developer.icloud-container-identifiers": ["iCloud.other.app"],
        ], containerID: containerID))
        // Container id without CloudKit service → denied (first use traps).
        XCTAssertFalse(CloudKitSyncService.cloudKitPermitted(byEntitlements: [
            "com.apple.developer.icloud-services": ["CloudDocuments"],
            "com.apple.developer.icloud-container-identifiers": [containerID],
        ], containerID: containerID))
        // Anonymous CloudKit counts.
        XCTAssertTrue(CloudKitSyncService.cloudKitPermitted(byEntitlements: [
            "com.apple.developer.icloud-services": ["CloudKit-Anonymous"],
            "com.apple.developer.icloud-container-identifiers": [containerID],
        ], containerID: containerID))
    }

    func test_parse_thenPermit_endToEnd() throws {
        let blob = profileBlob(entitlements: """
        <key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>
        <key>com.apple.developer.icloud-container-identifiers</key><array><string>\(containerID)</string></array>
        """)
        let ents = try XCTUnwrap(CloudKitSyncService.parseProvisioningEntitlements(from: blob))
        XCTAssertTrue(CloudKitSyncService.cloudKitPermitted(byEntitlements: ents, containerID: containerID))
    }
}
