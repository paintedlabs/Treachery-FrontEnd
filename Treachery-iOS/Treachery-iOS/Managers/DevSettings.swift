//
//  DevSettings.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import Foundation
import SwiftUI

/// Dev-only settings for testing. Compiled out of release builds entirely.
#if DEBUG
@MainActor
final class DevSettings: ObservableObject {
    static let shared = DevSettings()

    @AppStorage("devModeEnabled") var devModeEnabled = false

    private init() {}
}
#else
// Stub so `DevSettings.shared` compiles but does nothing in release.
@MainActor
final class DevSettings {
    static let shared = DevSettings()
    let devModeEnabled = false
    private init() {}
}
#endif
