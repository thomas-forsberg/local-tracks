import Foundation

// What auto-record saw and decided, newest last, so a walk that didn't start by itself can be explained
// afterwards. A plain text file next to the database; it never leaves the phone unless the user shares it.
@MainActor
final class AutoRecordLog {
    let file: URL
    private let maxLines: Int
    private let now: () -> Date
    private let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    init(file: URL, maxLines: Int = 1000, now: @escaping () -> Date = Date.init) {
        self.file = file
        self.maxLines = maxLines
        self.now = now
    }

    func add(_ message: String) {
        let line = "\(timestamp.string(from: now()))  \(message)\n"
        guard let handle = try? FileHandle(forWritingTo: file) else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
        trimIfNeeded()
    }

    func lines() -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    // Trims to `maxLines` once it's a fifth over, so the file isn't rewritten on every line.
    private func trimIfNeeded() {
        let all = lines()
        guard all.count > maxLines + maxLines / 5 else { return }
        try? (all.suffix(maxLines).joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }
}
