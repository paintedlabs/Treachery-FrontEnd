import Testing
import Foundation
@testable import Treachery_iOS

@Suite("About section")
struct AppInfoTests {

    @Test("Version and build read as people quote them", arguments: [
        (["CFBundleShortVersionString": "1.2", "CFBundleVersion": "34"], "1.2 (34)"),
        (["CFBundleShortVersionString": "1.2"], "1.2"),
        (["CFBundleVersion": "34"], "(34)"),
        ([:], "Unknown"),
    ] as [([String: String], String)])
    func version(infoDictionary: [String: String], expected: String) {
        #expect(AppInfo.version(from: infoDictionary) == expected)
    }

    @Test func missingInfoDictionaryReadsAsUnknown() {
        #expect(AppInfo.version(from: nil) == "Unknown")
    }

    @Test func privacyPolicyLinksToTheHostedPage() {
        #expect(AppInfo.privacyPolicyURL.absoluteString == "https://treachery-71922.web.app/privacy")
    }

    /// The Fan Content Policy asks for this notice word for word.
    @Test func fanContentNoticeIsWordForWord() {
        #expect(AppInfo.fanContentNotice == """
            Treachery is unofficial Fan Content permitted under the Fan Content Policy. \
            Not approved/endorsed by Wizards. Portions of the materials used are property of Wizards of the Coast. \
            ©Wizards of the Coast LLC.
            """)
    }
}
