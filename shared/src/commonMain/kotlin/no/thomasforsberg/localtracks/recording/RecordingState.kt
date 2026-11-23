package no.thomasforsberg.localtracks.recording

import no.thomasforsberg.localtracks.track.TrackMeasurement
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

    // Over moving time, as Strava does: standing at a red light doesn't lower it.
    fun averageSpeedMetersPerSecond(now: Instant): Double? {
        val progress = progressOrNull() ?: return null
        val seconds = progress.movingTimeSeconds
        return if (seconds > 0) progress.distanceMeters / seconds else null
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
    val measurement: TrackMeasurement,
    val pointCount: Int,
    val elevationGain: ElevationGain,
    // Increases on every resume, so distance is never counted across a pause.
    val segmentIndex: Int,
    // Last accepted point of the current segment.
    val lastPoint: TrackPoint?,
    val currentSpeedMetersPerSecond: Double?,
    // Null when the sport doesn't count steps or no pedometer reading has arrived (e.g. no permission).
    val stepCount: StepCount? = null,
) {
    val distanceMeters: Double get() = measurement.distanceMeters
    val movingTimeSeconds: Double get() = measurement.movingTimeSeconds

    // False while standing still, which the UI shows as auto-paused.
    val isMoving: Boolean get() = measurement.isMoving

    val steps: Int? get() = stepCount?.steps

    companion object {
        // With a departure, the activity starts when the user set off, and the stretch walked before
        // recording counts as moving time, distance and steps.
        fun startingAt(sport: Sport, time: Instant, departure: Departure? = null): ActivityProgress {
            val startedAt = departure?.at?.coerceAtMost(time) ?: time
            val leadIn = time - startedAt
            return ActivityProgress(
                sport = sport,
                startedAt = startedAt,
                activeTimeBeforeResume = leadIn,
                measurement = departure?.let { TrackMeasurement.continuing(it.distanceMeters, leadIn) } ?: TrackMeasurement.EMPTY,
                pointCount = 0,
                elevationGain = ElevationGain.NONE,
                segmentIndex = 0,
                lastPoint = null,
                currentSpeedMetersPerSecond = null,
                stepCount = departure?.steps?.takeIf { sport.countsSteps }?.let { StepCount(it, lastReading = null) },
            )
        }
    }
}

data class RecordedPoint(val segmentIndex: Int, val point: TrackPoint)
