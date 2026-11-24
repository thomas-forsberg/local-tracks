package no.thomasforsberg.localtracks.track

import no.thomasforsberg.localtracks.recording.LeadIn
import no.thomasforsberg.localtracks.recording.RecordedPoint
import no.thomasforsberg.localtracks.recording.Sport
import kotlin.math.roundToInt

// Speed and incline are taken over pieces this long, so barometer noise doesn't read as steep slopes.
const val ENERGY_PIECE_METERS = 100.0

// Above this, the running equation applies on foot; below RUN_MIN when the sport is running too
// (walking breaks). In between, the sport decides.
const val WALK_MAX_METERS_PER_SECOND = 2.2
const val RUN_MIN_METERS_PER_SECOND = 1.67

private const val MAX_GRADE = 0.25
private const val KCAL_PER_LITRE_OXYGEN = 5.0

// Active energy (on top of resting) per kg of body weight, so it's stored once and the weight applies
// when shown. On foot: the ACSM walking and running equations from speed and incline. Cycling: METs by
// speed from the Compendium of Physical Activities. Only moving time counts; the stretch before GPS
// started counts as flat walking.
fun activeKcalPerKg(points: List<RecordedPoint>, sport: Sport, leadIn: LeadIn?): Double {
    val samples = samplesAlong(points, sport)
    val recorded = if (samples.size < 2) {
        0.0
    } else {
        val total = samples.last().distance
        val boundaries = generateSequence(ENERGY_PIECE_METERS) { it + ENERGY_PIECE_METERS }.takeWhile { it < total }.toList() + total
        boundaries.fold(0.0 to samples.first()) { (kcal, from), boundary ->
            val to = samples.interpolatedAt(boundary)
            val climb = if (to.elevation != null && from.elevation != null) to.elevation - from.elevation else 0.0
            kcal + kcalPerKg(sport, to.distance - from.distance, to.movingSeconds - from.movingSeconds, climb) to to
        }.first
    }
    val beforeGps = leadIn?.let { kcalPerKg(Sport.HIKING, it.distanceMeters, it.durationSeconds, climbMeters = 0.0) } ?: 0.0
    return recorded + beforeGps
}

fun kcalPerKg(sport: Sport, meters: Double, seconds: Double, climbMeters: Double): Double {
    if (meters <= 0 || seconds <= 0) return 0.0
    val speed = meters / seconds
    val hours = seconds / 3600
    if (sport == Sport.CYCLING) return (cyclingMet(speed * 3.6) - 1) * hours
    val grade = (climbMeters / meters).coerceIn(0.0, MAX_GRADE)
    val metersPerMinute = speed * 60
    val running = speed > WALK_MAX_METERS_PER_SECOND || (sport == Sport.RUNNING && speed >= RUN_MIN_METERS_PER_SECOND)
    // ml oxygen per kg per minute, above the 3.5 used at rest.
    val oxygen = if (running) 0.2 * metersPerMinute + 0.9 * metersPerMinute * grade else 0.1 * metersPerMinute + 1.8 * metersPerMinute * grade
    return oxygen * seconds / 60 / 1000 * KCAL_PER_LITRE_OXYGEN
}

private fun cyclingMet(kilometersPerHour: Double): Double = when {
    kilometersPerHour < 16.0 -> 4.0
    kilometersPerHour < 19.3 -> 6.8
    kilometersPerHour < 22.5 -> 8.0
    kilometersPerHour < 25.8 -> 10.0
    kilometersPerHour < 30.6 -> 12.0
    else -> 15.8
}

// For display: rounded to whole kilocalories.
fun activeKcal(kcalPerKg: Double, weightKilograms: Double): Int = (kcalPerKg * weightKilograms).roundToInt()
