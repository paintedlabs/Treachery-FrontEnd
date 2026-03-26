//
//  PerformanceTests.swift
//  Treachery-iOSUITests
//
//  Performance tests using XCTMetric for launch time and responsiveness.
//

import XCTest

final class PerformanceTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Launch Performance

    @MainActor
    func testColdLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testWarmLaunchPerformance() throws {
        let app = XCUIApplication()
        app.launch()
        app.terminate()

        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            app.launch()
        }
    }

    // MARK: - Memory

    @MainActor
    func testMemoryOnLaunch() throws {
        let app = XCUIApplication()

        let memoryMetric = XCTMemoryMetric(application: app)

        measure(metrics: [memoryMetric]) {
            app.launch()
            // Wait for the UI to settle
            let title = app.staticTexts["Treachery"]
            _ = title.waitForExistence(timeout: 5)
            app.terminate()
        }
    }

    // MARK: - Animation Hitches

    @MainActor
    func testLoginScreenScrollPerformance() throws {
        let app = XCUIApplication()
        app.launch()

        let title = app.staticTexts["Treachery"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        // Measure animation smoothness during interaction
        let osSignpostMetric = XCTOSSignpostMetric(subsystem: "com.Solomon.Treachery-iOS",
                                                    category: "UI",
                                                    name: "LoginInteraction")

        measure(metrics: [osSignpostMetric, XCTCPUMetric()]) {
            // Interact with form fields
            let emailField = app.textFields["Email"]
            if emailField.exists {
                emailField.tap()
                emailField.typeText("perf@test.com")
            }

            let passwordField = app.secureTextFields["Password"]
            if passwordField.exists {
                passwordField.tap()
                passwordField.typeText("perftest123")
            }
        }
    }
}
