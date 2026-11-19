package no.thomasforsberg.localtracks.track

import no.thomasforsberg.localtracks.recording.Sport
import kotlin.time.Duration

data class TrackSummary(
    val pointCount: Int,
    val distanceMeters: Double,
    val elapsed: Duration,
)

// Distance as recording measures it (smoothed, standing still excluded), for one segment of points.
fun List<TrackPoint>.summary(sport: Sport = Sport.HIKING): TrackSummary {
    val times = mapNotNull { it.time }
    return TrackSummary(
        pointCount = size,
        distanceMeters = fold(TrackMeasurement.EMPTY) { measurement, point -> measurement.adding(point, sport) }.distanceMeters,
        elapsed = if (times.size < 2) Duration.ZERO else times.last() - times.first(),
    )
}
