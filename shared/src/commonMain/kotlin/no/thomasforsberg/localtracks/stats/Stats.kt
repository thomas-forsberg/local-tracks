package no.thomasforsberg.localtracks.stats

import no.thomasforsberg.localtracks.recording.Sport
import no.thomasforsberg.localtracks.storage.ActivitySummary
import kotlin.time.Instant

data class SportTotals(
    val sport: Sport,
    val activityCount: Int,
    val distanceMeters: Double,
    val movingTimeSeconds: Double,
    val elevationGainMeters: Double,
)

enum class RecordKind { LONGEST_DISTANCE, LONGEST_MOVING_TIME, BIGGEST_CLIMB, FASTEST_AVERAGE_SPEED }

data class PersonalRecord(val kind: RecordKind, val activity: ActivitySummary, val value: Double)

// Shorter activities can't set a speed record: a few seconds at a GPS-spike pace isn't an achievement.
const val MINIMUM_DISTANCE_FOR_SPEED_RECORD_METERS = 1000.0

// Totals per sport for finished activities started at or after `since` (null: all time).
// The caller decides where a period starts, since "this week" depends on the user's calendar.
fun totalsSince(activities: List<ActivitySummary>, since: Instant?): List<SportTotals> =
    activities
        .filter { it.finishedAt != null && (since == null || it.startedAt >= since) }
        .groupBy { it.sport }
        .map { (sport, ofSport) ->
            SportTotals(
                sport = sport,
                activityCount = ofSport.size,
                distanceMeters = ofSport.sumOf { it.totals.distanceMeters },
                movingTimeSeconds = ofSport.sumOf { it.totals.movingTimeSeconds },
                elevationGainMeters = ofSport.sumOf { it.totals.elevationGainMeters },
            )
        }
        .sortedByDescending { it.distanceMeters }

// The best finished activity per sport and kind; ties go to the earlier activity.
fun personalRecords(activities: List<ActivitySummary>): List<PersonalRecord> =
    activities
        .filter { it.finishedAt != null }
        .groupBy { it.sport }
        .entries
        .sortedBy { it.key.ordinal }
        .flatMap { (_, ofSport) ->
            RecordKind.entries.mapNotNull { kind ->
                ofSport
                    .sortedBy { it.startedAt }
                    .mapNotNull { activity -> recordValue(kind, activity)?.let { PersonalRecord(kind, activity, it) } }
                    .maxByOrNull { it.value }
            }
        }

private fun recordValue(kind: RecordKind, activity: ActivitySummary): Double? {
    val totals = activity.totals
    return when (kind) {
        RecordKind.LONGEST_DISTANCE -> totals.distanceMeters
        RecordKind.LONGEST_MOVING_TIME -> totals.movingTimeSeconds
        RecordKind.BIGGEST_CLIMB -> totals.elevationGainMeters
        RecordKind.FASTEST_AVERAGE_SPEED ->
            if (totals.distanceMeters >= MINIMUM_DISTANCE_FOR_SPEED_RECORD_METERS && totals.movingTimeSeconds > 0) {
                totals.distanceMeters / totals.movingTimeSeconds
            } else {
                null
            }
    }?.takeIf { it > 0 }
}
