import Foundation

/// An installed application that can be searched and launched.
public struct AppEntry: Hashable, Identifiable, Sendable {
    public let name: String
    public let bundleID: String?
    public let url: URL

    public var id: String { url.path }

    public init(name: String, bundleID: String?, url: URL) {
        self.name = name
        self.bundleID = bundleID
        self.url = url
    }
}
