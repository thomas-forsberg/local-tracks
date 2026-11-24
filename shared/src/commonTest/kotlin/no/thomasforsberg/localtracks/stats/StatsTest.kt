package no.thomasforsberg.localtracks.stats

import no.thomasforsberg.localtracks.recording.Sport
import no.thomasforsberg.localtracks.storage.ActivitySummary
import no.thomasforsberg.localtracks.storage.ActivityTotals
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Instant

class StatsTest {
    private val now = Instant.parse("2026-11-19T12:00:00Z")
    private var nextId = 1L

    private fun activity(sport: Sport, daysAgo: Int, km: Double, minutes: Int, climb: Double = 0.0, finished: Boolean = true): ActivitySummary {
        val start = now - daysAgo.days
        return ActivitySummary(
            id = nextId++,
            sport = sport,
            startedAt = start,
            finishedAt = if (finished) start + minutes.minutes else null,
            totals = ActivityTotals(minutes.minutes, km * 1000, 100, climb, minutes.minutes),
        )
    }

    @Test
    fun totalsPerSportSinceAPeriodStartIncludingOnlyFinishedActivities() {
        val activities = listOf(
            activity(Sport.CYCLING, daysAgo = 1, km = 20.0, minutes = 60, climb = 100.0),
            activity(Sport.CYCLING, daysAgo = 3, km = 30.0, minutes = 90, climb = 200.0),
            activity(Sport.CYCLING, daysAgo = 40, km = 50.0, minutes = 120),
            activity(Sport.HIKING, daysAgo = 2, km = 5.0, minutes = 90, climb = 300.0),
            activity(Sport.HIKING, daysAgo = 0, km = 3.0, minutes = 30, finished = false),
        )

        val week = totalsSince(activities, since = now - 7.days)

        assertEquals(listOf(Sport.CYCLING, Sport.HIKING), week.map { it.sport })
        assertEquals(SportTotals(Sport.CYCLING, 2, 50_000.0, 150 * 60.0, 300.0), week[0])
        assertEquals(SportTotals(Sport.HIKING, 1, 5_000.0, 90 * 60.0, 300.0), week[1])
        assertEquals(100_000.0, totalsSince(activities, since = null).first { it.sport == Sport.CYCLING }.distanceMeters)
    }

    @Test
    fun totalsAddUpActiveEnergyCountingMissingAsNothing() {
        val activities = listOf(
            activity(Sport.HIKING, daysAgo = 1, km = 5.0, minutes = 60).copy(activeKcalPerKg = 2.5),
            activity(Sport.HIKING, daysAgo = 2, km = 3.0, minutes = 40).copy(activeKcalPerKg = 1.5),
            activity(Sport.HIKING, daysAgo = 3, km = 2.0, minutes = 30),
        )

        assertEquals(4.0, totalsSince(activities, since = null).single().activeKcalPerKg)
    }

    @Test
    fun recordsPerSportAndKind() {
        val long = activity(Sport.CYCLING, daysAgo = 10, km = 80.0, minutes = 240, climb = 900.0)
        val fast = activity(Sport.CYCLING, daysAgo = 5, km = 30.0, minutes = 60, climb = 100.0)
        val hike = activity(Sport.HIKING, daysAgo = 2, km = 12.0, minutes = 300, climb = 1100.0)

        val records = personalRecords(listOf(long, fast, hike))

        val cycling = records.filter { it.activity.sport == Sport.CYCLING }.associate { it.kind to it.activity.id }
        assertEquals(long.id, cycling[RecordKind.LONGEST_DISTANCE])
        assertEquals(long.id, cycling[RecordKind.LONGEST_MOVING_TIME])
        assertEquals(long.id, cycling[RecordKind.BIGGEST_CLIMB])
        assertEquals(fast.id, cycling[RecordKind.FASTEST_AVERAGE_SPEED])
        assertEquals(4, records.count { it.activity.sport == Sport.HIKING })
    }

    @Test
    fun shortActivitiesCantSetASpeedRecordAndZeroValuesArentRecords() {
        val sprint = activity(Sport.RUNNING, daysAgo = 1, km = 0.5, minutes = 1)
        val flat = activity(Sport.RUNNING, daysAgo = 2, km = 5.0, minutes = 30, climb = 0.0)

        val kinds = personalRecords(listOf(sprint, flat)).map { it.kind to it.activity.id }

        assertTrue(RecordKind.FASTEST_AVERAGE_SPEED to flat.id in kinds)
        assertTrue(kinds.none { it.first == RecordKind.BIGGEST_CLIMB })
    }

    @Test
    fun tiesGoToTheEarlierActivity() {
        val first = activity(Sport.HIKING, daysAgo = 9, km = 10.0, minutes = 120)
        val second = activity(Sport.HIKING, daysAgo = 1, km = 10.0, minutes = 150)

        assertEquals(first.id, personalRecords(listOf(second, first)).first { it.kind == RecordKind.LONGEST_DISTANCE }.activity.id)
    }
}
