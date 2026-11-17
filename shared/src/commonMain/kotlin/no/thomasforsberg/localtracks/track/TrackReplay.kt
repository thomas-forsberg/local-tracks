package no.thomasforsberg.localtracks.track

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlin.time.Duration

// Emits points with their recorded time gaps, sped up by speedFactor; drives the recorder from GPX files.
fun List<TrackPoint>.replay(speedFactor: Double = 1.0): Flow<TrackPoint> {
    require(speedFactor > 0) { "speedFactor must be positive, was $speedFactor" }
    return flow {
        firstOrNull()?.let { emit(it) }
        zipWithNext().forEach { (previous, next) ->
            delay(gapBetween(previous, next) / speedFactor)
            emit(next)
        }
    }
}

private fun gapBetween(previous: TrackPoint, next: TrackPoint): Duration {
    val from = previous.time ?: return Duration.ZERO
    val to = next.time ?: return Duration.ZERO
    return (to - from).coerceAtLeast(Duration.ZERO)
}
