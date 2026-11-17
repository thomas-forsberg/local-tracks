import Foundation

// The folder holding the SQLite database and its -wal/-shm files.
enum DatabaseDirectory {
    // File protection completeUntilFirstUserAuthentication: encrypted until the first unlock after boot,
    // then writable while locked, which recording needs. Files created in the folder inherit it.
    // Excluded from iCloud backup by default; a setting to include it comes later.
    static func prepare(
        in baseDirectory: URL,
        excludedFromBackup: Bool = true,
        fileManager: FileManager = .default
    ) throws -> URL {
        var directory = baseDirectory.appending(path: "Database", directoryHint: .isDirectory)
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
}
