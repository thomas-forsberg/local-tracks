package no.thomasforsberg.localtracks.recording

// movingThresholdMetersPerSecond: below this speed the activity counts as standing still (no distance, no moving time).
enum class Sport(val movingThresholdMetersPerSecond: Double, val countsSteps: Boolean) {
    CYCLING(1.0, countsSteps = false),
    RUNNING(0.6, countsSteps = false),
    HIKING(0.4, countsSteps = true),
}
