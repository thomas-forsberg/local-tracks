package no.thomasforsberg.localtracks.storage

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.native.inMemoryDriver
import no.thomasforsberg.localtracks.db.LocalTracksDatabase
import no.thomasforsberg.localtracks.maps.db.MBTilesDatabase

actual fun createInMemoryDriver(): SqlDriver = inMemoryDriver(LocalTracksDatabase.Schema)

actual fun createInMemoryMBTilesDriver(): SqlDriver = inMemoryDriver(MBTilesDatabase.Schema)
