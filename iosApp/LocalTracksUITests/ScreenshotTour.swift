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
        app.buttons["Show stats"].tap()
        app.buttons["Pause"].tap()
        XCTAssert(app.buttons["Resume"].waitForExistence(timeout: 5))
        snapshot("03-paused")
        app.buttons["Stop"].tap()
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
        // Shown as a popover with only "Delete"; tapping outside cancels.
        XCTAssert(app.sheets.firstMatch.waitForExistence(timeout: 5))
        snapshot("07-delete-confirmation")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap() // dismiss the dialog

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
