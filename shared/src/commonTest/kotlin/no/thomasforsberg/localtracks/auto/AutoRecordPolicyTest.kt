package no.thomasforsberg.localtracks.auto

import no.thomasforsberg.localtracks.auto.AutoRecordDecision.None
import no.thomasforsberg.localtracks.auto.AutoRecordDecision.StartRecording
import no.thomasforsberg.localtracks.auto.AutoRecordDecision.StartWatching
import no.thomasforsberg.localtracks.auto.AutoRecordDecision.StopRecording
import no.thomasforsberg.localtracks.auto.AutoRecordDecision.StopWatching
import no.thomasforsberg.localtracks.auto.AutoRecordPhase.AT_HOME
import no.thomasforsberg.localtracks.auto.AutoRecordPhase.AUTO_RECORDING
import no.thomasforsberg.localtracks.auto.AutoRecordPhase.MANUAL_RECORDING
import no.thomasforsberg.localtracks.auto.AutoRecordPhase.WAITING_FOR_HOME
import no.thomasforsberg.localtracks.auto.AutoRecordPhase.WATCHING
import no.thomasforsberg.localtracks.auto.MotionKind.AUTOMOTIVE
import no.thomasforsberg.localtracks.auto.MotionKind.CYCLING
import no.thomasforsberg.localtracks.auto.MotionKind.RUNNING
import no.thomasforsberg.localtracks.auto.MotionKind.STATIONARY
import no.thomasforsberg.localtracks.auto.MotionKind.UNKNOWN
import no.thomasforsberg.localtracks.auto.MotionKind.WALKING
import no.thomasforsberg.localtracks.recording.Sport
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

class AutoRecordPolicyTest {
    private val leftAt = Instant.parse("2026-11-23T08:00:00Z")
    private val policy = AutoRecordPolicy()

    private fun at(seconds: Int) = leftAt + seconds.seconds

    private fun sample(kind: MotionKind, seconds: Int) = policy.motion(MotionSample(kind, at(seconds)))

    @Test
    fun leavingHomeStartsWatching() {
        assertEquals(StartWatching, policy.leftHome(leftAt))
        assertEquals(WATCHING, policy.state.phase)
        assertEquals(false, policy.state.isHome)
    }

    @Test
    fun walkingForTwoMinutesStartsAHikeFromWhenTheWalkBegan() {
        policy.leftHome(leftAt)
        // The walk began inside the home circle, before iOS reported leaving it.
        assertEquals(None, sample(WALKING, -60))
        assertEquals(None, policy.tick(at(30)))

        assertEquals(StartRecording(Sport.HIKING, departedAt = at(-60)), policy.tick(at(60)))
        assertEquals(AUTO_RECORDING, policy.state.phase)
    }

    @Test
    fun runningStartsARunAndSwitchingBetweenWalkingAndRunningKeepsTheClockGoing() {
        policy.leftHome(leftAt)
        sample(WALKING, 0)
        sample(RUNNING, 60)

        assertEquals(StartRecording(Sport.RUNNING, departedAt = at(0)), policy.tick(at(120)))
    }

    @Test
    fun cyclingStartsARideWithNothingToFillIn() {
        policy.leftHome(leftAt)
        sample(CYCLING, 10)

        assertEquals(StartRecording(Sport.CYCLING, departedAt = null), policy.tick(at(130)))
    }

    @Test
    fun drivingAfterLeavingBlocksAutoRecordingUntilHome() {
        policy.leftHome(leftAt)
        sample(WALKING, 0) // to the car
        assertEquals(StopWatching, sample(AUTOMOTIVE, 60))
        assertEquals(WAITING_FOR_HOME, policy.state.phase)

        // Out walking after parking: still nothing, until home again.
        assertEquals(None, sample(WALKING, 1800))
        assertEquals(None, policy.leftHome(at(1900)))
        assertEquals(None, policy.arrivedHome())
        assertEquals(AT_HOME, policy.state.phase)
        assertEquals(StartWatching, policy.leftHome(at(7200)))
    }

