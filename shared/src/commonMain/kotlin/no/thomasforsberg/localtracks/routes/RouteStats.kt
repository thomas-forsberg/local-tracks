package no.thomasforsberg.localtracks.routes

import no.thomasforsberg.localtracks.recording.Sport
import kotlin.time.Instant

// Stats for one sport on one route. Times are moving times: stopping to talk doesn't make an attempt slower.
data class RouteStats(
    val sport: Sport,
    val count: Int,
    val totalDistanceMeters: Double,
    val totalMovingTimeSeconds: Double,
    val averageMovingTimeSeconds: Double,
    // Over all attempts: total distance by total moving time.
    val averageSpeedMetersPerSecond: Double?,
    // Fastest first, at most three.
    val best: List<RouteAttempt>,
    val latest: RouteAttempt,
    // Positive: the latest attempt was slower.
    val latestVersusAverageSeconds: Double,
    val latestVersusBestSeconds: Double,
    val lastDoneAt: Instant,
    // Null with a single attempt.
    val averageDaysBetween: Double?,
    // Per direction relative to the route's reference: false = the same way, true = the other way.
    val byDirection: Map<Boolean, DirectionStats>,
)

data class DirectionStats(val count: Int, val best: RouteAttempt)

// The sports done on the route, most attempts first.
fun RouteSummary.sports(): List<Sport> =
    attempts.groupingBy { it.activity.sport }.eachCount().entries.sortedByDescending { it.value }.map { it.key }

fun RouteSummary.stats(sport: Sport): RouteStats? {
    val ofSport = attempts.filter { it.activity.sport == sport }.sortedBy { it.activity.startedAt }
    if (ofSport.isEmpty()) return null
    fun RouteAttempt.seconds() = activity.totals.movingTimeSeconds
    val totalDistance = ofSport.sumOf { it.activity.totals.distanceMeters }
    val totalSeconds = ofSport.sumOf { it.seconds() }
    val average = totalSeconds / ofSport.size
    val best = ofSport.sortedBy { it.seconds() }
    val latest = ofSport.last()
    val first = ofSport.first().activity.startedAt
    val days = if (ofSport.size > 1) (latest.activity.startedAt - first).inWholeSeconds / 86_400.0 / (ofSport.size - 1) else null
    return RouteStats(
        sport = sport,
        count = ofSport.size,
        totalDistanceMeters = totalDistance,
        totalMovingTimeSeconds = totalSeconds,
        averageMovingTimeSeconds = average,
        averageSpeedMetersPerSecond = if (totalSeconds > 0) totalDistance / totalSeconds else null,
        best = best.take(3),
        latest = latest,
        latestVersusAverageSeconds = latest.seconds() - average,
        latestVersusBestSeconds = latest.seconds() - best.first().seconds(),
        lastDoneAt = latest.activity.startedAt,
        averageDaysBetween = days,
        byDirection = ofSport.groupBy { it.reversed }.mapValues { (_, attempts) -> DirectionStats(attempts.size, attempts.minBy { it.seconds() }) },
    )
}
