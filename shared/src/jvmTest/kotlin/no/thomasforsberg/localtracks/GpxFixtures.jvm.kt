package no.thomasforsberg.localtracks

actual fun environmentVariable(name: String): String? = System.getenv(name)
