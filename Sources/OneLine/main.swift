import AppKit

if CommandLine.arguments.contains("--self-check") {
    exit(SelfCheck.run())
}

if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
   index + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index + 1]
    let sample = index + 2 < CommandLine.arguments.count ? CommandLine.arguments[index + 2] : "event"
    exit(MainActor.assumeIsolated { SnapshotRenderer.run(path: path, sample: sample) })
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
