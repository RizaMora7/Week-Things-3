import AppKit

// The only file with top-level code (swiftc requires this in multi-file projects).
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
