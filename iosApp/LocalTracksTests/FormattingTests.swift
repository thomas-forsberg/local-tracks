import CoreLocation
import Foundation
import Shared
import Testing
@testable import LocalTracks

struct FormattingTests {
    private let english = Locale(identifier: "en_US")

    @Test(arguments: [(5.0, "0:05"), (2640.0, "44:00"), (5530.9, "1:32:10")])
    func clock(seconds: Double, expected: String) {
        #expect(Formatters.clock(seconds: seconds) == expected)
    }

    @Test func shortDurationRoundsToMinutes() {
        #expect(Formatters.shortDuration(seconds: 2640, locale: english) == "44 min")
        #expect(Formatters.shortDuration(seconds: 5520, locale: english) == "1 hr, 32 min")
        #expect(Formatters.shortDuration(seconds: 9.4, locale: english) == "9 sec")
    }

    @Test func paceIsMinutesPerKilometre() {
        #expect(Formatters.pace(metersPerSecond: 1000.0 / 631) == "10:31 /km")
        #expect(Formatters.pace(metersPerSecond: 1000.0 / 300) == "5:00 /km")
    }

    @Test func paceIsBlankWhenStandingStillOrUnknown() {
        #expect(Formatters.pace(metersPerSecond: 0.1) == "–")
        #expect(Formatters.pace(metersPerSecond: nil) == "–")
    }

    @Test func cyclingShowsSpeedWhileRunningAndHikingShowPace() {
        #expect(Formatters.speedOrPace(metersPerSecond: 5, for: .cycling) == Formatters.speed(metersPerSecond: 5))
        #expect(Formatters.speedOrPace(metersPerSecond: 5, for: .running) == "3:20 /km")
        #expect(Sport.hiking.averageSpeedTitle == "Avg pace")
        #expect(Sport.cycling.averageSpeedTitle == "Avg speed")
    }

    @Test func stepsAreGroupedForTheLocale() {
        #expect(Formatters.steps(4213, locale: Locale(identifier: "en_US")) == "4,213")
    }

    @Test func markersOverlapWhenCloserThanOneMarkerOnScreen() {
        #expect(RouteMapView.Coordinator.markersOverlap(CGPoint(x: 100, y: 100), CGPoint(x: 110, y: 105)))
        #expect(!RouteMapView.Coordinator.markersOverlap(CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 130)))
    }

    @Test func chartDomainHasAMinimumSpanSoSteadySpeedsLookSteady() {
        #expect(SpeedChart.domain(for: [20.0, 20.4], minimumSpan: 10, floor: 0) == 15.2...25.2)
        #expect(SpeedChart.domain(for: [2.0, 3.0], minimumSpan: 10, floor: 0) == 0...7.5)
        #expect(SpeedChart.domain(for: [5.0, 30.0], minimumSpan: 10, floor: 0) == 5...30)
    }

    @Test func paceAxisLabelsAreMinutesAndSeconds() {
        #expect(SpeedChart.minutesAndSeconds(5.45) == "5:27")
    }
}
