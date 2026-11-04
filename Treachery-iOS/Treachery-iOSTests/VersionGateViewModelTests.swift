import Testing
import Foundation
@testable import Treachery_iOS

@MainActor
struct VersionGateViewModelTests {

    // MARK: - Helpers

    private let storeURL = URL(string: "https://apps.apple.com/app/id0000000000")

    private var updateRequired: VersionGateState {
        .updateRequired(message: "Update for the new rules.", storeURL: storeURL)
    }

    private func makeConfig(minimumBuild: Int?) -> VersionGateConfig {
        VersionGateConfig(minimumBuild: minimumBuild, message: "Update for the new rules.", storeURL: storeURL)
    }

    /// The installed build defaults to "42".
    private func makeModel(
        loader: StubVersionGateConfigLoader,
        installedBuild: String? = "42",
        clock: TestClock = TestClock(),
        initialState: VersionGateState = .checking
    ) -> VersionGateViewModel {
        VersionGateViewModel(
            loader: loader,
            installedBuild: installedBuild,
            clock: clock,
            timeout: .seconds(3),
            initialState: initialState
        )
    }

    // MARK: - Launch Check

    @Test func buildBelowMinimumRequiresUpdate() async {
        let model = makeModel(loader: StubVersionGateConfigLoader(.returns(makeConfig(minimumBuild: 43))))
        await model.checkVersion()
        #expect(model.state == updateRequired)
    }

    @Test func buildEqualToMinimumIsAllowed() async {
        let model = makeModel(loader: StubVersionGateConfigLoader(.returns(makeConfig(minimumBuild: 42))))
        await model.checkVersion()
        #expect(model.state == .allowed)
    }

    @Test func buildAboveMinimumIsAllowed() async {
        let model = makeModel(loader: StubVersionGateConfigLoader(.returns(makeConfig(minimumBuild: 41))))
        await model.checkVersion()
        #expect(model.state == .allowed)
    }

    @Test func missingDocumentLetsUserIn() async {
        let model = makeModel(loader: StubVersionGateConfigLoader(.returns(nil)))
        await model.checkVersion()
        #expect(model.state == .allowed)
    }

    @Test func documentWithoutMinimumLetsUserIn() async {
        let model = makeModel(loader: StubVersionGateConfigLoader(.returns(makeConfig(minimumBuild: nil))))
        await model.checkVersion()
        #expect(model.state == .allowed)
    }

    @Test func readErrorLetsUserIn() async {
        let model = makeModel(loader: StubVersionGateConfigLoader(.fails(URLError(.notConnectedToInternet))))
        await model.checkVersion()
        #expect(model.state == .allowed)
    }

    @Test(arguments: ["1.0.3", "build-42", "", nil] as [String?])
    func unparseableBuildNumberLetsUserIn(installedBuild: String?) async {
        let model = makeModel(
            loader: StubVersionGateConfigLoader(.returns(makeConfig(minimumBuild: 1_000))),
            installedBuild: installedBuild
        )
        await model.checkVersion()
        #expect(model.state == .allowed)
    }

    @Test(.timeLimit(.minutes(1)))
    func slowReadLetsUserInAtTheTimeout() async throws {
        let clock = TestClock()
        let model = makeModel(loader: StubVersionGateConfigLoader(.hangs), clock: clock)

        async let check: Void = model.checkVersion()
        await clock.waitForSleepers()
        #expect(clock.pendingDeadlines == [.seconds(3)])

        // Only the timer can let anyone in while the read hangs, so a timer
        // still asleep at 2.999s means the gate was still checking.
        clock.advance(by: .milliseconds(2_999))
        #expect(clock.pendingDeadlines == [.seconds(3)])

        clock.advance(by: .milliseconds(1))
        try #require(clock.pendingDeadlines.isEmpty)
        await check
        #expect(model.state == .allowed)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledCheckLetsUserIn() async {
        let clock = TestClock()
        let model = makeModel(loader: StubVersionGateConfigLoader(.hangs), clock: clock)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await model.checkVersion() }
            await clock.waitForSleepers()
            group.cancelAll()
        }
        // The read stopped without answering, so the gate let the user in itself.
        #expect(model.state == .allowed)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledCheckDoesNotWaitForTheRead() async {
        let clock = TestClock()
        let loader = StubVersionGateConfigLoader(.answersWhenReleased(makeConfig(minimumBuild: 100)))
        let model = makeModel(loader: loader, clock: clock)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await model.checkVersion() }
            await clock.waitForSleepers()
            group.cancelAll()

            // Let in while the read, which ignores cancellation like Firestore's,
            // is still out.
            _ = await model.$state.values.first { $0 != .checking }
            #expect(model.state == .allowed)

            // Its late answer would block this build; the user is already in.
            await loader.release()
        }
        #expect(model.state == .allowed)
    }

    @Test(.timeLimit(.minutes(1)))
    func readArrivingAfterTheTimeoutIsIgnored() async {
        let clock = TestClock()
        let loader = StubVersionGateConfigLoader(.answersWhenReleased(makeConfig(minimumBuild: 100)))
        let model = makeModel(loader: loader, clock: clock)

        async let check: Void = model.checkVersion()
        await clock.waitForSleepers()
        clock.advance(by: .seconds(3))
        _ = await model.$state.values.first { $0 != .checking }

        // The late answer would block this build; the user is already in.
        await loader.release()
        await check
        #expect(model.state == .allowed)
    }

    @Test func skippedGateNeverReads() async {
        let loader = StubVersionGateConfigLoader(.returns(makeConfig(minimumBuild: 100)))
        let model = makeModel(loader: loader, initialState: .allowed)
        await model.checkVersion()
        #expect(model.state == .allowed)
        #expect(await loader.loadCount == 0)
    }

    @Test func liveGateSkipsTheCheckOnlyInDebugBuilds() {
        // Debug builds are build 1 and talk to the production project, so a
        // real min_build would lock out the simulator, UI tests and screenshots.
        #if DEBUG
        #expect(VersionGateViewModel.live().state == .allowed)
        #else
        #expect(VersionGateViewModel.live().state == .checking)
        #endif
    }

    // MARK: - Re-check

    @Test func recheckLetsUserInOnceMinimumIsLowered() async {
        let loader = StubVersionGateConfigLoader(.returns(makeConfig(minimumBuild: 100)))
        let model = makeModel(loader: loader)
        await model.checkVersion()
        #expect(model.state == updateRequired)

        await loader.setBehavior(.returns(makeConfig(minimumBuild: 0)))
        await model.recheckIfBlocked()
        #expect(model.state == .allowed)
    }

    @Test func recheckKeepsUpdateScreenWhenReadFails() async {
        let loader = StubVersionGateConfigLoader(.returns(makeConfig(minimumBuild: 100)))
        let model = makeModel(loader: loader)
        await model.checkVersion()

        await loader.setBehavior(.fails(URLError(.notConnectedToInternet)))
        await model.recheckIfBlocked()
        #expect(model.state == updateRequired)
    }

    @Test func recheckNeverBlocksAnAllowedBuild() async {
        let loader = StubVersionGateConfigLoader(.returns(nil))
        let model = makeModel(loader: loader)
        await model.checkVersion()

        await loader.setBehavior(.returns(makeConfig(minimumBuild: 100)))
        await model.recheckIfBlocked()
        #expect(model.state == .allowed)
        #expect(await loader.loadCount == 1)
    }
}
