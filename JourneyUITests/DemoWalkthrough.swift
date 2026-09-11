import XCTest

/// A paced walkthrough of the app, used to record the README demo.
///
/// A recording script rather than a test. The `Journey` scheme skips it; it runs
/// under `Journey-Demo`, and `Tools/record-demo.sh` does the whole job.
@MainActor
final class DemoWalkthrough: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Run before recording starts, so permission prompts stay out of the GIF.
    func testGrantPermissions() {
        let allowLabels = ["Allow Full Access", "Allow While Using App", "Allow"]
        // Without this, XCTest's default handler answers prompts with "Don't Allow".
        addUIInterruptionMonitor(withDescription: "Permission prompt") { alert in
            for label in allowLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        let app = launchDemo()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in allowLabels {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 5) {
                button.tap()
            }
        }
        // Interacting with the app gives the interruption monitor a chance to run.
        app.swipeDown()
        XCTAssertTrue(app.buttons["New Entry"].waitForExistence(timeout: 10))
        beat(1.0)
        app.terminate()
    }

    func testRecordDemo() {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["New Entry"].waitForExistence(timeout: 10))
        mark("DEMO-START")
        beat(2.0)

        // 1. Today: the places visited, with the photos taken at each.
        app.swipeUp()
        beat(2.0)
        app.swipeDown()
        beat(1.0)

        // 2. Yesterday, and back.
        app.buttons["Previous Day"].tap()
        beat(2.2)
        app.buttons["Today"].tap()
        beat(1.2)

        // 3. Write about a place; its photos come along.
        let write = app.buttons["Write about this place"].firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()
        beat(1.2)
        let title = app.textFields["Title"]
        title.tap()
        title.typeText("Temple of Dawn")
        beat(0.5)
        let notes = app.textViews.firstMatch
        notes.tap()
        notes.typeText("Climbed the central prang before the crowds.")
        beat(1.0)
        app.buttons["Save"].tap()
        beat(2.2)

        // 4. Read the day back as a journal page, and open its photos full screen.
        app.tabBars.buttons["Calendar"].tap()
        beat(2.2)
        app.buttons["Day"].tap()
        beat(2.0)
        let photo = app.buttons["pageMedia"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        for _ in 0..<3 where !photo.isHittable {
            app.swipeUp()
            beat(1.0)
        }
        photo.tap()
        beat(1.8)
        app.swipeLeft()
        beat(1.5)
        app.buttons["Close"].tap()
        beat(1.2)

        // 5. Journals and the rest of the settings.
        app.tabBars.buttons["Settings"].tap()
        beat(2.2)
        mark("DEMO-END")
    }

    /// Wall-clock marker in the test log; `record-demo.sh` trims the capture to them.
    private func mark(_ label: String) {
        print("\(label) \(Date().timeIntervalSince1970)")
    }

    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        return app
    }

    /// A readable pause, so the recording isn't a blur of instant transitions.
    private func beat(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
