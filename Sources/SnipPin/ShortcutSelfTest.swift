import AppKit

/// Headless check of the shortcut store, persistence and hotkey registration.
@MainActor
enum ShortcutSelfTest {
    static func run() async -> Int32 {
        let store = ShortcutStore.shared
        var ok = true

        // Preserve whatever the user has configured and restore it afterwards.
        let backup = UserDefaults.standard.dictionary(forKey: "SnipPin.shortcuts")
        defer {
            if let backup {
                UserDefaults.standard.set(backup, forKey: "SnipPin.shortcuts")
            } else {
                UserDefaults.standard.removeObject(forKey: "SnipPin.shortcuts")
            }
            store.reload()
        }
        store.resetToDefaults()

        func check(_ condition: Bool, _ message: String) {
            print((condition ? "PASS  " : "FAIL  ") + message)
            if !condition { ok = false }
        }

        check(store.combo(for: .capture)?.display == "⌘⇧A", "default capture ⌘⇧A")
        check(store.combo(for: .pinClipboard)?.display == "⌃⌥V", "default clipboard pin ⌃⌥V")
        check(store.tool(forKeyCode: 15) == .rect, "default R selects rect")
        check(store.tool(forKeyCode: 49) == nil, "space is not a tool shortcut")

        store.set(KeyCombo(keyCode: 11, modifiers: [.command, .shift], display: "⌘⇧B"), for: .capture)
        check(store.combo(for: .capture)?.keyCode == 11, "custom capture stored")
        check(store.combo(for: .capture)?.display == "⌘⇧B", "custom capture display")
        let stored = UserDefaults.standard.dictionary(forKey: "SnipPin.shortcuts") as? [String: Any]
        check((stored?["capture"] as? [String: Any])?["keyCode"] as? Int == 11, "custom capture persisted")

        check(HotKeyManager.shared.register(11, [.command, .shift], {}), "RegisterEventHotKey ⌘⇧B")
        HotKeyManager.shared.unregisterAll()

        store.set(KeyCombo(keyCode: 1, modifiers: [], display: "S"), for: .toolRect)
        check(store.tool(forKeyCode: 1) == .rect, "rebound tool key selects rect")
        check(store.tool(forKeyCode: 15) == nil, "old tool key no longer maps")

        store.set(nil, for: .colorPicker)
        check(store.combo(for: .colorPicker) == nil, "cleared hotkey")

        store.resetToDefaults()
        check(store.combo(for: .capture)?.display == "⌘⇧A", "reset restores capture")
        check(store.combo(for: .colorPicker)?.display == "⌃⌥C", "reset restores color picker")
        check(store.tool(forKeyCode: 15) == .rect, "reset restores tool key")

        check(HotKeyManager.shared.register(0, [.command, .shift], {}), "default capture registers")
        HotKeyManager.shared.unregisterAll()

        print(ok ? "RESULT: PASS" : "RESULT: FAIL")
        return ok ? 0 : 2
    }
}
