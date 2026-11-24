package no.thomasforsberg.localtracks.track

import no.thomasforsberg.localtracks.recording.RecordedPoint
import no.thomasforsberg.localtracks.recording.Sport
import no.thomasforsberg.localtracks.geo.distanceMeters
import kotlin.math.max
import kotlin.time.DurationUnit

// Everything the detail screen shows beyond the stored totals, computed from the stored points.
data class ActivityAnalysis(
    // Downsampled along the distance, for charts.
    val profile: List<ProfileSample>,
    val splits: List<Split>,
    val maxSpeedMetersPerSecond: Double?,
)

data class ProfileSample(
    val distanceMeters: Double,
    // Absolute altitude: barometer for the shape, anchored to GPS altitude for the level. Null without either.
    val elevationMeters: Double?,
    // Lightly smoothed; null while standing still.
    val speedMetersPerSecond: Double?,
)

// One kilometre (the last one usually shorter), timed by moving time.
data class Split(
    val number: Int,
    val distanceMeters: Double,
    val movingTimeSeconds: Double,
    val elevationChangeMeters: Double?,
) {
    val averageSpeedMetersPerSecond: Double? get() = if (movingTimeSeconds > 0) distanceMeters / movingTimeSeconds else null
}

internal data class Sample(val distance: Double, val movingSeconds: Double, val elevation: Double?, val speed: Double?)

fun analyze(points: List<RecordedPoint>, sport: Sport, maxSamples: Int): ActivityAnalysis {
    val samples = samplesAlong(points, sport)
    return ActivityAnalysis(
        profile = samples.downsampled(maxSamples).map { ProfileSample(it.distance, it.elevation, it.speed) },
        splits = splits(samples, splitMeters = 1000.0),
        maxSpeedMetersPerSecond = samples.mapNotNull { it.speed }.maxOrNull(),
    )
}

internal fun samplesAlong(points: List<RecordedPoint>, sport: Sport): List<Sample> {
    val elevations = points.groupBy { it.segmentIndex }.values.flatMap(::absoluteElevations)
    var measurement = TrackMeasurement.EMPTY
    var segment: Int? = null
    val raw = points.mapIndexed { index, recorded ->
        if (segment != null && segment != recorded.segmentIndex) measurement = measurement.startingNewSegment()
        segment = recorded.segmentIndex
        val previousPoint = measurement.lastPoint
        measurement = measurement.adding(recorded.point, sport)
        val speed = recorded.point.speedMetersPerSecond ?: previousPoint?.let { speedBetween(it, recorded.point) }
        Sample(measurement.distanceMeters, measurement.movingTimeSeconds, elevations[index], speed.takeIf { measurement.isMoving })
    }
    return raw.withSmoothedSpeed(window = 5)
}

// Barometric altitude is relative to when the sensor started (each segment), so it is shifted to the
// GPS altitude by their typical difference: the barometer gives the shape, GPS the level. "Typical" is
// the interquartile mean: robust to GPS altitude outliers, and it averages out symmetric noise.
private fun absoluteElevations(segment: List<RecordedPoint>): List<Double?> {
    val offsets = segment.mapNotNull { recorded ->
        val gps = recorded.point.elevationMeters ?: return@mapNotNull null
        val barometric = recorded.point.barometer?.relativeAltitudeMeters ?: return@mapNotNull null
        gps - barometric
    }.sorted()
    val offset = offsets.subList(offsets.size / 4, offsets.size - offsets.size / 4).takeIf { it.isNotEmpty() }?.average()
    return segment.map { recorded ->
        val barometric = recorded.point.barometer?.relativeAltitudeMeters
        if (barometric != null && offset != null) barometric + offset else recorded.point.elevationMeters
    }
}

private fun List<Sample>.withSmoothedSpeed(window: Int): List<Sample> = mapIndexed { index, sample ->
    if (sample.speed == null) return@mapIndexed sample
    val neighbours = subList(max(0, index - window / 2), minOf(size, index + window / 2 + 1)).mapNotNull { it.speed }
    sample.copy(speed = neighbours.average())
}

private fun List<Sample>.downsampled(maxSamples: Int): List<Sample> {
    if (size <= maxSamples) return this
    val step = size.toDouble() / maxSamples
    return (0 until maxSamples).map { this[(it * step).toInt()] } + last()
}

private fun splits(samples: List<Sample>, splitMeters: Double): List<Split> {
    if (samples.isEmpty()) return emptyList()
    val total = samples.last().distance
    val boundaries = generateSequence(splitMeters) { it + splitMeters }.takeWhile { it < total }.toList() + total
    return boundaries.fold(emptyList<Split>() to samples.first()) { (splits, from), boundary ->
        val to = samples.interpolatedAt(boundary)
        val split = Split(
            number = splits.size + 1,
            distanceMeters = to.distance - from.distance,
            movingTimeSeconds = to.movingSeconds - from.movingSeconds,
            elevationChangeMeters = if (to.elevation != null && from.elevation != null) to.elevation - from.elevation else null,
        )
        (splits + split) to to
    }.first.filter { it.distanceMeters > 0 }
}

internal fun List<Sample>.interpolatedAt(distance: Double): Sample {
    val after = indexOfFirst { it.distance >= distance }.takeIf { it >= 0 } ?: return last()
    val b = this[after]
    val a = getOrNull(after - 1)?.takeIf { it.distance < b.distance } ?: return b
    val fraction = (distance - a.distance) / (b.distance - a.distance)
    fun lerp(x: Double, y: Double) = x + (y - x) * fraction
    return Sample(
        distance = distance,
        movingSeconds = lerp(a.movingSeconds, b.movingSeconds),
        elevation = if (a.elevation != null && b.elevation != null) lerp(a.elevation, b.elevation) else b.elevation,
        speed = b.speed,
    )
}

private fun speedBetween(from: TrackPoint, to: TrackPoint): Double? {
    val start = from.time ?: return null
    val end = to.time ?: return null
    val seconds = (end - start).toDouble(DurationUnit.SECONDS)
    return if (seconds > 0) distanceMeters(from, to) / seconds else null
}
