import Testing
import Foundation
@testable import Treachery_iOS

struct FirebaseBackendTests {

    @Test func plainLaunchUsesProduction() {
        #expect(FirebaseBackend.forLaunch(arguments: ["Treachery-iOS"], environment: [:]) == .production)
    }

    @Test func useEmulatorsArgumentSelectsTheLocalEmulators() {
        let backend = FirebaseBackend.forLaunch(arguments: ["Treachery-iOS", "-useEmulators"], environment: [:])
        #expect(backend == .localEmulators)
    }

    @Test func unitTestHostSelectsTheLocalEmulators() {
        let environment = ["XCTestConfigurationFilePath": "/tmp/Treachery.xctestconfiguration"]
        #expect(FirebaseBackend.forLaunch(arguments: ["Treachery-iOS"], environment: environment) == .localEmulators)
    }

    /// Reads back what the app delegate actually configured in the app hosting these tests.
    @Test func thisTestHostIsKeptOffProduction() throws {
        let app = try #require(FirebaseBackend.configuredDefaultApp)
        #expect(app.projectID == LocalEmulators.projectID)
        #expect(app.googleAppID == LocalEmulators.googleAppID)
    }

    /// The emulator app's own "app-" scheme isn't registered, so without the bundled
    /// CLIENT_ID, Send Code would hit PhoneAuthProvider's fatalError in emulator mode.
    @Test func emulatorPhoneSignInCallbackSchemeIsRegistered() throws {
        let app = try #require(FirebaseBackend.configuredDefaultApp)
        let schemes = registeredURLSchemes()
        let scheme = phoneAuthCallbackScheme(clientID: app.clientID, googleAppID: app.googleAppID, registeredSchemes: schemes)

        #expect(schemes.contains { $0.caseInsensitiveCompare(scheme) == .orderedSame })
    }

    @Test func emulatorOptionsPassFirebaseValidation() {
        // FIRInstallations.m validateAPIKey: 39 URL-safe characters starting with "A".
        let apiKey = LocalEmulators.apiKey
        #expect(apiKey.count == 39)
        #expect(apiKey.hasPrefix("A"))
        #expect(apiKey.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        // FIRApp.m validateAppIDFormat: "1:<project number>:ios:<hex>".
        #expect(LocalEmulators.googleAppID.wholeMatch(of: #/1:\d+:ios:[0-9a-f]+/#) != nil)
        // Same project as the web playtest, so both clients can join the same games.
        #expect(LocalEmulators.projectID == "demo-test")
    }
}

/// Checks the bundled GoogleService-Info.plist against the app it ships in.
struct BundledFirebaseConfigTests {

    private func googleServiceInfo() throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test func configIsThisAppsFirebaseRegistration() throws {
        let info = try googleServiceInfo()
        #expect(info["BUNDLE_ID"] as? String == Bundle.main.bundleIdentifier)
        #expect(info["PROJECT_ID"] as? String == "treachery-71922")
        #expect(info["GOOGLE_APP_ID"] as? String != FirebaseAuthKeychainMigration.legacyAppID)
    }

    /// PhoneAuthProvider calls fatalError on "Send Code" when its callback scheme isn't
    /// registered: the reversed CLIENT_ID if registered, else "app-" plus the dashed
    /// GOOGLE_APP_ID (PhoneAuthProvider.swift ~L100-115 and ~L640-665).
    @Test func phoneSignInCallbackSchemesAreRegistered() throws {
        let info = try googleServiceInfo()
        let appID = try #require(info["GOOGLE_APP_ID"] as? String)
        let reversedClientID = try #require(info["REVERSED_CLIENT_ID"] as? String)
        let schemes = registeredURLSchemes()

        #expect(schemes.contains(reversedClientID))
        #expect(schemes.contains("app-" + appID.replacingOccurrences(of: ":", with: "-")))
    }
}

/// The URL schemes this app's Info.plist registers.
private func registeredURLSchemes() -> [String] {
    let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
    return urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
}

/// The callback scheme PhoneAuthProvider picks (PhoneAuthProvider.swift `init(auth:)`,
/// ~L643-664): the reversed CLIENT_ID if that is registered, else "app-" plus the
/// GOOGLE_APP_ID with its colons turned into dashes.
private func phoneAuthCallbackScheme(clientID: String?, googleAppID: String, registeredSchemes: [String]) -> String {
    if let clientID {
        let reversed = clientID.components(separatedBy: ".").reversed().joined(separator: ".")
        if registeredSchemes.contains(where: { $0.caseInsensitiveCompare(reversed) == .orderedSame }) {
            return reversed
        }
    }
    return "app-" + googleAppID.replacingOccurrences(of: ":", with: "-")
}
