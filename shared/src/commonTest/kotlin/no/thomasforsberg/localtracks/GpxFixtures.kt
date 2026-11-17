package no.thomasforsberg.localtracks

import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString

expect fun environmentVariable(name: String): String?

object GpxFixtures {
    fun read(name: String): String {
        val directory = checkNotNull(environmentVariable("GPX_FIXTURES_DIR")) {
            "GPX_FIXTURES_DIR is not set; run the tests through Gradle"
        }
        return SystemFileSystem.source(Path(directory, name)).buffered().use { it.readString() }
    }
}
