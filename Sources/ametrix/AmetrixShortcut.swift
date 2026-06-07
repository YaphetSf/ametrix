import Carbon

struct AmetrixShortcut {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String
    let modifierLabels: [String]
    let modifierSymbols: [String]

    var displayLabel: String {
        (modifierLabels + [keyLabel]).joined(separator: " + ")
    }

    var symbolicLabel: String {
        (modifierSymbols + [keyLabel]).joined(separator: "  ")
    }

    var logLabel: String {
        (modifierLabels + [keyLabel]).joined(separator: "-")
    }
}

enum AmetrixShortcuts {
    static let lock = AmetrixShortcut(
        keyCode: UInt32(kVK_ANSI_Z),
        modifiers: UInt32(controlKey | cmdKey),
        keyLabel: "Z",
        modifierLabels: ["Control", "Command"],
        modifierSymbols: ["⌃", "⌘"]
    )
}
