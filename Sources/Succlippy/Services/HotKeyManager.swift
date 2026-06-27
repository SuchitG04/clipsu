import AppKit
import Carbon.HIToolbox

/// Registers a single system-wide hotkey via Carbon (works without Accessibility permission).
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x53434C50 // 'SCLP'

    /// Invoked on the main thread when the hotkey fires.
    var onHotKey: (() -> Void)?

    init() {
        installHandler()
    }

    deinit {
        unregister()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// (Re)registers using NSEvent-style modifier flags + a virtual key code (as stored in settings).
    func register(keyCode: Int, nsModifiers: Int) {
        unregister()
        let carbonMods = Self.carbonModifiers(fromNSFlags: UInt(nsModifiers))
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(UInt32(keyCode), carbonMods, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            Log.error("RegisterEventHotKey failed: \(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if hkID.signature == manager.signature {
                DispatchQueue.main.async { manager.onHotKey?() }
            }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    /// Converts NSEvent modifier flag bits to Carbon modifier bits.
    static func carbonModifiers(fromNSFlags flags: UInt) -> UInt32 {
        var carbon: UInt32 = 0
        let cmd: UInt = 1 << 20, shift: UInt = 1 << 17, option: UInt = 1 << 19, control: UInt = 1 << 18
        if flags & cmd != 0 { carbon |= UInt32(cmdKey) }
        if flags & shift != 0 { carbon |= UInt32(shiftKey) }
        if flags & option != 0 { carbon |= UInt32(optionKey) }
        if flags & control != 0 { carbon |= UInt32(controlKey) }
        return carbon
    }
}
