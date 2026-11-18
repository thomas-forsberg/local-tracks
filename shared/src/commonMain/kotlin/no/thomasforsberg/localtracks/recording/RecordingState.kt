package no.thomasforsberg.localtracks.recording

import no.thomasforsberg.localtracks.track.TrackPoint
import kotlin.native.HiddenFromObjC
import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.Instant

sealed interface RecordingState {
    data object Idle : RecordingState

    data class Recording(val progress: ActivityProgress, val resumedAt: Instant) : RecordingState

    data class Paused(val progress: ActivityProgress, val pausedAt: Instant) : RecordingState

    data class Finished(val progress: ActivityProgress, val finishedAt: Instant) : RecordingState

    // Time spent recording, excluding pauses.
    @HiddenFromObjC
    fun activeTime(now: Instant): Duration = when (this) {
        Idle -> Duration.ZERO
        is Recording -> progress.activeTimeBeforeResume + (now - resumedAt).coerceAtLeast(Duration.ZERO)
        is Paused -> progress.activeTimeBeforeResume
        is Finished -> progress.activeTimeBeforeResume
    }

    // Wall-clock time since start, including pauses.
    @HiddenFromObjC
    fun elapsed(now: Instant): Duration = when (this) {
        Idle -> Duration.ZERO
        is Recording -> now - progress.startedAt
        is Paused -> now - progress.startedAt
        is Finished -> finishedAt - progress.startedAt
    }

    // Kotlin's Duration reaches Swift as its raw internal encoding, so Swift gets plain seconds instead.
    fun activeTimeSeconds(now: Instant): Double = activeTime(now).toDouble(DurationUnit.SECONDS)

    fun elapsedSeconds(now: Instant): Double = elapsed(now).toDouble(DurationUnit.SECONDS)

    fun averageSpeedMetersPerSecond(now: Instant): Double? {
        val seconds = activeTime(now).toDouble(DurationUnit.SECONDS)
        val distance = progressOrNull()?.distanceMeters ?: return null
        return if (seconds > 0) distance / seconds else null
    }

    fun progressOrNull(): ActivityProgress? = when (this) {
        Idle -> null
        is Recording -> progress
        is Paused -> progress
        is Finished -> progress
    }
}

data class ActivityProgress(
    val sport: Sport,
    val startedAt: Instant,
    @property:HiddenFromObjC val activeTimeBeforeResume: Duration,
    val distanceMeters: Double,
    val pointCount: Int,
    val elevationGain: ElevationGain,
    // Increases on every resume, so distance is never counted across a pause.
    val segmentIndex: Int,
    // Last accepted point of the current segment.
    val lastPoint: TrackPoint?,
    val currentSpeedMetersPerSecond: Double?,
) {
    companion object {
        fun startingAt(sport: Sport, time: Instant) = ActivityProgress(
            sport = sport,
            startedAt = time,
            activeTimeBeforeResume = Duration.ZERO,
            distanceMeters = 0.0,
            pointCount = 0,
            elevationGain = ElevationGain.NONE,
            segmentIndex = 0,
            lastPoint = null,
            currentSpeedMetersPerSecond = null,
        )
    }
}

data class RecordedPoint(val segmentIndex: Int, val point: TrackPoint)
