import XCTest

// Walks through the screens with demo data and attaches a screenshot of each.
// Run with scripts/screenshot-tour.sh, which exports the images to build/screenshots/.
// UI automation needs XCTest; the unit tests use Swift Testing.
final class ScreenshotTour: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTour() {
        let app = launch("-demoData")
        XCTAssert(app.buttons["Start"].waitForExistence(timeout: 30))
        snapshot("01-record")
        app.buttons["Settings"].tap()
        XCTAssert(app.switches["Record when I leave home"].waitForExistence(timeout: 5))
        snapshot("01b-settings")
        app.buttons["Done"].tap()

        // Demo mode feeds pretend GPS, barometer and pedometer data, so this records without real sensors.
        app.buttons["Hiking"].tap()
        app.buttons["Start"].tap()
        XCTAssert(app.buttons["Pause"].waitForExistence(timeout: 5))
        sleep(8)
        snapshot("02-recording")
        app.buttons["Show map"].tap()
        sleep(3) // let the map draw
        snapshot("02b-recording-map")
        // Panning stops following the latest point and offers a re-centre button.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3)))
        XCTAssert(app.buttons["Re-centre"].waitForExistence(timeout: 5))
        snapshot("02e-recording-map-panned")
        app.buttons["Re-centre"].tap()
        XCTAssert(app.buttons["Re-centre"].waitForNonExistence(timeout: 5))
        app.buttons["Show stats"].tap()

        // The Live Activity: compact in the Dynamic Island on the home screen, and as the card in the
        // Notification Center (which shows what the lock screen shows).
        XCUIDevice.shared.press(.home)
        sleep(2)
        snapshot("02c-dynamic-island")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.005))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.7)))
        sleep(2)
        snapshot("02d-lock-screen-card")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssert(app.buttons["Pause"].waitForExistence(timeout: 10))
        app.buttons["Pause"].tap()
        XCTAssert(app.buttons["Resume"].waitForExistence(timeout: 5))
        snapshot("03-paused")
        app.buttons["Stop"].press(forDuration: 1.5)
        XCTAssert(app.buttons["Start"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Activities"].tap()
        let firstRow = app.cells.firstMatch
        XCTAssert(firstRow.waitForExistence(timeout: 10))
        snapshot("04-activities")

        // The demo hike (the first row is the few seconds just recorded above, then running and cycling).
        app.cells.element(boundBy: 3).tap()
        XCTAssert(app.staticTexts["Moving time"].waitForExistence(timeout: 10))
        sleep(2) // let the map draw its first frame
        snapshot("05-activity-detail")
        app.swipeUp()
        sleep(1)
        snapshot("06-activity-charts")
        app.swipeUp()
        sleep(1)
        snapshot("06b-splits")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssert(firstRow.waitForExistence(timeout: 5))

        firstRow.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssert(app.alerts.firstMatch.waitForExistence(timeout: 5))
        sleep(1) // still there once the row has slid back
        XCTAssert(app.alerts.firstMatch.exists)
        snapshot("07-delete-confirmation")
        app.alerts.buttons["Cancel"].tap()

        app.tabBars.buttons["Stats"].tap()
        XCTAssert(app.staticTexts["Stats"].waitForExistence(timeout: 5))
        snapshot("09-stats")
        app.buttons["All time"].tap()
        sleep(1)
        snapshot("10-stats-all-time")

        // Demo mode draws its own map tiles instead of downloading them.
        app.tabBars.buttons["Maps"].tap()
        XCTAssert(app.staticTexts["Nordmarka"].waitForExistence(timeout: 15))
        app.staticTexts["Nordmarka"].tap() // zooms the map to it
        sleep(3) // let the map draw
        snapshot("11-maps")
        app.buttons["Add area"].tap()
        XCTAssert(app.buttons["Download"].waitForExistence(timeout: 5))
        sleep(2)
        snapshot("12-maps-add-area")
        app.buttons["Cancel"].tap()
    }

    // The same screens in dark mode, the Night trail palette.
    @MainActor
    func testDarkMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData", "-darkMode"]
        app.launch()
        XCTAssert(app.buttons["Start"].waitForExistence(timeout: 30))
        app.buttons["Hiking"].tap()
        app.buttons["Start"].tap()
        XCTAssert(app.buttons["Pause"].waitForExistence(timeout: 5))
        sleep(6)
        snapshot("20-dark-recording")
        app.buttons["Stop"].press(forDuration: 1.5)
        app.tabBars.buttons["Activities"].tap()
        XCTAssert(app.cells.firstMatch.waitForExistence(timeout: 10))
        snapshot("21-dark-activities")
        app.cells.element(boundBy: 3).tap()
        XCTAssert(app.staticTexts["Moving time"].waitForExistence(timeout: 10))
        sleep(2)
        snapshot("22-dark-activity-detail")
    }

    @MainActor
    func testMapsBeforeDownloading() {
        let app = launch("-demoDataEmpty")
        app.tabBars.buttons["Maps"].tap()
        XCTAssert(app.buttons["Download overview"].waitForExistence(timeout: 10))
        snapshot("13-maps-empty")
    }

    @MainActor
    func testEmptyActivities() {
        let app = launch("-demoDataEmpty")
        app.tabBars.buttons["Activities"].tap()
        XCTAssert(app.staticTexts["No activities yet"].waitForExistence(timeout: 10))
        snapshot("08-activities-empty")
    }

    @MainActor
    private func launch(_ argument: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [argument]
        app.launch()
        return app
    }

    @MainActor
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
