import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut to toggle between 0° and preferred portrait angle (default: ⌃⌥⌘R).
    static let toggleDisplayRotation = Self(
        "toggleDisplayRotation",
        default: .init(.r, modifiers: [.control, .option, .command])
    )

    /// Optional global shortcut to cycle trackpad mode (Linked -> Independent -> Off).
    static let cycleTrackpadMode = Self("cycleTrackpadMode")
}
