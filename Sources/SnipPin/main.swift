import AppKit

// Debug aid: record how the app was launched (used by the automated smoke tests).
if CommandLine.arguments.count > 1 {
    let line = CommandLine.arguments.dropFirst().joined(separator: " ")
    try? line.write(toFile: "/tmp/snippin-argv.log", atomically: true, encoding: .utf8)
}

// Top-level code runs on the main thread; AppKit setup is main-actor isolated.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
