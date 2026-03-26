//
//  Treachery_iOSUITestsLaunchTests.swift
//  Treachery-iOSUITests
//
//  Created by Luke Solomon on 9/10/24.
//

import XCTest

final class Treachery_iOSUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify the app launches and shows either login or home screen
        let treacheryTitle = app.staticTexts["Treachery"]
        XCTAssertTrue(treacheryTitle.waitForExistence(timeout: 10),
                      "App should launch and display the Treachery title")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
