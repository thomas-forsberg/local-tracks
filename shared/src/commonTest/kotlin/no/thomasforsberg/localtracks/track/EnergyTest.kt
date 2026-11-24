package no.thomasforsberg.localtracks.track

import no.thomasforsberg.localtracks.recording.BarometerReading
import no.thomasforsberg.localtracks.recording.LeadIn
import no.thomasforsberg.localtracks.recording.RecordedPoint
import no.thomasforsberg.localtracks.recording.Sport
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

class EnergyTest {
    private val start = Instant.parse("2026-09-12T07:00:00Z")

    // One point per second, heading north at the given speed, climbing at the given rate.
    private fun track(seconds: Int, speed: Double, climbPerSecond: Double = 0.0) = (0..seconds).map { second ->
        RecordedPoint(
            segmentIndex = 0,
            point = TrackPoint(
                latitude = 59.9 + second * speed / 111_195.08,
                longitude = 10.7,
                elevationMeters = 100.0 + second * climbPerSecond,
                time = start + second.seconds,
                horizontalAccuracyMeters = 5.0,
                speedMetersPerSecond = speed,
                barometer = BarometerReading(start + second.seconds, second * climbPerSecond, 100.0),
            ),
        )
    }

    @Test
    fun walkingAt5KilometresAnHourOnTheFlat() {
        assertEquals(2.5, kcalPerKg(Sport.HIKING, meters = 5000.0, seconds = 3600.0, climbMeters = 0.0), absoluteTolerance = 1e-9)
    }

    @Test
    fun runningCostsAboutOneKilocaloriePerKgPerKilometre() {
        assertEquals(10.0, kcalPerKg(Sport.RUNNING, meters = 10_000.0, seconds = 3600.0, climbMeters = 0.0), absoluteTolerance = 1e-9)
    }

    @Test
    fun climbingAddsToTheCostAndDescendingCountsAsFlat() {
        // 1 m/s up a 10 % slope for 100 s: (6 + 1.8 × 60 × 0.1) ml/kg/min.
        assertEquals(0.14, kcalPerKg(Sport.HIKING, meters = 100.0, seconds = 100.0, climbMeters = 10.0), absoluteTolerance = 1e-9)
        assertEquals(
            kcalPerKg(Sport.HIKING, 100.0, 100.0, climbMeters = 0.0),
            kcalPerKg(Sport.HIKING, 100.0, 100.0, climbMeters = -10.0),
        )
    }

    @Test
    fun theSpeedPicksWalkingOrRunningWhereItIsClear() {
        assertEquals(kcalPerKg(Sport.HIKING, 150.0, 100.0, 0.0), kcalPerKg(Sport.RUNNING, 150.0, 100.0, 0.0), "walking break on a run")
        assertEquals(kcalPerKg(Sport.RUNNING, 250.0, 100.0, 0.0), kcalPerKg(Sport.HIKING, 250.0, 100.0, 0.0), "jogging on a hike")
        assertEquals(2 * kcalPerKg(Sport.HIKING, 190.0, 100.0, 0.0), kcalPerKg(Sport.RUNNING, 190.0, 100.0, 0.0), "in between, the sport decides")
    }

    @Test
    fun cyclingUsesMetsBySpeed() {
        // 20 km/h is 8 METs, 7 of them on top of resting.
        assertEquals(7.0, kcalPerKg(Sport.CYCLING, meters = 20_000.0, seconds = 3600.0, climbMeters = 0.0), absoluteTolerance = 1e-9)
    }

    @Test
    fun aRecordedWalkPlusTheStretchBeforeGps() {
        val walk = track(seconds = 3600, speed = 5000.0 / 3600)
        val leadIn = LeadIn(5.minutes, distanceMeters = 400.0, steps = null)

        assertEquals(2.5, activeKcalPerKg(walk, Sport.HIKING, leadIn = null), absoluteTolerance = 0.05)
        assertEquals(2.7, activeKcalPerKg(walk, Sport.HIKING, leadIn), absoluteTolerance = 0.05)
    }

    @Test
    fun aRecordedClimbCostsMore() {
        val flat = activeKcalPerKg(track(seconds = 600, speed = 1.0), Sport.HIKING, leadIn = null)
        val uphill = activeKcalPerKg(track(seconds = 600, speed = 1.0, climbPerSecond = 0.1), Sport.HIKING, leadIn = null)

        // 10 % up: 6 + 10.8 ml/kg/min instead of 6.
        assertEquals(16.8 / 6, uphill / flat, absoluteTolerance = 0.05)
    }

    @Test
    fun nothingRecordedCostsNothing() {
        assertEquals(0.0, activeKcalPerKg(emptyList(), Sport.CYCLING, leadIn = null))
    }

    @Test
    fun shownForTheUsersWeight() {
        assertEquals(200, activeKcal(kcalPerKg = 2.5, weightKilograms = 80.0))
    }
}
