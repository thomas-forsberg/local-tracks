package no.thomasforsberg.localtracks.recording

import kotlinx.coroutines.flow.StateFlow
import no.thomasforsberg.localtracks.recording.RecordingState.Finished
import no.thomasforsberg.localtracks.storage.ActivityRepository
import no.thomasforsberg.localtracks.storage.ActivitySummary
import no.thomasforsberg.localtracks.storage.ActivityTotals
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
    private val flushInterval: Duration = DEFAULT_FLUSH_INTERVAL,
) {
    constructor(repository: ActivityRepository) : this(RecordingSession(), repository, Clock.System)

    val state: StateFlow<RecordingState> get() = session.state

    private var activityId: Long? = null
    private var storedPointCount = 0
    private val pendingPoints = mutableListOf<RecordedPoint>()
    private var lastFlushAt: Instant = clock.now()

    fun start(sport: Sport): Boolean {
        if (!session.start(sport)) return false
        val progress = checkNotNull(state.value.progressOrNull())
        attach(repository.startActivity(sport, progress.startedAt), storedPointCount = 0)
        return true
    }

    fun pause(): Boolean = session.pause().also { paused -> if (paused) flush() }

    fun resume(): Boolean = session.resume()

    fun stop(): Boolean {
        if (!session.stop()) return false
        val finished = state.value as Finished
        flush()
        activityId?.let { repository.finishActivity(it, finished.finishedAt, totalsOf(finished)) }
        activityId = null
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

    // Continues the unfinished activity: it is restored (as Paused, so the gap is never counted)
    // and resumed straight away in a new segment, so one tap on "Resume" is enough.
    fun resumeUnfinished(): Boolean {
        val unfinished = unfinishedActivity() ?: return false
        val lastPoint = repository.lastTrackPoint(unfinished.id)
        val progress = ActivityProgress(
            sport = unfinished.sport,
            startedAt = unfinished.startedAt,
            activeTimeBeforeResume = unfinished.totals.activeTime,
            distanceMeters = unfinished.totals.distanceMeters,
            pointCount = unfinished.totals.pointCount,
            elevationGain = ElevationGain(unfinished.totals.elevationGainMeters, referenceMeters = null),
            segmentIndex = lastPoint?.segmentIndex ?: 0,
            lastPoint = lastPoint?.point,
            currentSpeedMetersPerSecond = null,
        )
        if (!session.restore(progress)) return false
        attach(unfinished.id, storedPointCount = unfinished.totals.pointCount)
        return session.resume()
    }

    // Saves the unfinished activity as it was at its last stored point.
    fun finishUnfinished(): Boolean {
        val unfinished = unfinishedActivity() ?: return false
        val finishedAt = repository.lastTrackPoint(unfinished.id)?.point?.time ?: unfinished.startedAt
        repository.finishActivity(unfinished.id, finishedAt, unfinished.totals)
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
        return ActivityTotals(state.activeTime(clock.now()), progress.distanceMeters, progress.pointCount, progress.elevationGain.meters)
    }

    companion object {
        val DEFAULT_FLUSH_INTERVAL: Duration = 5.seconds
    }
}
