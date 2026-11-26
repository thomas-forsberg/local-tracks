package no.thomasforsberg.localtracks.auto

import no.thomasforsberg.localtracks.recording.RecordedPoint
import no.thomasforsberg.localtracks.recording.Sport
import no.thomasforsberg.localtracks.track.Sample
import no.thomasforsberg.localtracks.track.samplesAlong
import kotlin.math.roundToInt
import kotlin.time.Instant

enum class TripVerdict {
    // Nothing suggests driving.
    KEEP,

    // Recorded on foot, but at bike speeds and with no sign of a car.
    CYCLING,

    // Some sign of driving, not enough to be sure: kept, and the user is asked.
    SUSPECTED_CAR,

    // Sure enough to delete it.
    CAR,
}

data class TripJudgement(val verdict: TripVerdict, val reason: String)

// What an automatic recording's sensors say about whether it was a car ride. Recording too much is
// better than missing an activity, so only clear evidence deletes one.
object TripCheck {
    // Moving time per window for speeds and effort: long enough to smooth over GPS jumps and sprints.
    const val WINDOW_SECONDS = 180.0
    const val TOP_SPEED_WINDOW_SECONDS = 30.0

    // A strong amateur holds about 300 W for a few minutes; 600 W is beyond nearly everyone.
    const val IMPOSSIBLE_WATTS = 600.0

    // Only a few long descents take a bike this fast for half a minute.
    const val CAR_SPEED_METERS_PER_SECOND = 25.0

    // Faster than this for minutes isn't running.
    const val BIKE_SPEED_METERS_PER_SECOND = 5.5

    // motion: the classifier's samples from before the first point until `until`, in time order.
    fun judge(points: List<RecordedPoint>, sport: Sport, motion: List<MotionSample>, until: Instant, carAudio: Boolean): TripJudgement {
        val start = points.firstNotNullOfOrNull { it.point.time } ?: until
        val shares = motionShares(motion, start, until)
        val samples = samplesAlong(points, Sport.CYCLING)
        val watts = maxCyclingWatts(samples)
        val topSpeed = maxAverageSpeed(samples, TOP_SPEED_WINDOW_SECONDS)
        val fastest = maxAverageSpeed(samples, WINDOW_SECONDS)
        val facts = "driving ${shares.driving.percent()} %, cycling ${shares.cycling.percent()} %, " +
            "top ${(topSpeed * 3.6).roundToInt()} km/h, ${watts.roundToInt()} W on a bike"
        val impossibleOnABike = watts > IMPOSSIBLE_WATTS || topSpeed > CAR_SPEED_METERS_PER_SECOND
        return when {
            carAudio -> TripJudgement(TripVerdict.CAR, "CarPlay was connected; $facts")
            shares.driving >= 0.5 && shares.cycling < 0.2 -> TripJudgement(TripVerdict.CAR, facts)
            impossibleOnABike && shares.cycling < 0.5 -> TripJudgement(TripVerdict.CAR, facts)
            shares.driving >= 0.2 || impossibleOnABike -> TripJudgement(TripVerdict.SUSPECTED_CAR, facts)
            sport != Sport.CYCLING && (fastest > BIKE_SPEED_METERS_PER_SECOND || shares.cycling >= 0.5) ->
                TripJudgement(TripVerdict.CYCLING, facts)
            else -> TripJudgement(TripVerdict.KEEP, facts)
        }
    }

    // Shares of the time spent moving: each sample holds until the next. Standing still and uncertain
    // readings don't count either way.
    internal data class Shares(val driving: Double, val cycling: Double)

    internal fun motionShares(motion: List<MotionSample>, start: Instant, until: Instant): Shares {
        val seconds = mutableMapOf<MotionKind, Double>()
        motion.forEachIndexed { index, sample ->
            val from = maxOf(sample.at, start)
            val to = minOf(motion.getOrNull(index + 1)?.at ?: until, until)
            if (to > from) seconds[sample.kind] = (seconds[sample.kind] ?: 0.0) + (to - from).inWholeMilliseconds / 1000.0
        }
        val moving = listOf(MotionKind.WALKING, MotionKind.RUNNING, MotionKind.CYCLING, MotionKind.AUTOMOTIVE).sumOf { seconds[it] ?: 0.0 }
        if (moving <= 0) return Shares(0.0, 0.0)
        return Shares((seconds[MotionKind.AUTOMOTIVE] ?: 0.0) / moving, (seconds[MotionKind.CYCLING] ?: 0.0) / moving)
    }

    // The most power a cyclist would need over any window: rolling resistance, climbing and air.
    // Rider and bike 85 kg, upright on the hoods.
    internal fun cyclingWatts(speed: Double, grade: Double): Double =
        speed * 85.0 * 9.81 * (0.005 + grade) + 0.5 * 1.2 * 0.4 * speed * speed * speed

    private fun maxCyclingWatts(samples: List<Sample>): Double = windows(samples, WINDOW_SECONDS).maxOfOrNull { (from, to) ->
        val meters = to.distance - from.distance
        val speed = meters / (to.movingSeconds - from.movingSeconds)
        val climb = if (from.elevation != null && to.elevation != null) to.elevation - from.elevation else 0.0
        cyclingWatts(speed, if (meters > 0) climb / meters else 0.0)
    } ?: 0.0

    private fun maxAverageSpeed(samples: List<Sample>, seconds: Double): Double = windows(samples, seconds).maxOfOrNull { (from, to) ->
        (to.distance - from.distance) / (to.movingSeconds - from.movingSeconds)
    } ?: 0.0

    // Each sample paired with the point `seconds` of moving time later.
    private fun windows(samples: List<Sample>, seconds: Double): List<Pair<Sample, Sample>> {
        val result = mutableListOf<Pair<Sample, Sample>>()
        var end = 0
        for (from in samples) {
            while (end < samples.size && samples[end].movingSeconds - from.movingSeconds < seconds) end++
            if (end == samples.size) break
            result += from to samples[end]
        }
        return result
    }

    private fun Double.percent() = (this * 100).roundToInt()
}
