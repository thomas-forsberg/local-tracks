package no.thomasforsberg.localtracks.routes

import no.thomasforsberg.localtracks.recording.Sport
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Loops around a lake near Oslo: a circle of `radius` metres, walked from its southern point.
internal fun loop(
    radiusMeters: Double = 500.0,
    clockwise: Boolean = false,
    noiseMeters: Double = 0.0,
    seed: Int = 1,
    centerLatitude: Double = 59.97,
    centerLongitude: Double = 10.73,
    points: Int = 400,
): List<GeoPoint> {
    val random = Random(seed)
    val metersPerDegreeLongitude = 111_195.0 * cos(centerLatitude * PI / 180)
    return (0..points).map { i ->
        val turn = 2 * PI * i / points * (if (clockwise) -1 else 1)
        val angle = -PI / 2 + turn
        val noise = { (random.nextDouble() * 2 - 1) * noiseMeters }
        GeoPoint(
            centerLatitude + (radiusMeters * sin(angle) + noise()) / 111_195.0,
            centerLongitude + (radiusMeters * cos(angle) + noise()) / metersPerDegreeLongitude,
        )
    }
}

internal fun track(line: List<GeoPoint>, id: Long = 1, sport: Sport = Sport.HIKING) =
    RouteTrack(id, sport, line.lengthMeters(), line.resampled(RouteMatching.SPACING_METERS))

class RouteMatchingTest {
    @Test
    fun resamplingSpacesPointsEvenly() {
        val line = loop()
        val resampled = line.resampled(25.0)

        assertEquals(line.lengthMeters() / 25, resampled.size.toDouble(), 2.0)
        assertEquals(line.first(), resampled.first())
        assertEquals(line.last(), resampled.last())
    }

    @Test
    fun theSameLoopWithGpsNoiseMatches() {
        val match = RouteMatching.match(track(loop(noiseMeters = 8.0, seed = 1)), track(loop(noiseMeters = 8.0, seed = 2)))

        assertEquals(TrackMatch(reversed = false), match)
    }

    @Test
    fun theSameLoopTheOtherWayRoundMatchesReversed() {
        val match = RouteMatching.match(track(loop(clockwise = true)), track(loop(clockwise = false)))

        assertEquals(TrackMatch(reversed = true), match)
    }

    @Test
    fun aDifferentLoopDoesNotMatch() {
        val bigger = loop(radiusMeters = 560.0)

        assertNull(RouteMatching.match(track(loop()), track(bigger)), "same start, ~12 % longer, 60 m off all the way")
    }

    @Test
    fun aShortSideTripStillCountsAsTheSameRoute() {
        val base = loop()
        // A 60 m out-and-back to a viewpoint on the far side: under 5 % of the loop.
        val far = base[base.size / 2]
        val spur = (1..5).map { GeoPoint(far.latitude + it * 0.00011, far.longitude) }
        val withSpur = base.subList(0, base.size / 2) + spur + spur.reversed() + base.subList(base.size / 2, base.size)

        assertNotNull(RouteMatching.match(track(withSpur), track(base)))
    }

    @Test
    fun takingAnotherPathForAQuarterOfTheLoopIsADifferentRoute() {
        val base = loop()
        // The same length to within a few percent, but the last quarter runs 100 m further out.
        val other = loop().mapIndexed { i, point ->
            if (i < base.size * 3 / 4) point else {
                val bulge = 100.0 * kotlin.math.sin(PI * (i - base.size * 3 / 4) / (base.size / 4))
                GeoPoint(point.latitude, point.longitude - bulge / (111_195.0 * cos(59.97 * PI / 180)))
            }
        }

        assertNull(RouteMatching.match(track(other), track(base)))
    }

    @Test
    fun lengthsMayDifferByFivePercentButAtLeast100Meters() {
        assertTrue(RouteMatching.lengthsCompatible(1_000.0, 1_095.0), "short loop: 100 m")
        assertFalse(RouteMatching.lengthsCompatible(1_000.0, 1_120.0))
        assertTrue(RouteMatching.lengthsCompatible(30_000.0, 31_400.0), "long ride: 5 %")
        assertFalse(RouteMatching.lengthsCompatible(30_000.0, 32_000.0))
    }

    @Test
    fun theSameLoopWalkedTwiceInOneGoIsNotTheLoop() {
        val once = loop()
        val twice = once + once.drop(1)

        assertNull(RouteMatching.match(track(twice), track(once)))
    }

    @Test
    fun walksMuchShorterThanAnyRouteAreNeverRoutes() {
        val short = loop(radiusMeters = 60.0)

        assertNull(RouteMatching.match(track(short), track(short)))
    }

    @Test
    fun aTripMatchesItsReturnJourney() {
        val there = (0..100).map { GeoPoint(59.97 + it * 0.0001, 10.73) }

        val match = assertNotNull(RouteMatching.match(track(there), track(there.reversed())))
        assertTrue(match.reversed)
    }

    @Test
    fun loopsKnowWhichWayRoundTheyGo() {
        assertEquals(RouteShape.ANTICLOCKWISE_LOOP, RouteMatching.shape(loop(clockwise = false)))
        assertEquals(RouteShape.CLOCKWISE_LOOP, RouteMatching.shape(loop(clockwise = true)))
        assertEquals(RouteShape.NOT_A_LOOP, RouteMatching.shape((0..100).map { GeoPoint(59.97 + it * 0.0001, 10.73) }))
    }
}
