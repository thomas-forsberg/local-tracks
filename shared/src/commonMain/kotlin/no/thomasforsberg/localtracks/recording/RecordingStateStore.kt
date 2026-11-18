package no.thomasforsberg.localtracks.recording

// Remembers whether the activity in progress is paused, so that survives the app being killed.
// It's app state rather than activity data, so it lives in platform key-value storage
// (UserDefaults on iOS), not the database. The database stays the source of truth for
// *whether* there is an unfinished activity; this only says which one was paused.
interface RecordingStateStore {
    fun pausedActivityId(): Long?

    fun markPaused(activityId: Long)

    fun clear()
}

class InMemoryRecordingStateStore : RecordingStateStore {
    private var pausedActivityId: Long? = null

    override fun pausedActivityId(): Long? = pausedActivityId

    override fun markPaused(activityId: Long) {
        pausedActivityId = activityId
    }

    override fun clear() {
        pausedActivityId = null
    }
}
