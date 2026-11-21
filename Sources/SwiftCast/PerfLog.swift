import AppKit
import QuartzCore

/// Opt-in latency log (`SWIFTCAST_PERF=1`), written to stderr.
///
/// For each key press and hotkey, it records, relative to the event's own timestamp
/// (the moment the input happened):
/// - `queue`: until the app starts handling the event
/// - `work`: handling, through the end of that run-loop pass's Core Animation commit,
///   when the frame is handed to the window server
/// - `total`: input → commit
@MainActor
enum PerfLog {
    static let isEnabled = ProcessInfo.processInfo.environment["SWIFTCAST_PERF"] != nil

    private struct Pending {
        let label: String
        let eventTime: TimeInterval
        let dispatchTime: TimeInterval
    }

    private static var pending: [Pending] = []
    /// Named phase durations within the current run-loop pass, printed with its events.
    private static var phases: [(String, TimeInterval)] = []
    private static var observer: CFRunLoopObserver?
    private static var preCommitObserver: CFRunLoopObserver?
    /// When the current pass reached Core Animation's commit, splitting `work` into
    /// `handle` (event handling) and `commit` (layout, drawing, commit).
    private static var preCommitTime: TimeInterval?

    static func start() {
        guard isEnabled, observer == nil else { return }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let chars = event.charactersIgnoringModifiers ?? "?"
            mark("key \(chars.unicodeScalars.map { $0.value < 32 || $0.value == 127 ? "\\u{\(String($0.value, radix: 16))}" : String($0) }.joined())",
                 eventTime: event.timestamp)
            return event
        }
        // Runs just before Core Animation's own before-waiting commit observer (order 2_000_000).
        preCommitObserver = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 1_999_999) { _, _ in
            MainActor.assumeIsolated {
                if !pending.isEmpty { preCommitTime = ProcessInfo.processInfo.systemUptime }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), preCommitObserver, .commonModes)
        // Runs after Core Animation's own before-waiting commit observer (order 2_000_000).
        observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, Int.max) { _, _ in
            MainActor.assumeIsolated { flush() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// Times `body` as a named phase of the current run-loop pass.
    static func measure<T>(_ name: String, _ body: () -> T) -> T {
        guard isEnabled else { return body() }
        let start = ProcessInfo.processInfo.systemUptime
        defer { phases.append((name, ProcessInfo.processInfo.systemUptime - start)) }
        return body()
    }

    /// Records an input event to report once its frame is committed.
    static func mark(_ label: String, eventTime: TimeInterval) {
        guard isEnabled else { return }
        pending.append(Pending(label: label, eventTime: eventTime, dispatchTime: ProcessInfo.processInfo.systemUptime))
    }

    private static func flush() {
        guard !pending.isEmpty else {
            phases.removeAll()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        var detail = phases.map { String(format: " %@=%.2fms", $0.0, $0.1 * 1000) }.joined()
        if let preCommitTime, let first = pending.first {
            detail = String(format: " handle=%.2fms commit=%.2fms", (preCommitTime - first.dispatchTime) * 1000, (now - preCommitTime) * 1000) + detail
        }
        preCommitTime = nil
        for p in pending {
            let line = String(
                format: "perf %@ queue=%.2fms work=%.2fms total=%.2fms%@\n",
                p.label,
                (p.dispatchTime - p.eventTime) * 1000,
                (now - p.dispatchTime) * 1000,
                (now - p.eventTime) * 1000,
                detail
            )
            FileHandle.standardError.write(Data(line.utf8))
        }
        pending.removeAll()
        phases.removeAll()
    }
}
