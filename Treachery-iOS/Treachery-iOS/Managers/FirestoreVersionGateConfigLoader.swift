//
//  FirestoreVersionGateConfigLoader.swift
//  Treachery-iOS
//

import Foundation
import FirebaseFirestore

/// Reads `config/ios` from Firestore. The rules let anyone read `config/*`,
/// so this works before sign-in.
struct FirestoreVersionGateConfigLoader: VersionGateConfigLoading {
    func loadConfig() async throws -> VersionGateConfig? {
        // The default source asks the server. When the SDK already knows it's
        // offline, it answers from its local cache instead: the last copy this
        // device read, or an error if it never read one.
        let snapshot = try await Firestore.firestore()
            .collection("config")
            .document("ios")
            .getDocument()
        guard let data = snapshot.data() else { return nil }
        return VersionGateConfig(firestoreData: data)
    }
}

extension VersionGateConfig {
    /// Maps the raw document leniently, because people type these fields into
    /// the Firebase console by hand. A field of the wrong type reads as
    /// absent, and `min_build` also accepts a string of digits, since string
    /// is the console's default field type.
    init(firestoreData data: [String: Any]) {
        self.init(
            minimumBuild: Self.integer(from: data["min_build"]),
            message: Self.text(from: data["message"]),
            storeURL: Self.storeURL(from: data["store_url"])
        )
    }

    private static func integer(from value: Any?) -> Int? {
        if let number = value as? Int { return number }
        return text(from: value).flatMap { Int($0) }
    }

    private static func text(from value: Any?) -> String? {
        let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    /// Only https and App Store links. Other schemes either couldn't be opened,
    /// leaving an Update button that does nothing, or (plain http) would send
    /// people told to update to a page any network on the way could rewrite.
    private static func storeURL(from value: Any?) -> URL? {
        guard let text = text(from: value),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              ["https", "itms-apps", "itms-appss"].contains(scheme),
              url.host() != nil
        else { return nil }
        return url
    }
}
