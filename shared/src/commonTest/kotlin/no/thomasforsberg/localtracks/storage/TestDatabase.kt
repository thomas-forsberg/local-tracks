package no.thomasforsberg.localtracks.storage

import app.cash.sqldelight.db.SqlDriver
import no.thomasforsberg.localtracks.db.LocalTracksDatabase

expect fun createInMemoryDriver(): SqlDriver

fun createTestDatabase(): LocalTracksDatabase = createDatabase(createInMemoryDriver())
