//
//  VersionGate.swift
//  Treachery-iOS
//

import Foundation

/// The fields of Firestore's `config/ios` that decide whether this build may
/// run. Operators edit the document by hand in the Firebase console; see
/// "Forcing an iOS update" in docs/DEPLOYMENT.md.
struct VersionGateConfig: Equatable, Sendable {
    /// Builds numbered below this (`CFBundleVersion`) must update. Nil means
    /// no minimum is set.
    let minimumBuild: Int?
    /// Shown on the update screen in place of the default text.
    let message: String?
    /// The App Store page the Update button opens. Nil hides the button.
    let storeURL: URL?
}

/// Where the launch-time version check stands. RootView shows its auth flow
/// only once this is `.allowed`.
enum VersionGateState: Equatable, Sendable {
    /// Waiting for `config/ios`, for at most the gate's timeout.
    case checking
    /// This build may be used.
    case allowed
    /// This build is older than `min_build` and must be updated to continue.
    case updateRequired(message: String?, storeURL: URL?)
}

extension VersionGateState {
    /// The verdict for one successful read of `config/ios`.
    ///
    /// Only a minimum, plus an integer build number below it, blocks. A
    /// missing document, a missing `min_build` or a build number that isn't an
    /// integer all let the user in, so a broken document or an unusual build
    /// can't block anyone on its own.
    init(config: VersionGateConfig?, installedBuild: String?) {
        guard let config,
              let minimumBuild = config.minimumBuild,
              let build = installedBuild.flatMap({ Int($0) }),
              build < minimumBuild
        else {
            self = .allowed
            return
        }
        self = .updateRequired(message: config.message, storeURL: config.storeURL)
    }
}
