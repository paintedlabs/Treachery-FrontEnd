//
//  ScreenshotTests.swift
//  Treachery-iOSUITests
//
//  App Store screenshot automation via Fastlane snapshot.
//  Run with: fastlane screenshots
//
//  WARNING: these tests run against PRODUCTION Firebase. Every one taps
//  "Play as Guest", which creates a real anonymous auth user, and the captured
//  screens show whatever live Firestore returns. There is no offline or mock
//  mode: SnapshotHelper passes --FASTLANE_SNAPSHOT to the app, but no app code
//  reads it. Deterministic screenshots would need the app to check that launch
//  argument at startup and point FirebaseManager / FirestoreManager at seeded
//  fixtures or the Firebase emulator instead of production.
//
//  Because of that, `fastlane test` skips this class (skip_testing in the
//  Fastfile). Running the scheme's tests from Xcode does not, so deselect
//  ScreenshotTests in the test navigator when running tests locally.
//

import XCTest

final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Login / Welcome

    @MainActor
    func testScreenshot01_LoginScreen() throws {
        // The app launches to the login screen when unauthenticated
        let title = app.staticTexts["Treachery"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Login screen should appear")

        // Wait for the form fade-in animation
        sleep(1)

        snapshot("01_LoginScreen")
    }

    // MARK: - Home Screen (via Guest Login)

    @MainActor
    func testScreenshot02_HomeScreen() throws {
        let guestButton = app.buttons["Play as Guest"]
        XCTAssertTrue(guestButton.waitForExistence(timeout: 10), "Guest button should appear")
        guestButton.tap()

        // Wait for guest auth and navigation to home
        let createGame = app.buttons["Create a new game"]
        if !createGame.waitForExistence(timeout: 15) {
            // Fallback: look for the home screen title
            let homeTitle = app.staticTexts["Treachery"]
            XCTAssertTrue(homeTitle.waitForExistence(timeout: 5), "Home screen should appear")
        }

        snapshot("02_HomeScreen")
    }

    // MARK: - Create Game

    @MainActor
    func testScreenshot03_CreateGame() throws {
        signInAsGuest()

        let createGame = findButton(labels: ["Create a new game", "Create Game"])
        XCTAssertTrue(createGame.waitForExistence(timeout: 15), "Create Game button should appear")
        createGame.tap()

        // Wait for Create Game screen to load
        sleep(2)

        snapshot("03_CreateGame")
    }

    // MARK: - Join Game

    @MainActor
    func testScreenshot04_JoinGame() throws {
        signInAsGuest()

        let joinGame = findButton(labels: ["Join an existing game", "Join Game"])
        XCTAssertTrue(joinGame.waitForExistence(timeout: 15), "Join Game button should appear")
        joinGame.tap()

        // Wait for Join Game screen to load
        sleep(2)

        snapshot("04_JoinGame")
    }

    // MARK: - Game History Tab

    @MainActor
    func testScreenshot05_GameHistory() throws {
        signInAsGuest()

        // Wait for home to fully load
        sleep(2)

        // Tap the History tab
        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10), "History tab should exist")
        historyTab.tap()

        sleep(1)

        snapshot("05_GameHistory")
    }

    // MARK: - Profile Tab

    @MainActor
    func testScreenshot06_Profile() throws {
        signInAsGuest()

        // Wait for home to fully load
        sleep(2)

        // Tap the Profile tab
        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10), "Profile tab should exist")
        profileTab.tap()

        sleep(1)

        snapshot("06_Profile")
    }

    // MARK: - Helpers

    /// Sign in as guest and wait for the home screen to appear.
    private func signInAsGuest() {
        let guestButton = app.buttons["Play as Guest"]
        guard guestButton.waitForExistence(timeout: 10) else { return }
        guestButton.tap()

        // Wait for the home screen to appear after auth
        let _ = app.tabBars.firstMatch.waitForExistence(timeout: 15)
    }

    /// Find the first existing button matching any of the given accessibility labels.
    private func findButton(labels: [String]) -> XCUIElement {
        for label in labels {
            let button = app.buttons[label]
            if button.exists { return button }
        }
        // Return the first one as fallback (will fail waitForExistence if missing)
        return app.buttons[labels.first!]
    }
}
