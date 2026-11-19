package no.thomasforsberg.localtracks.track

import no.thomasforsberg.localtracks.recording.RecordedPoint
import no.thomasforsberg.localtracks.recording.Sport
import kotlin.native.HiddenFromObjC
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.DurationUnit
import no.thomasforsberg.localtracks.geo.distanceMeters as distanceBetween

// Distance and moving time from GPS points, fed one point at a time, so live recording and
// analysis of stored points always give the same numbers.
//
// Distance uses two rules that matched Strava within ~0.5 % on real walks:
//  1. A step into a point where the device isn't moving doesn't count (GPS drift while standing still).
//  2. Each point between a segment's first and last is replaced by the accuracy-weighted average of
//     itself and its two neighbours, which flattens the zig-zag of GPS noise without cutting corners much.
// Moving time counts the time into each point where the speed is at least the sport's moving threshold.
data class TrackMeasurement(
    val distanceBeforeSegmentMeters: Double,
    val segment: SmoothedDistance,
    @property:HiddenFromObjC val movingTime: Duration,
    // Last point of the current segment, and whether it was moving.
    val lastPoint: TrackPoint?,
    val isMoving: Boolean,
) {
    val distanceMeters: Double get() = distanceBeforeSegmentMeters + segment.totalMeters

    // Kotlin's Duration reaches Swift as its raw internal encoding, so Swift gets plain seconds instead.
    val movingTimeSeconds: Double get() = movingTime.toDouble(DurationUnit.SECONDS)

    fun adding(point: TrackPoint, sport: Sport): TrackMeasurement {
        val seconds = lastPoint?.let { secondsBetween(it, point) }
        val computedSpeed = lastPoint?.let { previous -> seconds?.takeIf { it > 0 }?.let { distanceBetween(previous, point) / it } }
        val speed = point.speedMetersPerSecond ?: computedSpeed
        // Motion sensors (accelerometer, independent of GPS) can veto movement; otherwise GPS speed decides.
        val moving = point.stationaryByMotion != true && (speed?.let { it >= sport.movingThresholdMetersPerSecond } ?: true)
        return copy(
            segment = segment.adding(point, moving),
            movingTime = movingTime + if (moving && seconds != null) seconds.seconds else Duration.ZERO,
            lastPoint = point,
            isMoving = moving,
        )
    }

    // Every resume starts a new segment: nothing is measured across a pause.
    fun startingNewSegment(): TrackMeasurement =
        TrackMeasurement(distanceMeters, SmoothedDistance.EMPTY, movingTime, lastPoint = null, isMoving = false)

    companion object {
        val EMPTY = TrackMeasurement(0.0, SmoothedDistance.EMPTY, Duration.ZERO, lastPoint = null, isMoving = false)

        fun continuing(distanceMeters: Double, movingTime: Duration) =
            TrackMeasurement(distanceMeters, SmoothedDistance.EMPTY, movingTime, lastPoint = null, isMoving = false)
    }
}

// The distance part of TrackMeasurement for one segment. Smoothing a point needs the next point, so the
// distance up to the latest point is the smoothed part plus a provisional step to the latest raw point;
// that step is replaced by the smoothed one when the next point arrives.
data class SmoothedDistance(
    private val committedMeters: Double,
    private val lastSmoothed: TrackPoint?,
    private val previous: TrackPoint?,
    private val latest: TrackPoint?,
    private val latestMoving: Boolean,
) {
    val totalMeters: Double
        get() {
            val from = lastSmoothed ?: return committedMeters
            val to = latest ?: return committedMeters
            return committedMeters + if (previous != null && latestMoving) distanceBetween(from, to) else 0.0
        }

    fun adding(point: TrackPoint, moving: Boolean): SmoothedDistance {
        val latest = latest ?: return copy(lastSmoothed = point, latest = point, latestMoving = moving)
        val previous = previous ?: return copy(previous = latest, latest = point, latestMoving = moving)
        val smoothed = weightedAverage(previous, latest, point)
        val step = if (latestMoving) distanceBetween(lastSmoothed!!, smoothed) else 0.0
        return SmoothedDistance(committedMeters + step, smoothed, latest, point, moving)
    }

    companion object {
        val EMPTY = SmoothedDistance(0.0, null, null, null, false)
    }
}

private const val UNKNOWN_ACCURACY_METERS = 10.0

// Position of the middle point, averaged with its neighbours, each weighted by 1/accuracy².
private fun weightedAverage(a: TrackPoint, middle: TrackPoint, c: TrackPoint): TrackPoint {
    val points = listOf(a, middle, c)
    val weights = points.map { 1 / (it.horizontalAccuracyMeters ?: UNKNOWN_ACCURACY_METERS).coerceAtLeast(1.0).let { accuracy -> accuracy * accuracy } }
    val total = weights.sum()
    return middle.copy(
        latitude = points.zip(weights).sumOf { (point, weight) -> point.latitude * weight } / total,
        longitude = points.zip(weights).sumOf { (point, weight) -> point.longitude * weight } / total,
    )
}

private fun secondsBetween(from: TrackPoint, to: TrackPoint): Double? {
    val start = from.time ?: return null
    val end = to.time ?: return null
    return (end - start).toDouble(DurationUnit.SECONDS)
}

// Measures stored points exactly as recording did, segment by segment.
fun List<RecordedPoint>.measure(sport: Sport): TrackMeasurement =
    fold(TrackMeasurement.EMPTY to null as Int?) { (measurement, segment), recorded ->
        val current = if (segment != null && segment != recorded.segmentIndex) measurement.startingNewSegment() else measurement
        current.adding(recorded.point, sport) to recorded.segmentIndex
    }.first
