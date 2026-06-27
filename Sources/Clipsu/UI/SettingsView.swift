import SwiftUI
import AppKit
import ClipsuCore

/// The preferences window, organised into tabs.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var appState: AppState
    var onHotKeyChange: () -> Void

    var body: some View {
        TabView {
            GeneralTab(settings: settings).tabItem { Label("General", systemImage: "gearshape") }
            ShortcutTab(settings: settings, onHotKeyChange: onHotKeyChange)
                .tabItem { Label("Shortcut", systemImage: "command") }
            HistoryTab(settings: settings).tabItem { Label("History", systemImage: "clock") }
            PrivacyTab(settings: settings).tabItem { Label("Privacy", systemImage: "hand.raised") }
            OCRTab(settings: settings).tabItem { Label("Images", systemImage: "photo") }
            DataTab(appState: appState).tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 460, height: 340)
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings

    var launchBinding: Binding<Bool> {
        Binding(get: { settings.launchAtLogin }, set: { on in
            settings.launchAtLogin = on
            LoginItem.setEnabled(on)
        })
    }

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: launchBinding)
            Toggle("Pause capturing", isOn: $settings.paused)
            Picker("Panel position", selection: $settings.panelPosition) {
                ForEach(PanelPosition.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("When pressing Return", selection: $settings.enterBehavior) {
                ForEach(EnterBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct ShortcutTab: View {
    @ObservedObject var settings: AppSettings
    var onHotKeyChange: () -> Void

    var body: some View {
        Form {
            HStack {
                Text("Open Clipsu")
                Spacer()
                HotKeyRecorderView(
                    keyCode: $settings.hotKeyCode,
                    modifiers: $settings.hotKeyModifiers,
                    onChange: onHotKeyChange
                )
                .frame(width: 140, height: 26)
            }
            Text("Click the field and press your shortcut. Tip: ⌥C is the “ç” character — if you ever need to type it, switch to something like ⌥⌘C.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct HistoryTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("Keep", selection: $settings.retentionMode) {
                ForEach(RetentionMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if settings.retentionMode == .count {
                Stepper("Max items: \(settings.retentionCount)",
                        value: $settings.retentionCount, in: 50...100_000, step: 50)
            }
            if settings.retentionMode == .days {
                Stepper("Days: \(settings.retentionDays)",
                        value: $settings.retentionDays, in: 1...3650, step: 1)
            }
            Picker("De-duplicate against", selection: $settings.dedupScope) {
                ForEach(DedupScope.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("Pinned items are always kept, regardless of these limits.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct PrivacyTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Ignore passwords & transient content", isOn: $settings.ignoreConcealed)
            Section("Excluded apps") {
                if settings.excludedBundleIDs.isEmpty {
                    Text("No excluded apps").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(settings.excludedBundleIDs, id: \.self) { bid in
                        HStack {
                            Text(appName(for: bid)).font(.system(size: 12))
                            Spacer()
                            Button(role: .destructive) {
                                settings.excludedBundleIDs.removeAll { $0 == bid }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("Add App…", action: addApp)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier,
           !settings.excludedBundleIDs.contains(bid) {
            settings.excludedBundleIDs.append(bid)
        }
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }
}

private struct OCRTab: View {
    @ObservedObject var settings: AppSettings
    private let mb = 1024 * 1024

    var body: some View {
        Form {
            Toggle("Recognize text in images (OCR)", isOn: $settings.ocrEnabled)
            Stepper("Skip OCR above \(settings.ocrSkipBytes / mb) MB",
                    value: $settings.ocrSkipBytes, in: mb...(64 * mb), step: mb)
                .disabled(!settings.ocrEnabled)
            Text("OCR runs fully on-device and makes image contents searchable.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct DataTab: View {
    @ObservedObject var appState: AppState
    @State private var itemCount = 0
    @State private var dbSize = 0
    @State private var showClearConfirm = false

    var body: some View {
        Form {
            LabeledContent("Items", value: "\(itemCount)")
            LabeledContent("Database size", value: dbSize.clipBytes)
            Button("Reveal Data Folder in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory])
            }
            Button("Clear All History…", role: .destructive) { showClearConfirm = true }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear(perform: refresh)
        .confirmationDialog("Delete all clipboard history?",
                            isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) {
                appState.clearAll(); refresh()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func refresh() {
        itemCount = (try? appState.database.count()) ?? 0
        dbSize = (try? FileManager.default.attributesOfItem(atPath: AppPaths.databaseURL.path))?[.size] as? Int ?? 0
    }
}
