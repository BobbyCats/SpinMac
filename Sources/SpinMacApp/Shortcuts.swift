import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut to toggle between 0° and preferred portrait angle (default: ⌥⇧S).
    static let toggleDisplayRotation = Self(
        "toggleDisplayRotation",
        default: .init(.s, modifiers: [.option, .shift])
    )

    /// Optional global shortcut to cycle trackpad mode (Linked -> Independent -> Off).
    static let cycleTrackpadMode = Self("cycleTrackpadMode")
}
