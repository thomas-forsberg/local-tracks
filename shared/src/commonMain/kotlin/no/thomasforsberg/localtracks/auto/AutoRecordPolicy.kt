package no.thomasforsberg.localtracks.auto

import no.thomasforsberg.localtracks.recording.Sport
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Instant

// What the phone's motion classifier says the user is doing.
enum class MotionKind { STATIONARY, WALKING, RUNNING, CYCLING, AUTOMOTIVE, UNKNOWN }

// The classifier reports changes, so a sample's kind holds until the next sample.
data class MotionSample(val kind: MotionKind, val at: Instant)

enum class AutoRecordPhase {
    // Inside the home circle with nothing going on.
    AT_HOME,

    // Just left home: watching the motion sensors to see how the user is moving.
    WATCHING,

    // Recording started automatically; it stops when the user gets home.
    AUTO_RECORDING,

    // The user started recording by hand; left alone until it's stopped.
    MANUAL_RECORDING,

    // Drove off, gave up watching, or stopped a recording while out: nothing starts until home again.
    WAITING_FOR_HOME,
}

// Kept across app launches: iOS relaunches the app for each home event.
data class AutoRecordState(val phase: AutoRecordPhase, val isHome: Boolean, val leftHomeAt: Instant?) {
    companion object {
        val INITIAL = AutoRecordState(AutoRecordPhase.AT_HOME, isHome = true, leftHomeAt = null)
    }
}

sealed interface AutoRecordDecision {
    data object None : AutoRecordDecision

    // Start the motion sensors (and keep the app running) to see how the user moves.
    data object StartWatching : AutoRecordDecision

    data object StopWatching : AutoRecordDecision

    // departedAt is when the user set off on foot, for filling in the stretch before recording started;
    // null when there's nothing to fill in (cycling: a few hundred metres hardly matter).
    data class StartRecording(val sport: Sport, val departedAt: Instant?) : AutoRecordDecision

    data object StopRecording : AutoRecordDecision
}

