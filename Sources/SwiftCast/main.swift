import AppKit
import SwiftCastPluginKit

// Before `AppDelegate`, so opening the databases is logged too.
Log.file.start()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
