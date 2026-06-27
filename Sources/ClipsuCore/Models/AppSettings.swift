import Foundation
import Combine

public enum PanelPosition: String, CaseIterable, Sendable {
    case center
    case cursor
    case remembered

    public var title: String {
        switch self {
        case .center:     return "Center of screen"
        case .cursor:     return "Near cursor"
        case .remembered: return "Remember last position"
        }
    }
}

public enum EnterBehavior: String, CaseIterable, Sendable {
    case alwaysPaste
    case smart

    public var title: String {
        switch self {
        case .alwaysPaste: return "Always paste"
        case .smart:       return "Smart (paste text, open images)"
        }
    }
}

public enum RetentionMode: String, CaseIterable, Sendable {
    case keepAll
    case days
    case count

    public var title: String {
        switch self {
        case .keepAll: return "Keep everything"
        case .days:    return "Keep last N days"
        case .count:   return "Keep last N items"
        }
    }
}

public enum DedupScope: String, CaseIterable, Sendable {
    case lastOnly
    case all

    public var title: String {
        switch self {
        case .lastOnly: return "Only the most recent item"
        case .all:      return "Entire history"
        }
    }
}

/// User-facing preferences, persisted to `UserDefaults`. Observable for SwiftUI.
public final class AppSettings: ObservableObject, @unchecked Sendable {
    private let defaults: UserDefaults

    public static let shared = AppSettings()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Hotkey default: ⌥C  (Option + C). keyCode 8 == 'c' on the ANSI layout.
        self.hotKeyCode = defaults.object(forKey: K.hotKeyCode) as? Int ?? 8
        self.hotKeyModifiers = defaults.object(forKey: K.hotKeyModifiers) as? Int ?? Int(NSEventModifierFlagOption)

        self.panelPosition = PanelPosition(rawValue: defaults.string(forKey: K.panelPosition) ?? "") ?? .center
        self.enterBehavior = EnterBehavior(rawValue: defaults.string(forKey: K.enterBehavior) ?? "") ?? .alwaysPaste

        self.retentionMode = RetentionMode(rawValue: defaults.string(forKey: K.retentionMode) ?? "") ?? .count
        self.retentionCount = defaults.object(forKey: K.retentionCount) as? Int ?? 1000
        self.retentionDays = defaults.object(forKey: K.retentionDays) as? Int ?? 90

        self.maxItemBytes = defaults.object(forKey: K.maxItemBytes) as? Int ?? (50 * 1024 * 1024)
        self.dedupScope = DedupScope(rawValue: defaults.string(forKey: K.dedupScope) ?? "") ?? .all

        self.ocrEnabled = defaults.object(forKey: K.ocrEnabled) as? Bool ?? true
        self.ocrSkipBytes = defaults.object(forKey: K.ocrSkipBytes) as? Int ?? (8 * 1024 * 1024)

        self.ignoreConcealed = defaults.object(forKey: K.ignoreConcealed) as? Bool ?? true
        self.excludedBundleIDs = defaults.stringArray(forKey: K.excludedBundleIDs) ?? []

        self.launchAtLogin = defaults.object(forKey: K.launchAtLogin) as? Bool ?? false
        self.paused = defaults.object(forKey: K.paused) as? Bool ?? false
        self.vimEnabled = defaults.object(forKey: K.vimEnabled) as? Bool ?? false
    }

    // The hotkey is published as a pair so the recorder/manager can react together.
    @Published public var hotKeyCode: Int { didSet { defaults.set(hotKeyCode, forKey: K.hotKeyCode) } }
    @Published public var hotKeyModifiers: Int { didSet { defaults.set(hotKeyModifiers, forKey: K.hotKeyModifiers) } }

    @Published public var panelPosition: PanelPosition { didSet { defaults.set(panelPosition.rawValue, forKey: K.panelPosition) } }
    @Published public var enterBehavior: EnterBehavior { didSet { defaults.set(enterBehavior.rawValue, forKey: K.enterBehavior) } }

    @Published public var retentionMode: RetentionMode { didSet { defaults.set(retentionMode.rawValue, forKey: K.retentionMode) } }
    @Published public var retentionCount: Int { didSet { defaults.set(retentionCount, forKey: K.retentionCount) } }
    @Published public var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: K.retentionDays) } }

    @Published public var maxItemBytes: Int { didSet { defaults.set(maxItemBytes, forKey: K.maxItemBytes) } }
    @Published public var dedupScope: DedupScope { didSet { defaults.set(dedupScope.rawValue, forKey: K.dedupScope) } }

    @Published public var ocrEnabled: Bool { didSet { defaults.set(ocrEnabled, forKey: K.ocrEnabled) } }
    @Published public var ocrSkipBytes: Int { didSet { defaults.set(ocrSkipBytes, forKey: K.ocrSkipBytes) } }

    @Published public var ignoreConcealed: Bool { didSet { defaults.set(ignoreConcealed, forKey: K.ignoreConcealed) } }
    @Published public var excludedBundleIDs: [String] { didSet { defaults.set(excludedBundleIDs, forKey: K.excludedBundleIDs) } }

    @Published public var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: K.launchAtLogin) } }
    @Published public var paused: Bool { didSet { defaults.set(paused, forKey: K.paused) } }
    @Published public var vimEnabled: Bool { didSet { defaults.set(vimEnabled, forKey: K.vimEnabled) } }

    private enum K {
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let panelPosition = "panelPosition"
        static let enterBehavior = "enterBehavior"
        static let retentionMode = "retentionMode"
        static let retentionCount = "retentionCount"
        static let retentionDays = "retentionDays"
        static let maxItemBytes = "maxItemBytes"
        static let dedupScope = "dedupScope"
        static let ocrEnabled = "ocrEnabled"
        static let ocrSkipBytes = "ocrSkipBytes"
        static let ignoreConcealed = "ignoreConcealed"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let launchAtLogin = "launchAtLogin"
        static let paused = "paused"
        static let vimEnabled = "vimEnabled"
    }
}

// Mirror of NSEvent.ModifierFlags.option.rawValue, kept here so Core has no AppKit dependency.
private let NSEventModifierFlagOption: UInt = 1 << 19
