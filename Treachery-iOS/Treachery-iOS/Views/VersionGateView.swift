//
//  VersionGateView.swift
//  Treachery-iOS
//

import SwiftUI

/// Runs the launch version check and shows `content` only once it lets this
/// build in. Until then it shows the launch splash, or the update screen if
/// this build is too old.
struct VersionGateView<Content: View>: View {
    @ObservedObject var model: VersionGateViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let content: Content

    init(model: VersionGateViewModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    var body: some View {
        // The tasks below hang off a ZStack, one container that lasts as long
        // as the gate. A Group's modifiers apply to each of its members, which
        // would tie the tasks to whichever branch happens to be showing.
        ZStack {
            switch model.state {
            case .checking:
                LaunchSplashView()
            case .allowed:
                content
            case .updateRequired(let message, let storeURL):
                UpdateRequiredView(message: message, storeURL: storeURL)
            }
        }
        .task {
            await model.checkVersion()
        }
        .task(id: scenePhase) {
            // Coming back to the app re-reads the config, so people already on
            // the update screen get in once an operator lowers min_build.
            guard scenePhase == .active else { return }
            await model.recheckIfBlocked()
        }
    }
}
