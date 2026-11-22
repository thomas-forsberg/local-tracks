import Foundation

// The folder holding the SQLite database and its -wal/-shm files, and the one holding map regions.
enum DatabaseDirectory {
    // File protection completeUntilFirstUserAuthentication: encrypted until the first unlock after boot,
    // then writable while locked, which recording needs. Files created in the folder inherit it.
    // Excluded from iCloud backup by default; a setting to include it comes later.
    static func prepare(
        in baseDirectory: URL,
        named name: String = "Database",
        excludedFromBackup: Bool = true,
        fileManager: FileManager = .default
    ) throws -> URL {
        var directory = baseDirectory.appending(path: name, directoryHint: .isDirectory)
        let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: protection)
        // createDirectory ignores attributes when the folder already exists.
        try fileManager.setAttributes(protection, ofItemAtPath: directory.path(percentEncoded: false))

        var values = URLResourceValues()
        values.isExcludedFromBackup = excludedFromBackup
        try directory.setResourceValues(values)
        return directory
    }

    static func applicationSupport(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    // Map regions go in Library/Maps: MapLibre is given their paths in mbtiles:// URLs, and
    // "Application Support" has a space in it.
    static func library(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }
}
