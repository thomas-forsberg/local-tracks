package no.thomasforsberg.localtracks.routes

import kotlinx.coroutines.test.runTest
import no.thomasforsberg.localtracks.recording.RecordedPoint
import no.thomasforsberg.localtracks.recording.Sport
import no.thomasforsberg.localtracks.recording.TestClock
import no.thomasforsberg.localtracks.storage.ActivityRepository
import no.thomasforsberg.localtracks.storage.ActivityTotals
import no.thomasforsberg.localtracks.storage.createTestDatabase
import no.thomasforsberg.localtracks.track.TrackPoint
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Instant

class RouteLibraryTest {
    private val database = createTestDatabase()
    private val activities = ActivityRepository(database)
    private val start = Instant.parse("2026-11-01T08:00:00Z")
    private val library = RouteLibrary(database, activities, TestClock(start))

    private fun record(line: List<GeoPoint>, day: Int, minutes: Int, sport: Sport = Sport.HIKING): Long {
        val startedAt = start + day.days
        val id = activities.startActivity(sport, startedAt)
        val points = line.map { RecordedPoint(0, TrackPoint(it.latitude, it.longitude, elevationMeters = null, time = startedAt)) }
        val totals = ActivityTotals(minutes.minutes, line.lengthMeters(), points.size, movingTime = minutes.minutes)
        activities.appendPoints(id, 0, points, totals)
        activities.finishActivity(id, startedAt + minutes.minutes, totals)
        return id
    }

    @Test
    fun twoWalksOfTheSameLoopBecomeARouteAndLaterOnesJoinIt() = runTest {
        val first = record(loop(noiseMeters = 6.0, seed = 1), day = 0, minutes = 40)
        record((0..100).map { GeoPoint(59.90 + it * 0.0001, 10.60) }, day = 1, minutes = 10) // elsewhere
        val second = record(loop(noiseMeters = 6.0, seed = 2), day = 2, minutes = 38)

        assertEquals(3, library.matchNewActivities())
        val route = library.routes().single()
        assertEquals(listOf(first, second), route.attempts.map { it.activity.id })
        assertEquals(RouteShape.ANTICLOCKWISE_LOOP, route.shape)
        assertNull(route.name)

        val third = record(loop(clockwise = true, noiseMeters = 6.0, seed = 3), day = 5, minutes = 36)
        assertEquals(1, library.matchNewActivities(), "only the new activity is checked")
        val updated = assertNotNull(library.routeFor(third))
        assertEquals(3, updated.attempts.size)
        assertTrue(updated.attempts.last().reversed)
    }

    @Test
    fun deletingAttemptsDissolvesARouteLeftWithOne() = runTest {
        val first = record(loop(seed = 1), day = 0, minutes = 40)
        record(loop(seed = 2), day = 1, minutes = 40)
        library.matchNewActivities()

        activities.delete(first)
        library.matchNewActivities()

        assertEquals(emptyList(), library.routes())
    }

    @Test
    fun routesCanBeRenamed() = runTest {
        record(loop(seed = 1), day = 0, minutes = 40)
        record(loop(seed = 2), day = 1, minutes = 40)
        library.matchNewActivities()
        val id = library.routes().single().id

        library.rename(id, "  Sognsvann rundt ")
        assertEquals("Sognsvann rundt", library.route(id)?.name)
        library.rename(id, "   ")
        assertNull(library.route(id)?.name, "blank: back to the automatic description")
    }

    @Test
    fun statsPerSportOnTheRoute() = runTest {
        record(loop(seed = 1), day = 0, minutes = 40)
        record(loop(seed = 2), day = 2, minutes = 36)
        record(loop(clockwise = true, seed = 3), day = 4, minutes = 38)
        record(loop(seed = 4), day = 6, minutes = 20, sport = Sport.RUNNING)
        library.matchNewActivities()
        val route = library.routes().single()

        assertEquals(listOf(Sport.HIKING, Sport.RUNNING), route.sports())
        val hiking = assertNotNull(route.stats(Sport.HIKING))
        assertEquals(3, hiking.count)
        assertEquals(38 * 60.0, hiking.averageMovingTimeSeconds)
        assertEquals(listOf(36, 38, 40), hiking.best.map { (it.activity.totals.movingTimeSeconds / 60).toInt() })
        assertEquals(0.0, hiking.latestVersusAverageSeconds)
        assertEquals(2 * 60.0, hiking.latestVersusBestSeconds)
        assertEquals(2.0, hiking.averageDaysBetween)
        assertEquals(2, hiking.byDirection[false]?.count)
        assertEquals(1, hiking.byDirection[true]?.count)
        assertEquals(1, route.stats(Sport.RUNNING)?.count)
    }
}
