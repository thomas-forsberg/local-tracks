package no.thomasforsberg.localtracks.auto

import no.thomasforsberg.localtracks.recording.BarometerReading
import no.thomasforsberg.localtracks.recording.RecordedPoint
import no.thomasforsberg.localtracks.recording.Sport
import no.thomasforsberg.localtracks.track.TrackPoint
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

class TripCheckTest {
    private val start = Instant.parse("2026-11-26T08:40:00Z")

    // One point per second, heading north at the given speed (m/s), climbing at the given rate.
    private fun trip(minutes: Int, speed: Double, climbPerSecond: Double = 0.0) = (0..minutes * 60).map { second ->
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

    private fun motion(vararg kinds: Pair<MotionKind, Int>) = kinds.map { (kind, minute) -> MotionSample(kind, start + minute.minutes) }

    private fun judge(points: List<RecordedPoint>, sport: Sport, motion: List<MotionSample> = emptyList(), carAudio: Boolean = false) =
        TripCheck.judge(points, sport, motion, until = points.last().point.time!!, carAudio = carAudio).verdict

    @Test
    fun aHikeIsKept() {
        assertEquals(TripVerdict.KEEP, judge(trip(20, speed = 1.4, climbPerSecond = 0.1), Sport.HIKING, motion(MotionKind.WALKING to 0)))
    }

    @Test
    fun drivingAt60WithTheSensorStillSayingWalkingIsACarRide() {
        // The classifier lags: it still says walking from the walk to the car.
        assertEquals(TripVerdict.CAR, judge(trip(10, speed = 16.7), Sport.HIKING, motion(MotionKind.WALKING to -5)))
    }

    @Test
    fun theSensorSayingDrivingMostOfTheTimeIsEnough() {
        // 30 km/h in town: a bike could do that.
        val motion = motion(MotionKind.WALKING to 0, MotionKind.AUTOMOTIVE to 3)
        assertEquals(TripVerdict.CAR, judge(trip(20, speed = 8.3), Sport.CYCLING, motion))
    }

    @Test
    fun carPlayIsEnough() {
        assertEquals(TripVerdict.CAR, judge(trip(5, speed = 8.3), Sport.CYCLING, carAudio = true))
    }

    @Test
    fun aFastBikeRideIsKept() {
        // 38 km/h on the flat, about 330 W: hard, but a cyclist's effort.
        assertEquals(TripVerdict.KEEP, judge(trip(30, speed = 10.5), Sport.CYCLING, motion(MotionKind.CYCLING to 0)))
    }

    @Test
    fun aFastDescentOnABikeIsAtMostSuspected() {
        // 70 km/h down 8 %: no power needed, but faster than most bikes ever go.
        val verdict = judge(trip(5, speed = 19.4, climbPerSecond = -19.4 * 0.08), Sport.CYCLING, motion(MotionKind.CYCLING to 0))
        assertEquals(TripVerdict.KEEP, verdict)
        val faster = judge(trip(5, speed = 26.0, climbPerSecond = -26.0 * 0.1), Sport.CYCLING, motion(MotionKind.CYCLING to 0))
        assertEquals(TripVerdict.SUSPECTED_CAR, faster)
    }

    @Test
    fun someDrivingIsSuspected() {
        // Cycling to the station, then a bus: 25 % of the time driving.
        val motion = motion(MotionKind.CYCLING to 0, MotionKind.AUTOMOTIVE to 15)
        assertEquals(TripVerdict.SUSPECTED_CAR, judge(trip(20, speed = 6.0), Sport.CYCLING, motion))
    }

    @Test
    fun bikeSpeedsOnFootMakeItABikeRide() {
        assertEquals(TripVerdict.CYCLING, judge(trip(20, speed = 7.0), Sport.HIKING, motion(MotionKind.WALKING to 0)))
        assertEquals(TripVerdict.CYCLING, judge(trip(20, speed = 4.0), Sport.HIKING, motion(MotionKind.CYCLING to 1)))
    }

    @Test
    fun fastRunningIsNotABikeRide() {
        assertEquals(TripVerdict.KEEP, judge(trip(20, speed = 5.0), Sport.RUNNING, motion(MotionKind.RUNNING to 0)))
    }

    @Test
    fun theReasonSaysWhatItSaw() {
        val points = trip(10, speed = 16.7)
        val reason = TripCheck.judge(points, Sport.HIKING, emptyList(), points.last().point.time!!, carAudio = false).reason
        assertTrue("top 60 km/h" in reason, reason)
    }

    @Test
    fun sharesCountOnlyMovingTimeWithinTheTrip() {
        val shares = TripCheck.motionShares(
            motion(MotionKind.AUTOMOTIVE to -10, MotionKind.STATIONARY to 0, MotionKind.WALKING to 2, MotionKind.AUTOMOTIVE to 4),
            start = start,
            until = start + 10.minutes,
        )
        assertEquals(6.0 / 8, shares.driving, absoluteTolerance = 1e-9)
        assertEquals(0.0, shares.cycling)
    }

    @Test
    fun cyclistPowerOnTheFlatAndUphill() {
        // 40 km/h on the flat: about 360 W; 15 km/h up 8 %: about 320 W.
        assertEquals(375.0, TripCheck.cyclingWatts(11.1, 0.0), absoluteTolerance = 15.0)
        assertEquals(320.0, TripCheck.cyclingWatts(4.17, 0.08), absoluteTolerance = 15.0)
    }
}
