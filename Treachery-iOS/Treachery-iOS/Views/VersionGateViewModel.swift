//
//  VersionGateViewModel.swift
//  Treachery-iOS
//

import Foundation
import os

/// Decides at launch whether this build may be used, by comparing its build
/// number with `min_build` in Firestore's `config/ios`. It is the kill switch
/// for shipped binaries: staging and production share one Firebase project, so
/// a build the backend can no longer support has to be told to update.
///
/// The check fails open. A read error, a missing document, a build number that
/// isn't an integer, a read slower than `timeout` or a cancelled check all let
/// the user in, so the gate can't strand anyone on its own.
@MainActor
final class VersionGateViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: VersionGateState

    // MARK: - Properties

    private let loader: any VersionGateConfigLoading
    private let installedBuild: String?
    private let clock: any Clock<Duration>
    private let timeout: Duration
    private let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "VersionGate")
    private let signposter = OSSignposter(subsystem: "com.Solomon.Treachery-iOS", category: "VersionGate")
    /// Set only while the launch check runs. It times the check for Instruments
    /// and the log, since every Release launch waits on it.
    private var launchCheckTiming: LaunchCheckTiming?

    // MARK: - Init

    /// - Parameters:
    ///   - installedBuild: This binary's `CFBundleVersion`.
    ///   - timeout: The longest launch waits for `config/ios` before letting the user in.
    ///   - initialState: `.checking` runs the launch check; `.allowed` skips it.
    init(
        loader: any VersionGateConfigLoading,
        installedBuild: String?,
        clock: any Clock<Duration>,
        timeout: Duration,
        initialState: VersionGateState = .checking
    ) {
        self.loader = loader
        self.installedBuild = installedBuild
        self.clock = clock
        self.timeout = timeout
        self.state = initialState
    }

    // MARK: - Launch Check

    /// Reads `config/ios` once and settles `state` within `timeout`.
    ///
    /// The read races the clock: whichever finishes first decides, and the
    /// other is cancelled. A read that lands after the timeout is ignored, so
    /// nobody is pulled out of the app once they're in. Cancelling the check
    /// lets the user in at once. Firestore can't cancel a read in flight, so
    /// this can return a while after `state` settles.
    func checkVersion() async {
        guard case .checking = state else { return }
        launchCheckTiming = LaunchCheckTiming(
            signpost: signposter.beginInterval("VersionGateCheck", id: signposter.makeSignpostID()),
            // `self.` keeps Darwin's clock() function out of the lookup, which
            // would otherwise stop Swift opening the `any Clock` here.
            elapsed: Self.stopwatch(on: self.clock)
        )
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.settleFromRead() }
            group.addTask { await self.settleAfterTimeout() }
            _ = await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Re-check

    /// Reads `config/ios` again while the update screen is up, so lowering or
    /// removing `min_build` lets people back in without relaunching. Only a
    /// successful read changes anything, and a re-check never blocks a build
    /// the launch check let in.
    func recheckIfBlocked() async {
        guard case .updateRequired = state else { return }
        do {
            let config = try await loader.loadConfig()
            // Another re-check may have let the user in during the await.
            guard case .updateRequired = state else { return }
            state = VersionGateState(config: config, installedBuild: installedBuild)
        } catch is CancellationError {
            return
        } catch {
            logger.error("Couldn't re-read config/ios; keeping the update screen: \(String(describing: error))")
        }
    }

    // MARK: - Helpers

    private func settleFromRead() async {
        do {
            let config = try await loader.loadConfig()
            let verdict = VersionGateState(config: config, installedBuild: installedBuild)
            settle(verdict, outcome: verdict == .allowed ? .allowed : .updateRequired)
        } catch is CancellationError {
            return // The timeout task settles the gate.
        } catch {
            logger.error("Couldn't read config/ios: \(String(describing: error))")
            settle(.allowed, outcome: .readFailed)
        }
    }

    /// Always settles the gate, so launch never waits longer than `timeout`.
    private func settleAfterTimeout() async {
        do {
            try await clock.sleep(for: timeout)
            settle(.allowed, outcome: .timedOut)
        } catch {
            // Cancelled. Either the read settled the gate first, and this
            // changes nothing, or the whole check was cancelled, which must not
            // leave launch waiting on a read that can't be stopped.
            settle(.allowed, outcome: .cancelled)
        }
    }

    /// Applies the first verdict only; later ones change nothing.
    private func settle(_ verdict: VersionGateState, outcome: LaunchCheckOutcome) {
        guard case .checking = state else { return }
        state = verdict
        if let timing = launchCheckTiming {
            launchCheckTiming = nil
            signposter.endInterval("VersionGateCheck", timing.signpost, "\(outcome.rawValue, privacy: .public)")
            let milliseconds = Int(timing.elapsed() / .milliseconds(1))
            let build = installedBuild ?? "unknown"
            logger.notice(
                "Version check for build \(build, privacy: .public): \(outcome.rawValue, privacy: .public) after \(milliseconds, privacy: .public) ms"
            )
        }
    }

    /// Starts timing on `clock`. The closure returns the time since then.
    private static func stopwatch<C: Clock>(on clock: C) -> () -> Duration where C.Duration == Duration {
        let start = clock.now
        return { start.duration(to: clock.now) }
    }
}

// MARK: - Launch Check Timing

private extension VersionGateViewModel {
    struct LaunchCheckTiming {
        let signpost: OSSignpostIntervalState
        let elapsed: () -> Duration
    }

    /// How the launch check ended, for the signpost and the log.
    enum LaunchCheckOutcome: String {
        case allowed
        case updateRequired = "update required"
        case readFailed = "read failed, allowed"
        case timedOut = "timed out, allowed"
        case cancelled = "cancelled, allowed"
    }
}

// MARK: - Production Wiring

extension VersionGateViewModel {
    /// The gate RootView uses: Firestore's `config/ios` against this binary's
    /// build number, with three seconds to answer before launch goes ahead.
    ///
    /// Debug builds skip the check and never read. They are always build 1, so
    /// a real `min_build` would lock out the simulator, previews, the UI tests
    /// and the screenshot lane, all of which run Debug.
    static func live() -> VersionGateViewModel {
        #if DEBUG
        let initialState = VersionGateState.allowed
        #else
        let initialState = VersionGateState.checking
        #endif
        return VersionGateViewModel(
            loader: FirestoreVersionGateConfigLoader(),
            installedBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            clock: ContinuousClock(),
            timeout: .seconds(3),
            initialState: initialState
        )
    }
}
