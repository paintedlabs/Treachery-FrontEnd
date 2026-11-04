//
//  AppInfo.swift
//  Treachery-iOS
//

import Foundation

/// What the Profile screen's About section says about the app.
enum AppInfo {
    /// The privacy policy. App Review requires a link to it inside the app,
    /// and App Store Connect lists the same URL.
    static let privacyPolicyURL = URL(string: "https://treachery-71922.web.app/privacy")!

    /// Help, reporting a player, and deleting an account on request. App
    /// Review asks for an easy way to contact the developer, and App Store
    /// Connect lists the same page as the Support URL.
    static let supportURL = URL(string: "https://treachery-71922.web.app/support")!

    /// The notice the Wizards of the Coast Fan Content Policy requires, word
    /// for word. Shown verbatim and never localized.
    static let fanContentNotice = "Treachery is unofficial Fan Content permitted under the Fan Content Policy. "
        + "Not approved/endorsed by Wizards. Portions of the materials used are property of Wizards of the Coast. "
        + "©Wizards of the Coast LLC."

    /// The version and build as people quote them, such as "1.2 (34)".
    /// - Parameter infoDictionary: The app bundle's Info.plist values.
    static func version(from infoDictionary: [String: Any]?) -> String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String
        let build = infoDictionary?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil): return version
        case let (nil, build?): return "(\(build))"
        case (nil, nil): return String(localized: "Unknown", comment: "Shown as the app version when it can't be read")
        }
    }
}