    @Test
    fun drivingBeforeLeavingHomeDoesNotBlock() {
        policy.leftHome(leftAt)
        sample(AUTOMOTIVE, -600) // history: arriving home by car earlier
        sample(WALKING, -30)

        assertEquals(StartRecording(Sport.HIKING, departedAt = at(-30)), policy.tick(at(90)))
    }

    @Test
    fun standingStillRestartsTheHoldBackButUncertainSamplesDoNot() {
        policy.leftHome(leftAt)
        sample(WALKING, 0)
        sample(UNKNOWN, 30)
        sample(STATIONARY, 60)
        sample(WALKING, 90)

        assertEquals(None, policy.tick(at(150)))
        assertEquals(StartRecording(Sport.HIKING, departedAt = at(90)), policy.tick(at(210)))
    }

    @Test
    fun theFilledInStretchIsBoundedSoPotteringAroundTheHouseDoesNotCount() {
        policy.leftHome(leftAt)
        sample(WALKING, -3600)

        assertEquals(StartRecording(Sport.HIKING, departedAt = leftAt - AutoRecordPolicy.MAX_BACKFILL), policy.tick(at(0)))
    }

    @Test
    fun givesUpWatchingWhenNothingHappensForTenMinutes() {
        policy.leftHome(leftAt)
        sample(STATIONARY, 0)

        assertEquals(None, policy.tick(at(9 * 60)))
        assertEquals(StopWatching, policy.tick(at(10 * 60)))
        assertEquals(WAITING_FOR_HOME, policy.state.phase)
    }

    @Test
    fun arrivingHomeStopsAnAutomaticRecording() {
        policy.leftHome(leftAt)
        sample(WALKING, 0)
        policy.tick(at(120))

        assertEquals(StopRecording, policy.arrivedHome())
        assertEquals(AT_HOME, policy.state.phase)
        policy.recordingStopped()
        assertEquals(AT_HOME, policy.state.phase)
    }

    @Test
    fun aManualRecordingIsLeftAloneAndBlocksUntilHomeWhenStoppedOut() {
        policy.leftHome(leftAt)
        assertEquals(StopWatching, policy.manualRecordingStarted())
        assertEquals(None, sample(WALKING, 0))
        assertEquals(None, policy.tick(at(600)))

        policy.recordingStopped()
        assertEquals(WAITING_FOR_HOME, policy.state.phase)
    }

    @Test
    fun aManualRecordingKeepsGoingWhenArrivingHome() {
        policy.manualRecordingStarted()
        policy.leftHome(leftAt)

        assertEquals(None, policy.arrivedHome())
        assertEquals(MANUAL_RECORDING, policy.state.phase)
        policy.recordingStopped()
        assertEquals(AT_HOME, policy.state.phase)
    }

    @Test
    fun stoppingAnAutomaticRecordingWhileOutWaitsForHome() {
        policy.leftHome(leftAt)
        sample(CYCLING, 0)
        policy.tick(at(120))

        policy.recordingStopped()
        assertEquals(WAITING_FOR_HOME, policy.state.phase)
    }

    @Test
    fun theStateCanBeRestoredAfterARelaunch() {
        policy.leftHome(leftAt)
        sample(AUTOMOTIVE, 60)

        val relaunched = AutoRecordPolicy(policy.state)
        assertEquals(None, relaunched.leftHome(at(600)))
        assertEquals(WAITING_FOR_HOME, relaunched.state.phase)
    }

    @Test
    fun aRelaunchWhileWatchingContinuesFromTheMotionHistory() {
        policy.leftHome(leftAt)
        val relaunched = AutoRecordPolicy(policy.state)

        relaunched.motion(MotionSample(WALKING, at(-20)))
        assertEquals(StartRecording(Sport.HIKING, at(-20)), relaunched.tick(at(100)))
    }

    @Test
    fun theHoldBackIsTwoMinutes() {
        assertEquals(2.minutes, AutoRecordPolicy.HOLD_BACK)
    }
}
