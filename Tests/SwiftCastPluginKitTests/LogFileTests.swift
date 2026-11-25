import Foundation
import Testing
@testable import SwiftCastPluginKit

struct LogFileTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "SwiftCastLogTests-\(UUID().uuidString)")

    private func makeLog(maxFileSize: Int = 200, maxArchives: Int = 2) -> LogFile {
        let log = LogFile(directory: directory, maxFileSize: maxFileSize, maxArchives: maxArchives)
        log.start()
        return log
    }

    private func contents(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    @Test func writesLinesWithLevelAndCategory() throws {
        let log = makeLog()
        log.write(.info, "hello", category: "test")
        log.write(.error, "broke", category: "db")
        log.flush()
        let lines = try #require(contents(log.currentURL)).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("INFO  [test] hello"))
        #expect(lines[1].hasSuffix("ERROR [db] broke"))
    }

    @Test func writesNothingBeforeStart() {
        let log = LogFile(directory: directory)
        log.write(.info, "early", category: "test")
        log.flush()
        #expect(!FileManager.default.fileExists(atPath: log.currentURL.path))
    }

    @Test func rollsOverPastTheSizeLimit() throws {
        let log = makeLog()
        log.write(.info, "first " + String(repeating: "a", count: 120), category: "test")
        log.write(.info, "second " + String(repeating: "b", count: 120), category: "test")
        log.flush()
        #expect(try #require(contents(log.archiveURL(1))).contains("first"))
        let current = try #require(contents(log.currentURL))
        #expect(current.contains("second"))
        #expect(!current.contains("first"))
    }

    @Test func keepsOnlyMaxArchives() throws {
        let log = makeLog(maxArchives: 2)
        for index in 1...5 {
            log.write(.info, "line\(index) " + String(repeating: "x", count: 150), category: "test")
        }
        log.flush()
        #expect(try #require(contents(log.currentURL)).contains("line5"))
        #expect(try #require(contents(log.archiveURL(1))).contains("line4"))
        #expect(try #require(contents(log.archiveURL(2))).contains("line3"))
        #expect(!FileManager.default.fileExists(atPath: log.archiveURL(3).path))
    }

    @Test func rollsOverAFileLeftFullByAnEarlierRun() throws {
        let earlier = makeLog()
        earlier.write(.info, "earlier " + String(repeating: "a", count: 150), category: "test")
        earlier.flush()

        let log = makeLog()
        log.write(.info, "later " + String(repeating: "b", count: 150), category: "test")
        log.flush()
        #expect(try #require(contents(log.archiveURL(1))).contains("earlier"))
        #expect(!(try #require(contents(log.currentURL))).contains("earlier"))
    }
}
