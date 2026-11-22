package no.thomasforsberg.localtracks.maps

import io.ktor.client.engine.darwin.Darwin

// Downloads into region files in mapsDirectoryPath, over URLSession.
fun createIosRegionDownloader(repository: MapRegionRepository, mapsDirectoryPath: String): RegionDownloader =
    RegionDownloader(tileHttpClient(Darwin.create()), repository) { region -> openIosMBTiles(mapsDirectoryPath, region.fileName) }
