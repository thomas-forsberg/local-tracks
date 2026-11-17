package no.thomasforsberg.localtracks.track

import no.thomasforsberg.localtracks.geo.distanceMeters
import kotlin.time.Duration

data class TrackSummary(
    val pointCount: Int,
    val distanceMeters: Double,
    val elapsed: Duration,
)

fun List<TrackPoint>.summary(): TrackSummary {
    val times = mapNotNull { it.time }
    return TrackSummary(
        pointCount = size,
        distanceMeters = zipWithNext(::distanceMeters).sum(),
        elapsed = if (times.size < 2) Duration.ZERO else times.last() - times.first(),
    )
}
