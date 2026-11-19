package no.thomasforsberg.localtracks.recording

// Below this speed the activity counts as standing still: no distance, no moving time.
enum class Sport(val movingThresholdMetersPerSecond: Double) {
    CYCLING(1.0),
    RUNNING(0.6),
    HIKING(0.4),
}
