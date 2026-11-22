package no.thomasforsberg.localtracks.recording

// Steps from the phone's pedometer, which reports a running total since the sensor started.
// Only the increase between readings while recording counts, so steps taken while paused never do.
data class StepCount(
    val steps: Int,
    // The pedometer's previous running total; null right after start or restore.
    val lastReading: Int?,
) {
    fun counting(reading: Int): StepCount = copy(steps = steps + increaseTo(reading), lastReading = reading)

    fun skipping(reading: Int): StepCount = copy(lastReading = reading)

    // A reading below the last one means the pedometer was restarted and counts from zero again.
    private fun increaseTo(reading: Int): Int = reading - (lastReading?.takeIf { it <= reading } ?: 0)

    companion object {
        val NONE = StepCount(steps = 0, lastReading = null)
    }
}
