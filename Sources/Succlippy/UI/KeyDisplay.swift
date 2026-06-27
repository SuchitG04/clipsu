import AppKit

/// Formats a (keyCode, NSEvent-modifier-flags) pair as a readable shortcut like "⌥C".
enum KeyDisplay {
    static func string(keyCode: Int, modifiers: Int) -> String {
        modifierString(modifiers) + keyString(keyCode)
    }

    static func modifierString(_ modifiers: Int) -> String {
        let flags = UInt(modifiers)
        var s = ""
        if flags & (1 << 18) != 0 { s += "⌃" } // control
        if flags & (1 << 19) != 0 { s += "⌥" } // option
        if flags & (1 << 17) != 0 { s += "⇧" } // shift
        if flags & (1 << 20) != 0 { s += "⌘" } // command
        return s
    }

    static func keyString(_ code: Int) -> String {
        if let named = special[code] { return named }
        return letters[code] ?? "Key \(code)"
    }

    private static let special: [Int: String] = [
        36: "↵", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6"
    ]

    private static let letters: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
        45: "N", 46: "M",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`"
    ]
}
