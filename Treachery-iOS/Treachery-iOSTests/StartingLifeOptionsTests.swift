import Testing
@testable import Treachery_iOS

/// The starting life totals the create screen's stepper and the lobby's menu
/// offer, both from `Game.startingLifeOptions`.
@MainActor
struct StartingLifeOptionsTests {

    @Test func everyValueFromTwentyToSixtyInStepsOfFive() {
        // The create screen's stepper range. The lobby's menu used to offer
        // only 20, 25, 30, 40 and 50, so a game created at 35, 45, 55 or 60
        // couldn't be set back to that value from the lobby.
        #expect(Game.startingLifeOptions == [20, 25, 30, 35, 40, 45, 50, 55, 60])
    }

    @Test func theCreateScreensDefaultIsOnOffer() {
        let createGame = CreateGameViewModel(
            firestoreManager: MockFirestoreManager(),
            cloudFunctions: MockCloudFunctions()
        )
        #expect(Game.startingLifeOptions.contains(createGame.startingLife))
    }
}
