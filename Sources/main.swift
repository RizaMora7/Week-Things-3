import AppKit

// Único archivo con código de nivel superior (swiftc lo exige en proyectos multi-archivo).
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
