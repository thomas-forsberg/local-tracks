package no.thomasforsberg.localtracks.recording

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import no.thomasforsberg.localtracks.recording.RecordingState.Finished
import no.thomasforsberg.localtracks.recording.RecordingState.Idle
import no.thomasforsberg.localtracks.recording.RecordingState.Paused
import no.thomasforsberg.localtracks.recording.RecordingState.Recording
import no.thomasforsberg.localtracks.track.TrackPoint
import kotlin.time.Clock
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.DurationUnit
import no.thomasforsberg.localtracks.geo.distanceMeters as distanceBetween

const val DEFAULT_MAX_HORIZONTAL_ACCURACY_METERS = 20.0

// Safe to call from any thread: all state lives in one atomically updated StateFlow.
// Invalid transitions (e.g. pause while idle) are ignored and return false rather than throwing,
// so a UI race can never crash a recording.
class RecordingSession(
    private val clock: Clock,
    private val maxHorizontalAccuracyMeters: Double = DEFAULT_MAX_HORIZONTAL_ACCURACY_METERS,
) {
    constructor() : this(Clock.System)

    private val mutableState = MutableStateFlow<RecordingState>(Idle)
    val state: StateFlow<RecordingState> = mutableState.asStateFlow()

    private val latestBarometer = MutableStateFlow<BarometerReading?>(null)

    fun start(sport: Sport): Boolean = transition { current ->
        when (current) {
            Idle, is Finished -> clock.now().let { now -> Recording(ActivityProgress.startingAt(sport, now), resumedAt = now) }
            is Recording, is Paused -> null
        }
    }

    fun pause(): Boolean = transition { current ->
        (current as? Recording)?.let {
            val now = clock.now()
            Paused(it.progress.copy(activeTimeBeforeResume = it.activeTime(now)), pausedAt = now)
        }
    }

    fun resume(): Boolean = transition { current ->
        (current as? Paused)?.let {
            Recording(
                it.progress.copy(
                    segmentIndex = it.progress.segmentIndex + 1,
                    lastPoint = null,
                    currentSpeedMetersPerSecond = null,
                    elevationGain = it.progress.elevationGain.startingNewSegment(),
                ),
                resumedAt = clock.now(),
            )
        }
    }

    fun stop(): Boolean = transition { current ->
        val now = clock.now()
        when (current) {
            is Recording -> Finished(current.progress.copy(activeTimeBeforeResume = current.activeTime(now)), finishedAt = now)
            is Paused -> Finished(current.progress, finishedAt = now)
            Idle, is Finished -> null
        }
    }

    // Brings back an activity interrupted by a crash or the app being killed. It starts as Paused,
    // so resume() opens a new segment and the gap is never counted as distance.
    fun restore(progress: ActivityProgress): Boolean = transition { current ->
        when (current) {
            Idle, is Finished -> Paused(progress.copy(currentSpeedMetersPerSecond = null), pausedAt = clock.now())
            is Recording, is Paused -> null
        }
    }

    fun onBarometer(reading: BarometerReading) {
        latestBarometer.value = reading
    }

    // Returns the point to persist, or null if the fix was rejected or nothing is being recorded.
    fun onLocation(fix: LocationFix): RecordedPoint? {
        var recorded: RecordedPoint? = null
        mutableState.update { current ->
            recorded = null
            val recording = current as? Recording ?: return@update current
            val point = acceptedPoint(fix, recording) ?: return@update current
            recorded = RecordedPoint(recording.progress.segmentIndex, point)
            recording.copy(progress = recording.progress.advancedTo(point))
        }
        return recorded
    }

    private fun acceptedPoint(fix: LocationFix, recording: Recording): TrackPoint? {
        val accurate = fix.horizontalAccuracyMeters in 0.0..maxHorizontalAccuracyMeters
        // Drops cached fixes from before start/resume, and duplicates or out-of-order delivery.
        val fresh = fix.time >= recording.resumedAt
        val inOrder = recording.progress.lastPoint?.time?.let { fix.time > it } ?: true
        if (!(accurate && fresh && inOrder)) return null

        return TrackPoint(
            latitude = fix.latitude,
            longitude = fix.longitude,
            elevationMeters = fix.altitudeMeters,
            time = fix.time,
            horizontalAccuracyMeters = fix.horizontalAccuracyMeters,
            speedMetersPerSecond = fix.speedMetersPerSecond?.takeIf { it >= 0 },
            barometer = latestBarometer.value?.takeIf { (fix.time - it.time).absoluteValue <= BAROMETER_MAX_AGE },
        )
    }

    private fun ActivityProgress.advancedTo(point: TrackPoint) = copy(
        distanceMeters = distanceMeters + (lastPoint?.let { distanceBetween(it, point) } ?: 0.0),
        pointCount = pointCount + 1,
        elevationGain = point.barometer?.let { elevationGain.adding(it.relativeAltitudeMeters) } ?: elevationGain,
        lastPoint = point,
        currentSpeedMetersPerSecond = point.speedMetersPerSecond ?: lastPoint?.let { speedBetween(it, point) },
    )

    private fun speedBetween(from: TrackPoint, to: TrackPoint): Double? {
        val fromTime = from.time ?: return null
        val toTime = to.time ?: return null
        val seconds = (toTime - fromTime).toDouble(DurationUnit.SECONDS)
        return if (seconds > 0) distanceBetween(from, to) / seconds else null
    }

    private inline fun transition(next: (RecordingState) -> RecordingState?): Boolean {
        var changed = false
        mutableState.update { current ->
            val updated = next(current)
            changed = updated != null
            updated ?: current
        }
        return changed
    }

    private companion object {
        val BAROMETER_MAX_AGE: Duration = 5.seconds
    }
}
