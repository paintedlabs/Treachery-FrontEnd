//
//  SnapshotHelper.swift
//  Fastlane snapshot helper
//
//  Based on the standard Fastlane SnapshotHelper.
//  https://github.com/fastlane/fastlane
//

import Foundation
import XCTest

var deviceLanguage = ""
var locale = ""

func setupSnapshot(_ app: XCUIApplication, waitForAnimations: Bool = true) {
    Snapshot.setupSnapshot(app, waitForAnimations: waitForAnimations)
}

func snapshot(_ name: String, waitForLoadingIndicator: Bool = true) {
    Snapshot.snapshot(name, waitForLoadingIndicator: waitForLoadingIndicator)
}

enum Snapshot {
    static var app: XCUIApplication?
    static var waitForAnimations = true
    static var cacheDirectory: URL?

    static func setupSnapshot(_ app: XCUIApplication, waitForAnimations: Bool = true) {
        Snapshot.app = app
        Snapshot.waitForAnimations = waitForAnimations

        app.launchArguments += ["--FASTLANE_SNAPSHOT"]

        // Read language and locale from Fastlane's temporary cache
        do {
            let cacheDir = try getCacheDirectory()
            Snapshot.cacheDirectory = cacheDir

            let languagePath = cacheDir.appendingPathComponent("language.txt")
            if let lang = try? String(contentsOf: languagePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
                deviceLanguage = lang
            }

            let localePath = cacheDir.appendingPathComponent("locale.txt")
            if let loc = try? String(contentsOf: localePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
                locale = loc
            }
        } catch {
            NSLog("Snapshot: Failed to read cache directory: \(error)")
        }

        if !deviceLanguage.isEmpty {
            app.launchArguments += ["-AppleLanguages", "(\(deviceLanguage))"]
        }
        if !locale.isEmpty {
            app.launchArguments += ["-AppleLocale", "\"\(locale)\""]
        }

        app.launch()
    }

    static func snapshot(_ name: String, waitForLoadingIndicator: Bool = true) {
        guard let app = Snapshot.app else {
            NSLog("Snapshot: Call setupSnapshot(app) before snapshot()")
            return
        }

        if waitForAnimations {
            sleep(1)
        }

        if waitForLoadingIndicator {
            waitForLoadingIndicatorToDisappear(within: 20)
        }

        NSLog("Snapshot: Taking screenshot '\(name)'")

        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways

        // Add attachment to current test
        if let testCase = currentTestCase() {
            testCase.add(attachment)
        }

        // Also save to Fastlane's expected output directory
        saveScreenshot(screenshot: screenshot, name: name)
    }

    // MARK: - Private Helpers

    private static func currentTestCase() -> XCTestCase? {
        // XCTestCase.perform is called on the current test instance. The class
        // must be typed as NSObject.Type: on bare AnyClass the perform(_:)
        // overload is ambiguous and fails to compile for x86_64 simulators.
        guard let currentTestClass = NSClassFromString("XCTestProbe") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("currentTestCase")
        guard currentTestClass.responds(to: selector) else { return nil }
        return currentTestClass.perform(selector)?.takeUnretainedValue() as? XCTestCase
    }

    private static func saveScreenshot(screenshot: XCUIScreenshot, name: String) {
        guard let screenshotDir = Snapshot.cacheDirectory?.appendingPathComponent("screenshots") else { return }

        // Fastlane globs this directory flat and sorts the files into per-language
        // folders itself, keying each file on the "<simulator>-" prefix. Concurrent
        // simulators report themselves as "Clone N of <device>", which has to be
        // stripped or the collected file names won't match a requested device.
        var simulator = ProcessInfo().environment["SIMULATOR_DEVICE_NAME"] ?? "Unknown"
        if let regex = try? NSRegularExpression(pattern: "Clone [0-9]+ of ") {
            simulator = regex.stringByReplacingMatches(
                in: simulator,
                range: NSRange(location: 0, length: simulator.count),
                withTemplate: ""
            )
        }

        do {
            try FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
            let filePath = screenshotDir.appendingPathComponent("\(simulator)-\(name).png")
            try screenshot.pngRepresentation.write(to: filePath, options: .atomic)
            NSLog("Snapshot: Saved to \(filePath.path)")
        } catch {
            NSLog("Snapshot: Failed to save screenshot: \(error)")
        }
    }

    /// The directory the `snapshot` action and the test runner exchange files through:
    /// snapshot writes language.txt/locale.txt into it and collects the PNGs the runner
    /// writes back into its `screenshots` subdirectory. It lives in the *host* home
    /// directory, which the simulator exposes as SIMULATOR_HOST_HOME.
    private static func getCacheDirectory() throws -> URL {
        // An explicit override wins, so a harness can redirect the exchange directory.
        if let override = UserDefaults.standard.string(forKey: "SnapshotHelperCacheDirectory"), !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        if let simulatorHostHome = ProcessInfo().environment["SIMULATOR_HOST_HOME"] {
            return URL(fileURLWithPath: simulatorHostHome)
                .appendingPathComponent("Library/Caches/tools.fastlane")
        }

        // Physical device, or a runner without the simulator environment. Fastlane
        // won't find screenshots here, but they stay inspectable after the run.
        return URL(fileURLWithPath: "/tmp/fastlane_snapshot")
    }

    private static func waitForLoadingIndicatorToDisappear(within timeout: TimeInterval) {
        guard let app = Snapshot.app else { return }

        let progressIndicators = app.activityIndicators
        let networkIndicators = app.statusBars.activityIndicators

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let stillLoading = progressIndicators.allElementsBoundByIndex.contains { $0.exists && $0.isHittable }
            let networkLoading = networkIndicators.allElementsBoundByIndex.contains { $0.exists }

            if !stillLoading && !networkLoading {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }
}