// When to start and stop recording automatically around home. Pure logic: the platform feeds it home
// events, motion samples and clock ticks, and carries out the decisions it returns.
class AutoRecordPolicy(
    initial: AutoRecordState = AutoRecordState.INITIAL,
    private val holdBack: Duration = HOLD_BACK,
    private val watchLimit: Duration = WATCH_LIMIT,
) {
    // For Swift, where Kotlin default arguments aren't available.
    constructor(initial: AutoRecordState) : this(initial, HOLD_BACK, WATCH_LIMIT)

    var state: AutoRecordState = initial
        private set

    // The current stretch of self-propelled movement; not persisted, the motion history is replayed instead.
    private var run: Run? = null

    fun leftHome(at: Instant): AutoRecordDecision {
        state = state.copy(isHome = false, leftHomeAt = at)
        if (state.phase != AutoRecordPhase.AT_HOME) return AutoRecordDecision.None
        run = null
        state = state.copy(phase = AutoRecordPhase.WATCHING)
        return AutoRecordDecision.StartWatching
    }

    fun arrivedHome(): AutoRecordDecision {
        val previous = state.phase
        state = state.copy(isHome = true, leftHomeAt = null)
        if (previous == AutoRecordPhase.MANUAL_RECORDING) return AutoRecordDecision.None
        state = state.copy(phase = AutoRecordPhase.AT_HOME)
        run = null
        return when (previous) {
            AutoRecordPhase.AUTO_RECORDING -> AutoRecordDecision.StopRecording
            AutoRecordPhase.WATCHING -> AutoRecordDecision.StopWatching
            else -> AutoRecordDecision.None
        }
    }

    // Samples must arrive in time order; history from before leaving home may be included.
    fun motion(sample: MotionSample): AutoRecordDecision {
        if (state.phase != AutoRecordPhase.WATCHING) return AutoRecordDecision.None
        val category = sample.kind.category
        when {
            sample.kind == MotionKind.AUTOMOTIVE -> {
                if (!isBeforeLeaving(sample.at)) return giveUpUntilHome()
                run = null // drove before leaving, e.g. arriving home earlier
            }
            category != null -> {
                val current = run
                run = if (current?.category == category) current.copy(latest = sample.kind) else Run(category, sample.at, sample.kind)
            }
            sample.kind == MotionKind.STATIONARY -> run = null
            // UNKNOWN: low confidence, keep whatever was going on.
        }
        return tick(sample.at)
    }

    // Called regularly while watching, since the classifier only reports changes.
    fun tick(now: Instant): AutoRecordDecision {
        if (state.phase != AutoRecordPhase.WATCHING) return AutoRecordDecision.None
        val current = run
        if (current != null && now - current.since >= holdBack) {
            state = state.copy(phase = AutoRecordPhase.AUTO_RECORDING)
            run = null
            return AutoRecordDecision.StartRecording(current.sport, departedAt(current))
        }
        val leftAt = state.leftHomeAt
        return if (leftAt != null && now - leftAt >= watchLimit) giveUpUntilHome() else AutoRecordDecision.None
    }

    fun manualRecordingStarted(): AutoRecordDecision {
        val wasWatching = state.phase == AutoRecordPhase.WATCHING
        state = state.copy(phase = AutoRecordPhase.MANUAL_RECORDING)
        run = null
        return if (wasWatching) AutoRecordDecision.StopWatching else AutoRecordDecision.None
    }

    // Any recording ended, by hand or automatically. Out and about, nothing new starts until home.
    fun recordingStopped() {
        if (state.phase != AutoRecordPhase.AUTO_RECORDING && state.phase != AutoRecordPhase.MANUAL_RECORDING) return
        state = state.copy(phase = if (state.isHome) AutoRecordPhase.AT_HOME else AutoRecordPhase.WAITING_FOR_HOME)
    }

    private fun giveUpUntilHome(): AutoRecordDecision {
        state = state.copy(phase = AutoRecordPhase.WAITING_FOR_HOME)
        run = null
        return AutoRecordDecision.StopWatching
    }

    private fun isBeforeLeaving(at: Instant) = state.leftHomeAt?.let { at < it } ?: false

    // On foot, the walk started inside the home circle; the backfill covers it. Bounded, so that
    // pottering about the house for an hour isn't counted.
    private fun departedAt(run: Run): Instant? {
        if (run.category != Category.ON_FOOT) return null
        val earliest = state.leftHomeAt?.minus(MAX_BACKFILL)
        return if (earliest != null && run.since < earliest) earliest else run.since
    }

    private enum class Category { ON_FOOT, CYCLING }

    private data class Run(val category: Category, val since: Instant, val latest: MotionKind) {
        val sport: Sport get() = when {
            category == Category.CYCLING -> Sport.CYCLING
            latest == MotionKind.RUNNING -> Sport.RUNNING
            else -> Sport.HIKING
        }
    }

    private val MotionKind.category: Category?
        get() = when (this) {
            MotionKind.WALKING, MotionKind.RUNNING -> Category.ON_FOOT
            MotionKind.CYCLING -> Category.CYCLING
            else -> null
        }

    companion object {
        // Moving this long without driving means it's an activity, not the walk to the car.
        val HOLD_BACK: Duration = 2.minutes

        // Leaving home without walking, running or cycling for this long (a bus, a visit next door)
        // stops the watching, which would otherwise keep GPS running.
        val WATCH_LIMIT: Duration = 10.minutes

        // iOS notices leaving the home circle a little late; this covers that and the hold-back.
        val MAX_BACKFILL: Duration = 5.minutes
    }
}

// Automatic recordings this short are deleted: a trip to the mailbox isn't an activity.
val MIN_AUTO_RECORDING_TIME: Duration = 5.minutes
const val MIN_AUTO_RECORDING_METERS = 300.0
