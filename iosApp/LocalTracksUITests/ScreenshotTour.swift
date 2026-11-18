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

        app.tabBars.buttons["Activities"].tap()
        let firstRow = app.cells.firstMatch
        XCTAssert(firstRow.waitForExistence(timeout: 10))
        snapshot("02-activities")

        firstRow.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        // Shown as a popover with only "Delete"; tapping outside cancels.
        XCTAssert(app.sheets.firstMatch.waitForExistence(timeout: 5))
        snapshot("03-delete-confirmation")
    }

    @MainActor
    func testEmptyActivities() {
        let app = launch("-demoDataEmpty")
        app.tabBars.buttons["Activities"].tap()
        XCTAssert(app.staticTexts["No activities yet"].waitForExistence(timeout: 10))
        snapshot("04-activities-empty")
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
