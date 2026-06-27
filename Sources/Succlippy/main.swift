import AppKit

// Menu bar agent: no Dock icon. Program start is already on the main thread, so we can
// assert main-actor isolation to construct the AppKit objects.
let delegate = MainActor.assumeIsolated { AppDelegate() }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.delegate = delegate                 // NSApplication.delegate is weak; the global keeps it alive.
    app.setActivationPolicy(.accessory)
    app.run()
}
