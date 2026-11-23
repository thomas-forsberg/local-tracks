package no.thomasforsberg.localtracks.recording

import kotlinx.coroutines.flow.StateFlow
import no.thomasforsberg.localtracks.auto.MIN_AUTO_RECORDING_METERS
import no.thomasforsberg.localtracks.auto.MIN_AUTO_RECORDING_TIME
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
// A failed write (e.g. a full disk) never stops the recording: the points stay buffered and are
// written on the next successful flush. Not thread-safe: call it from one thread (the main actor on iOS).
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

    // Null while recording if creating the database row failed; it's retried on every flush.
    private var activityId: Long? = null
    private var inProgress = false
    private var storedPointCount = 0
    private val pendingPoints = mutableListOf<RecordedPoint>()
    private var lastFlushAt: Instant = clock.now()

    // Whether the recording in progress was started by auto-record, and what it filled in before GPS started.
    var isAutoStarted: Boolean = false
        private set
    private var leadIn: LeadIn? = null

    // True after a failed database write, until the next one succeeds.
    var isStorageFailing: Boolean = false
        private set

    fun start(sport: Sport): Boolean = start(sport, departure = null, automatic = false)

    // For auto-record: the departure fills in the stretch walked before recording started (null for none).
    fun startAutomatically(sport: Sport, departure: Departure?): Boolean = start(sport, departure, automatic = true)

    private fun start(sport: Sport, departure: Departure?, automatic: Boolean): Boolean {
        if (!session.start(sport, departure)) return false
        attach(null, storedPointCount = 0)
        isAutoStarted = automatic
        leadIn = departure?.let {
            val progress = checkNotNull(state.value.progressOrNull())
            LeadIn(progress.activeTimeBeforeResume, it.distanceMeters, progress.steps)
        }
        stateStore.clear()
        write { ensureActivityId() }
        return true
    }

    // Stops an automatic recording when the user gets home, deleting it if it's too short to be an activity.
    fun stopAutomatically(): AutoStopResult {
        val id = activityId
        val wasAutomatic = isAutoStarted
        if (!stop()) return AutoStopResult.NOT_RECORDING
        val finished = state.value as Finished
        val tooShort = finished.progress.activeTimeBeforeResume < MIN_AUTO_RECORDING_TIME ||
            finished.progress.distanceMeters < MIN_AUTO_RECORDING_METERS
        if (wasAutomatic && tooShort && id != null) {
            write { repository.delete(id) }
            return AutoStopResult.DISCARDED
        }
        return AutoStopResult.KEPT
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
        // If this fails the activity stays unfinished in the database and is offered for recovery later.
        activityId?.let { id -> write { repository.finishActivity(id, finished.finishedAt, totalsOf(finished)) } }
        activityId = null
        inProgress = false
        isAutoStarted = false
        leadIn = null
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

    fun onSteps(stepsSinceSensorStart: Int) = session.onSteps(stepsSinceSensorStart)

    // Also call this when the app moves to the background.
    fun flush() {
        if (!inProgress) return
        lastFlushAt = clock.now()
        write {
            val id = ensureActivityId()
            repository.appendPoints(id, firstSeq = storedPointCount, points = pendingPoints.toList(), totals = totalsOf(state.value))
            storedPointCount += pendingPoints.size
            pendingPoints.clear()
        }
    }

    private fun ensureActivityId(): Long = activityId ?: run {
        val progress = checkNotNull(state.value.progressOrNull())
        repository.startActivity(progress.sport, progress.startedAt, isAutoStarted, leadIn).also { activityId = it }
    }

    private fun write(block: () -> Unit) {
        isStorageFailing = runCatching(block).isFailure
    }

    // Every point of the activity in progress, stored and not yet stored, e.g. to draw it on a live map
    // after the app was relaunched. Empty when nothing is in progress.
    fun recordedPoints(): List<RecordedPoint> {
        if (!inProgress) return emptyList()
        val stored = activityId?.let { id -> runCatching { repository.trackPoints(id) }.getOrNull() } ?: emptyList()
        return stored + pendingPoints
    }

    // An activity that was still recording when the app crashed or was killed.
    fun unfinishedActivity(): ActivitySummary? =
        if (inProgress) null else repository.latestUnfinishedActivity()

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
            stepCount = unfinished.totals.stepCount?.let { StepCount(it, lastReading = null) },
        )
        if (!session.restore(progress)) return null
        attach(unfinished.id, storedPointCount = unfinished.totals.pointCount)
        isAutoStarted = unfinished.autoStarted
        return unfinished
    }

    // Saves the unfinished activity as it was at its last stored point.
    fun finishUnfinished(): Boolean {
        val unfinished = unfinishedActivity() ?: return false
        val finishedAt = repository.lastTrackPoint(unfinished.id)?.point?.time ?: unfinished.startedAt
        write { repository.finishActivity(unfinished.id, finishedAt, unfinished.totals) }
        stateStore.clear()
        return !isStorageFailing
    }

    private fun attach(id: Long?, storedPointCount: Int) {
        activityId = id
        inProgress = true
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
            stepCount = progress.steps,
        )
    }

    companion object {
        val DEFAULT_FLUSH_INTERVAL: Duration = 5.seconds
    }
}

enum class AutoStopResult { NOT_RECORDING, KEPT, DISCARDED }
