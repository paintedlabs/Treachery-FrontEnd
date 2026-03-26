//
//  Treachery_iOSUITests.swift
//  Treachery-iOSUITests
//
//  Created by Luke Solomon on 9/10/24.
//

import XCTest

final class Treachery_iOSUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Login Screen

    @MainActor
    func testLoginScreenShowsAllElements() throws {
        // Title
        let title = app.staticTexts["Treachery"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "App title should be visible")

        // Email and password fields
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.exists, "Email field should be visible")

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.exists, "Password field should be visible")

        // Sign In button
        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.exists, "Sign In button should be visible")

        // Navigation links
        let createAccount = app.buttons["Create Account"]
        XCTAssertTrue(createAccount.exists, "Create Account link should be visible")

        let forgotPassword = app.buttons["Forgot Password?"]
        XCTAssertTrue(forgotPassword.exists, "Forgot Password link should be visible")

        // Guest button
        let guestButton = app.buttons["Play as Guest"]
        XCTAssertTrue(guestButton.exists, "Play as Guest button should be visible")
    }

    @MainActor
    func testSignInButtonDisabledWithEmptyFields() throws {
        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5))

        // Tap sign in with empty fields — should not crash or navigate
        signInButton.tap()

        // Should still be on login screen
        let title = app.staticTexts["Treachery"]
        XCTAssertTrue(title.exists, "Should remain on login screen with empty fields")
    }

    @MainActor
    func testCanTypeInEmailAndPasswordFields() throws {
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))

        emailField.tap()
        emailField.typeText("test@example.com")
        XCTAssertEqual(emailField.value as? String, "test@example.com")

        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("password123")
    }

    // MARK: - Navigation to Create Account

    @MainActor
    func testNavigateToCreateAccount() throws {
        let createAccount = app.buttons["Create Account"]
        XCTAssertTrue(createAccount.waitForExistence(timeout: 5))

        createAccount.tap()

        // Should show the sign up view
        let createAccountTitle = app.staticTexts["Create Account"]
        XCTAssertTrue(createAccountTitle.waitForExistence(timeout: 3),
                      "Should navigate to Create Account screen")

        // Verify sign up form elements
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.exists, "Sign up email field should be visible")

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.exists, "Sign up password field should be visible")

        let confirmPasswordField = app.secureTextFields["Confirm Password"]
        XCTAssertTrue(confirmPasswordField.exists, "Confirm password field should be visible")
    }

    @MainActor
    func testNavigateToCreateAccountAndBack() throws {
        let createAccount = app.buttons["Create Account"]
        XCTAssertTrue(createAccount.waitForExistence(timeout: 5))
        createAccount.tap()

        // Wait for navigation
        let createTitle = app.staticTexts["Create Account"]
        XCTAssertTrue(createTitle.waitForExistence(timeout: 3))

        // Go back
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists {
            backButton.tap()
        }

        // Should be back on login
        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 3),
                      "Should navigate back to login screen")
    }

    // MARK: - Navigation to Forgot Password

    @MainActor
    func testNavigateToForgotPassword() throws {
        let forgotPassword = app.buttons["Forgot Password?"]
        XCTAssertTrue(forgotPassword.waitForExistence(timeout: 5))

        forgotPassword.tap()

        // Should show the forgot password view
        let resetButton = app.buttons["Send Reset Link"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 3),
                      "Should navigate to Forgot Password screen")
    }

    // MARK: - Navigation to Phone Auth

    @MainActor
    func testNavigateToPhoneAuth() throws {
        let phoneSignIn = app.buttons["Sign In with Phone"]
        XCTAssertTrue(phoneSignIn.waitForExistence(timeout: 5))

        phoneSignIn.tap()

        // Should navigate to phone auth — look for phone number field
        let phoneField = app.textFields.firstMatch
        XCTAssertTrue(phoneField.waitForExistence(timeout: 3),
                      "Should navigate to Phone Auth screen")
    }

    // MARK: - Accessibility

    @MainActor
    func testLoginScreenAccessibility() throws {
        // Verify key elements have accessibility traits
        let title = app.staticTexts["Treachery"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        // The title should exist and be accessible
        XCTAssertTrue(title.isHittable, "Title should be accessible")

        // Buttons should be hittable
        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.isHittable, "Sign In button should be hittable")

        let guestButton = app.buttons["Play as Guest"]
        XCTAssertTrue(guestButton.isHittable, "Guest button should be hittable")
    }
}
