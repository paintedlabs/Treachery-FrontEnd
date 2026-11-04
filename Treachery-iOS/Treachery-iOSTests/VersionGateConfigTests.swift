import Testing
import Foundation
@testable import Treachery_iOS

/// Mapping the hand-edited `config/ios` document into `VersionGateConfig`.
struct VersionGateConfigTests {

    @Test func readsEveryFieldFromFirestoreTypes() {
        let config = VersionGateConfig(firestoreData: [
            "min_build": NSNumber(value: 57),
            "message": "Update to keep playing.",
            "store_url": "https://apps.apple.com/app/id0000000000",
        ])
        #expect(config == VersionGateConfig(
            minimumBuild: 57,
            message: "Update to keep playing.",
            storeURL: URL(string: "https://apps.apple.com/app/id0000000000")
        ))
    }

    @Test func emptyDocumentSetsNothing() {
        let config = VersionGateConfig(firestoreData: [:])
        #expect(config == VersionGateConfig(minimumBuild: nil, message: nil, storeURL: nil))
    }

    @Test func minimumBuildAcceptsStringOfDigits() {
        // String is the Firebase console's default field type.
        let config = VersionGateConfig(firestoreData: ["min_build": " 57 "])
        #expect(config.minimumBuild == 57)
    }

    @Test func fieldsOfTheWrongTypeReadAsAbsent() {
        let config = VersionGateConfig(firestoreData: [
            "min_build": "soon",
            "message": 42,
            "store_url": ["https://apps.apple.com/app/id0000000000"],
        ])
        #expect(config == VersionGateConfig(minimumBuild: nil, message: nil, storeURL: nil))
    }

    @Test func blankMessageReadsAsAbsent() {
        let config = VersionGateConfig(firestoreData: ["message": "  \n"])
        #expect(config.message == nil)
    }

    @Test(arguments: [
        ("https://apps.apple.com/app/id0000000000", true),
        ("itms-apps://apps.apple.com/app/id0000000000", true),
        ("itms-appss://apps.apple.com/app/id0000000000", true),
        // Plain http could be rewritten on the way by any network.
        ("http://apps.apple.com/app/id0000000000", false),
        ("apps.apple.com/app/id0000000000", false),
        ("https:apps.apple.com", false),
        ("mailto:support@example.com", false),
    ])
    func storeURLMustBeHTTPSOrAnAppStoreLink(link: String, isKept: Bool) {
        let config = VersionGateConfig(firestoreData: ["store_url": link])
        #expect((config.storeURL != nil) == isKept)
    }
}
