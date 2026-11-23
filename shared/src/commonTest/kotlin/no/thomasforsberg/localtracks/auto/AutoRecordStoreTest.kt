package no.thomasforsberg.localtracks.auto

import no.thomasforsberg.localtracks.storage.createTestDatabase
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.time.Instant

class AutoRecordStoreTest {
    private val store = AutoRecordStore(createTestDatabase())

    @Test
    fun startsDisabledWithoutAHome() {
        assertEquals(AutoRecordSettings(enabled = false, home = null), store.settings())
        assertEquals(AutoRecordState.INITIAL, store.state())
    }

    @Test
    fun keepsSettingsAndState() {
        val home = HomeLocation(59.94, 10.72)
        store.setHome(home)
        store.setEnabled(true)
        val state = AutoRecordState(
            AutoRecordPhase.ARRIVING_HOME,
            isHome = true,
            leftHomeAt = Instant.parse("2026-11-23T08:00:00Z"),
            arrivedHomeAt = Instant.parse("2026-11-23T09:00:00Z"),
        )
        store.saveState(state)

        assertEquals(AutoRecordSettings(enabled = true, home = home), store.settings())
        assertEquals(state, store.state())

        store.setHome(null)
        assertEquals(null, store.settings().home)
    }
}
