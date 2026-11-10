import AppKit
import Carbon.HIToolbox

/// A recorded key combination: key code + modifiers + a pre-rendered label.
struct KeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags
    var display: String

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        return value
    }
}

enum KeyNames {
    static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    static func name(for keyCode: UInt32, characters: String?) -> String {
        switch Int(keyCode) {
        case 36: return "↩"
        case 76: return "⌤"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "↖"
        case 119: return "↘"
        case 116: return "⇞"
        case 121: return "⇟"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            if let characters, !characters.isEmpty {
                return characters.uppercased()
            }
            return "键码\(keyCode)"
        }
    }
}

enum ShortcutAction: String, CaseIterable {
    case capture
    case pinClipboard
    case colorPicker
    case toolMove
    case toolRect
    case toolEllipse
    case toolArrow
    case toolPen
    case toolHighlight
    case toolMosaic
    case toolText

    static var globals: [ShortcutAction] { [.capture, .pinClipboard, .colorPicker] }
    static var tools: [ShortcutAction] {
        [.toolMove, .toolRect, .toolEllipse, .toolArrow, .toolPen, .toolHighlight, .toolMosaic, .toolText]
    }

    var isGlobal: Bool { Self.globals.contains(self) }

    var title: String {
        switch self {
        case .capture: return "区域截图"
        case .pinClipboard: return "剪贴板贴图"
        case .colorPicker: return "取色器"
        case .toolMove: return "移动截图"
        case .toolRect: return "矩形"
        case .toolEllipse: return "椭圆"
        case .toolArrow: return "箭头"
        case .toolPen: return "画笔"
        case .toolHighlight: return "高亮"
        case .toolMosaic: return "马赛克"
        case .toolText: return "文字"
        }
    }

    var tool: Tool? {
        switch self {
        case .toolMove: return .move
        case .toolRect: return .rect
        case .toolEllipse: return .ellipse
        case .toolArrow: return .arrow
        case .toolPen: return .pen
        case .toolHighlight: return .highlight
        case .toolMosaic: return .mosaic
        case .toolText: return .text
        default: return nil
        }
    }

    var defaultCombo: KeyCombo {
        switch self {
        case .capture:
            return KeyCombo(keyCode: 0, modifiers: [.command, .shift], display: "⌘⇧A")
        case .pinClipboard:
            return KeyCombo(keyCode: 9, modifiers: [.control, .option], display: "⌃⌥V")
        case .colorPicker:
            return KeyCombo(keyCode: 8, modifiers: [.control, .option], display: "⌃⌥C")
        case .toolMove:
            return KeyCombo(keyCode: 9, modifiers: [], display: "V")
        case .toolRect:
            return KeyCombo(keyCode: 15, modifiers: [], display: "R")
        case .toolEllipse:
            return KeyCombo(keyCode: 31, modifiers: [], display: "O")
        case .toolArrow:
            return KeyCombo(keyCode: 0, modifiers: [], display: "A")
        case .toolPen:
            return KeyCombo(keyCode: 35, modifiers: [], display: "P")
        case .toolHighlight:
            return KeyCombo(keyCode: 4, modifiers: [], display: "H")
        case .toolMosaic:
            return KeyCombo(keyCode: 46, modifiers: [], display: "M")
        case .toolText:
            return KeyCombo(keyCode: 17, modifiers: [], display: "T")
        }
    }
}

extension Tool {
    var shortcutAction: ShortcutAction {
        switch self {
        case .move: return .toolMove
        case .rect: return .toolRect
        case .ellipse: return .toolEllipse
        case .arrow: return .toolArrow
        case .pen: return .toolPen
        case .highlight: return .toolHighlight
        case .mosaic: return .toolMosaic
        case .text: return .toolText
        }
    }
}

@MainActor
final class ShortcutStore {
    static let shared = ShortcutStore()
    private static let defaultsKey = "SnipPin.shortcuts"

    private var combos: [ShortcutAction: KeyCombo] = [:]

    private init() {
        load()
    }

    func combo(for action: ShortcutAction) -> KeyCombo? {
        combos[action]
    }

    func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        combos[action] = combo
        save()
        NotificationCenter.default.post(name: .snipPinShortcutsChanged, object: nil)
    }

    func reload() {
        load()
    }

    func resetToDefaults() {
        combos = [:]
        for action in ShortcutAction.allCases {
            combos[action] = action.defaultCombo
        }
        save()
        NotificationCenter.default.post(name: .snipPinShortcutsChanged, object: nil)
    }

    func tool(forKeyCode keyCode: UInt32) -> Tool? {
        for action in ShortcutAction.tools {
            guard let combo = combos[action], combo.modifiers.isEmpty, combo.keyCode == keyCode else { continue }
            return action.tool
        }
        return nil
    }

    func display(forTool tool: Tool) -> String? {
        combos[tool.shortcutAction]?.display
    }

    // MARK: - Persistence

    private func load() {
        combos = [:]
        for action in ShortcutAction.allCases {
            combos[action] = action.defaultCombo
        }
        guard let stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) else { return }
        for action in ShortcutAction.allCases {
            guard let entry = stored[action.rawValue] as? [String: Any] else { continue }
            if entry["cleared"] as? Bool == true {
                combos[action] = nil
                continue
            }
            guard
                let keyCode = entry["keyCode"] as? Int,
                let modifiers = entry["modifiers"] as? Int,
                let display = entry["display"] as? String
            else { continue }
            combos[action] = KeyCombo(
                keyCode: UInt32(keyCode),
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers)),
                display: display
            )
        }
    }

    private func save() {
        var stored: [String: Any] = [:]
        for action in ShortcutAction.allCases {
            if let combo = combos[action] {
                stored[action.rawValue] = [
                    "keyCode": Int(combo.keyCode),
                    "modifiers": Int(combo.modifiers.rawValue),
                    "display": combo.display
                ]
            } else {
                stored[action.rawValue] = ["cleared": true]
            }
        }
        UserDefaults.standard.set(stored, forKey: Self.defaultsKey)
    }
}

extension Notification.Name {
    static let snipPinShortcutsChanged = Notification.Name("SnipPin.shortcutsChanged")
}
