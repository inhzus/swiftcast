import Foundation
import os

/// The app's info and error log. Each line goes to the unified log (`log stream --predicate
/// 'subsystem == "io.zunish.swiftcast"'`) and, once the app calls `Log.file.start()`, to a
/// rolling file under Application Support (see `LogFile`).
///
/// Log events, not keystrokes: launches, plugins activating, indexes rebuilt, failures. Never
/// log what the user types or copies, or the contents of their files; names, paths, counts and
/// durations are fine.
public enum Log {
    /// `<Database.directory>/Logs/swiftcast.log`, rolled at 1 MB with three older files kept.
    public static let file = LogFile(directory: Database.directory.appending(path: "Logs"))

    public static func info(_ message: String, category: String) {
        logger(category).info("\(message, privacy: .public)")
        file.write(.info, message, category: category)
    }

    public static func error(_ message: String, category: String) {
        logger(category).error("\(message, privacy: .public)")
        file.write(.error, message, category: category)
    }

    /// Whole milliseconds from `start` to now, for lines like "indexed 214 apps in 85 ms".
    public static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = start.duration(to: .now).components
        return Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
    }

    static let subsystem = Bundle.main.bundleIdentifier ?? "io.zunish.swiftcast"

    private static let loggers = OSAllocatedUnfairLock(initialState: [String: Logger]())

    private static func logger(_ category: String) -> Logger {
        loggers.withLock { loggers in
            if let logger = loggers[category] { return logger }
            let logger = Logger(subsystem: subsystem, category: category)
            loggers[category] = logger
            return logger
        }
    }
}

/// A log file that rolls over: when a line would take `<name>.log` past `maxFileSize`, it
/// becomes `<name>.1.log`, the older ones move up a number, and the one past `maxArchives` is
/// deleted. So the log never takes more than about `maxFileSize × (maxArchives + 1)`.
///
/// Writes happen in order on a background queue, so callers never wait on the disk. Nothing is
/// written until `start()`, which keeps tests and tools that use the plugin kit from writing
/// to the user's log.
public final class LogFile: @unchecked Sendable {
    public enum Level: String, Sendable {
        case info = "INFO "
        case error = "ERROR"
    }

    /// The file being written, `<directory>/<name>.log`.
    public let currentURL: URL
    public let directory: URL
    private let name: String
    private let maxFileSize: Int
    private let maxArchives: Int
    private let queue = DispatchQueue(label: "io.zunish.swiftcast.log", qos: .utility)

    // Touched only on `queue`.
    private var isStarted = false
    private var handle: FileHandle?
    private var size = 0
    private var reportedFailure = false
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
        return formatter
    }()

    public init(directory: URL, name: String = "swiftcast", maxFileSize: Int = 1 << 20, maxArchives: Int = 3) {
        self.directory = directory
        self.name = name
        self.maxFileSize = maxFileSize
        self.maxArchives = maxArchives
        currentURL = directory.appending(path: "\(name).log")
    }

    deinit {
        try? handle?.close()
    }

    /// Starts writing lines to disk; ones logged before are only in the unified log.
    public func start() {
        queue.async { self.isStarted = true }
    }

    public func write(_ level: Level, _ message: String, category: String, at date: Date = Date()) {
        queue.async {
            guard self.isStarted else { return }
            let line = "\(self.formatter.string(from: date)) \(level.rawValue) [\(category)] \(message)\n"
            self.append(Data(line.utf8))
        }
    }

    /// Waits for the lines logged so far to reach the file.
    public func flush() {
        queue.sync {}
    }

    /// `<name>.<index>.log`, the `index`th newest archive.
    public func archiveURL(_ index: Int) -> URL {
        directory.appending(path: "\(name).\(index).log")
    }

    private func append(_ data: Data) {
        do {
            if handle == nil { try open() }
            if size > 0, size + data.count > maxFileSize {
                try rotate()
                try open()
            }
            try handle?.write(contentsOf: data)
            size += data.count
        } catch {
            try? handle?.close()
            handle = nil
            // Report once, to the unified log only: logging this to the file would fail again.
            guard !reportedFailure else { return }
            reportedFailure = true
            Logger(subsystem: Log.subsystem, category: "log")
                .error("can't write \(self.currentURL.path, privacy: .public): \(error, privacy: .public)")
        }
    }

    private func open() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: currentURL.path) {
            fm.createFile(atPath: currentURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: currentURL)
        size = Int(try handle.seekToEnd())
        self.handle = handle
    }

    private func rotate() throws {
        try handle?.close()
        handle = nil
        let fm = FileManager.default
        try? fm.removeItem(at: archiveURL(maxArchives))
        if maxArchives > 1 {
            for index in stride(from: maxArchives - 1, through: 1, by: -1) where fm.fileExists(atPath: archiveURL(index).path) {
                try fm.moveItem(at: archiveURL(index), to: archiveURL(index + 1))
            }
        }
        if maxArchives > 0 {
            try fm.moveItem(at: currentURL, to: archiveURL(1))
        } else {
            try fm.removeItem(at: currentURL)
        }
    }
}
