package no.thomasforsberg.localtracks.storage

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.native.inMemoryDriver
import no.thomasforsberg.localtracks.db.LocalTracksDatabase

actual fun createInMemoryDriver(): SqlDriver = inMemoryDriver(LocalTracksDatabase.Schema)
