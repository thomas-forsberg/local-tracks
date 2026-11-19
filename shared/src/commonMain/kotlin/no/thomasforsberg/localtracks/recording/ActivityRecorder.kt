package no.thomasforsberg.localtracks.recording

import kotlinx.coroutines.flow.StateFlow
import no.thomasforsberg.localtracks.recording.RecordingState.Finished
import no.thomasforsberg.localtracks.storage.ActivityRepository
import no.thomasforsberg.localtracks.storage.ActivitySummary
import no.thomasforsberg.localtracks.storage.ActivityTotals
import no.thomasforsberg.localtracks.track.TrackMeasurement
import kotlin.time.Clock
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

// Records a session to storage. Accepted points are buffered and written in batches every
// flushInterval, and on pause, stop and flush(), so a crash loses at most the last few seconds.
// Not thread-safe: call it from one thread (the main actor on iOS).
class ActivityRecorder(
    private val session: RecordingSession,
    private val repository: ActivityRepository,
    private val clock: Clock,
    private val stateStore: RecordingStateStore = InMemoryRecordingStateStore(),
    private val flushInterval: Duration = DEFAULT_FLUSH_INTERVAL,
) {
    // For Swift, where Kotlin default arguments aren't available.
    constructor(repository: ActivityRepository, stateStore: RecordingStateStore) :
        this(RecordingSession(), repository, Clock.System, stateStore)

    val state: StateFlow<RecordingState> get() = session.state

    private var activityId: Long? = null
    private var storedPointCount = 0
    private val pendingPoints = mutableListOf<RecordedPoint>()
    private var lastFlushAt: Instant = clock.now()

    fun start(sport: Sport): Boolean {
        if (!session.start(sport)) return false
        val progress = checkNotNull(state.value.progressOrNull())
        attach(repository.startActivity(sport, progress.startedAt), storedPointCount = 0)
        stateStore.clear()
        return true
    }

    fun pause(): Boolean {
        if (!session.pause()) return false
        flush()
        activityId?.let(stateStore::markPaused)
        return true
    }

    fun resume(): Boolean = session.resume().also { resumed -> if (resumed) stateStore.clear() }

    fun stop(): Boolean {
        if (!session.stop()) return false
        val finished = state.value as Finished
        flush()
        activityId?.let { repository.finishActivity(it, finished.finishedAt, totalsOf(finished)) }
        activityId = null
        stateStore.clear()
        return true
    }

    // Returns whether the fix was recorded.
    fun onLocation(fix: LocationFix): Boolean {
        val recorded = session.onLocation(fix) ?: return false
        pendingPoints += recorded
        if (clock.now() - lastFlushAt >= flushInterval) flush()
        return true
    }

    fun onBarometer(reading: BarometerReading) = session.onBarometer(reading)

    fun onMotion(stationary: Boolean?) = session.onMotion(stationary)

    // Also call this when the app moves to the background.
    fun flush() {
        val id = activityId ?: return
        repository.appendPoints(id, firstSeq = storedPointCount, points = pendingPoints.toList(), totals = totalsOf(state.value))
        storedPointCount += pendingPoints.size
        pendingPoints.clear()
        lastFlushAt = clock.now()
    }

    // An activity that was still recording when the app crashed or was killed.
    fun unfinishedActivity(): ActivitySummary? =
        if (activityId == null) repository.latestUnfinishedActivity() else null

    // After the user reopens the app: continues the unfinished activity straight away, in a new
    // segment, so one tap on "Resume" is enough. The time the app wasn't running isn't counted.
    fun resumeUnfinished(): Boolean {
        restoreUnfinished() ?: return false
        stateStore.clear()
        return session.resume()
    }

    // After iOS relaunches the app in the background (e.g. it was killed for memory during a ride):
    // continues without any user action, staying paused if the activity was paused when the app died.
    fun continueAfterRelaunch(): Boolean {
        val unfinished = restoreUnfinished() ?: return false
        if (stateStore.pausedActivityId() == unfinished.id) return true
        stateStore.clear() // a stale flag for another activity
        return session.resume()
    }

    // Restores the unfinished activity as Paused, so the gap is never counted as distance or time.
    private fun restoreUnfinished(): ActivitySummary? {
        val unfinished = unfinishedActivity() ?: return null
        val lastPoint = repository.lastTrackPoint(unfinished.id)
        val progress = ActivityProgress(
            sport = unfinished.sport,
            startedAt = unfinished.startedAt,
            activeTimeBeforeResume = unfinished.totals.activeTime,
            measurement = TrackMeasurement.continuing(unfinished.totals.distanceMeters, unfinished.totals.movingTime),
            pointCount = unfinished.totals.pointCount,
            elevationGain = ElevationGain(unfinished.totals.elevationGainMeters, referenceMeters = null),
            segmentIndex = lastPoint?.segmentIndex ?: 0,
            lastPoint = lastPoint?.point,
            currentSpeedMetersPerSecond = null,
        )
        if (!session.restore(progress)) return null
        attach(unfinished.id, storedPointCount = unfinished.totals.pointCount)
        return unfinished
    }

    // Saves the unfinished activity as it was at its last stored point.
    fun finishUnfinished(): Boolean {
        val unfinished = unfinishedActivity() ?: return false
        val finishedAt = repository.lastTrackPoint(unfinished.id)?.point?.time ?: unfinished.startedAt
        repository.finishActivity(unfinished.id, finishedAt, unfinished.totals)
        stateStore.clear()
        return true
    }

    private fun attach(id: Long, storedPointCount: Int) {
        activityId = id
        this.storedPointCount = storedPointCount
        pendingPoints.clear()
        lastFlushAt = clock.now()
    }

    private fun totalsOf(state: RecordingState): ActivityTotals {
        val progress = checkNotNull(state.progressOrNull())
        return ActivityTotals(
            activeTime = state.activeTime(clock.now()),
            distanceMeters = progress.distanceMeters,
            pointCount = progress.pointCount,
            elevationGainMeters = progress.elevationGain.meters,
            movingTime = progress.measurement.movingTime,
        )
    }

    companion object {
        val DEFAULT_FLUSH_INTERVAL: Duration = 5.seconds
    }
}
