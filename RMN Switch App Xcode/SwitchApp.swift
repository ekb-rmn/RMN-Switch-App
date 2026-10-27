import AppKit
import SwiftUI
import Carbon
import ApplicationServices
import ServiceManagement

enum LaunchAtLogin {
    enum State { case disabled, enabled, requiresApproval }
    static let label = "ru.rmn.LangSwitch.login"
    static var legacyURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func configuration(appURL: URL) -> [String: Any] {
        ["Label": label, "ProgramArguments": ["/usr/bin/open", "-g", appURL.path],
         "RunAtLoad": true, "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive"]
    }

    static func setLegacyEnabled(_ enabled: Bool, appURL: URL, fileURL: URL) throws {
        if enabled {
            let data = try PropertyListSerialization.data(fromPropertyList: configuration(appURL: appURL), format: .xml, options: 0)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    static var state: State {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return .enabled
            case .requiresApproval: return .requiresApproval
            default: break
            }
        }
        return FileManager.default.fileExists(atPath: legacyURL.path) ? .enabled : .disabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
            // Remove our Monterey entry when the user changes the modern setting.
            try setLegacyEnabled(false, appURL: Bundle.main.bundleURL, fileURL: legacyURL)
        } else {
            try setLegacyEnabled(enabled, appURL: Bundle.main.bundleURL, fileURL: legacyURL)
        }
    }

    static func openSettings() {
        if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems() }
        else { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.users?startupItemsPref")!) }
    }
}

final class SwitchMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class SwitchMenuButton: NSButton {
    private var hovered = false
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
        hovered = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && (hovered || isHighlighted) {
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 11, yRadius: 11).fill()
        }
        cell?.draw(withFrame: bounds.insetBy(dx: 7, dy: 0), in: self)
    }
}

enum Operation: String { case layout, letterCase }

enum IndicatorStyle: String, CaseIterable {
    case letters, flags

    static func load(from defaults: UserDefaults = .standard) -> IndicatorStyle {
        IndicatorStyle(rawValue: defaults.string(forKey: "indicatorStyle") ?? "") ?? .letters
    }
}

enum FlatFlag {
    static func draw(_ flag: String, in rect: NSRect) -> Bool {
        func fill(_ color: NSColor, _ area: NSRect) {
            color.setFill()
            area.fill()
        }
        let red = NSColor(srgbRed: 0.80, green: 0.05, blue: 0.16, alpha: 1)
        let blue = NSColor(srgbRed: 0.0, green: 0.22, blue: 0.57, alpha: 1)
        switch flag {
        case "🇷🇺":
            let height = rect.height / 3
            fill(red, rect)
            fill(blue, NSRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: height))
            fill(.white, NSRect(x: rect.minX, y: rect.minY + height * 2, width: rect.width, height: height))
        case "🇺🇸":
            let stripe = rect.height / 13
            fill(.white, rect)
            for row in stride(from: 0, to: 13, by: 2) {
                fill(red, NSRect(x: rect.minX, y: rect.maxY - CGFloat(row + 1) * stripe, width: rect.width, height: stripe))
            }
            let canton = NSRect(x: rect.minX, y: rect.maxY - stripe * 7, width: rect.width * 0.4, height: stripe * 7)
            fill(blue, canton)
            NSColor.white.setFill()
            for row in 0..<9 {
                let count = row.isMultiple(of: 2) ? 6 : 5
                for column in 0..<count {
                    let center = NSPoint(x: canton.minX + canton.width * CGFloat(column * 2 + (count == 6 ? 1 : 2)) / 12,
                                         y: canton.maxY - canton.height * CGFloat(row + 1) / 10)
                    let star = NSBezierPath()
                    for point in 0..<10 {
                        let angle = CGFloat.pi / 2 + CGFloat(point) * CGFloat.pi / 5
                        let radius = canton.width / 18 * (point.isMultiple(of: 2) ? 1 : 0.4)
                        let vertex = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                        if point == 0 { star.move(to: vertex) } else { star.line(to: vertex) }
                    }
                    star.close()
                    star.fill()
                }
            }
        case "🇬🇧":
            fill(blue, rect)
            func diagonals(_ color: NSColor, width: CGFloat) {
                color.setStroke()
                let lines = NSBezierPath()
                lines.move(to: NSPoint(x: rect.minX, y: rect.minY))
                lines.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
                lines.move(to: NSPoint(x: rect.minX, y: rect.maxY))
                lines.line(to: NSPoint(x: rect.maxX, y: rect.minY))
                lines.lineWidth = width
                lines.stroke()
            }
            diagonals(.white, width: rect.height / 4)
            diagonals(red, width: rect.height / 10)
            for (color, thickness) in [(NSColor.white, CGFloat(0.32)), (red, CGFloat(0.18))] {
                fill(color, NSRect(x: rect.midX - rect.height * thickness / 2, y: rect.minY, width: rect.height * thickness, height: rect.height))
                fill(color, NSRect(x: rect.minX, y: rect.midY - rect.height * thickness / 2, width: rect.width, height: rect.height * thickness))
            }
        default:
            return false
        }
        return true
    }
}

enum KeyboardSources {
    static func currentFlag() -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let identifier = TISGetInputSourceProperty(source, kTISPropertyInputSourceID).map {
            Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String
        } ?? ""
        if currentLabel() == "EN" {
            return identifier.localizedCaseInsensitiveContains("British") ? "🇬🇧" : "🇺🇸"
        }
        return ["RU": "🇷🇺", "UK": "🇺🇦", "BE": "🇧🇾", "KK": "🇰🇿",
                "DE": "🇩🇪", "FR": "🇫🇷", "ES": "🇪🇸", "IT": "🇮🇹",
                "PT": "🇵🇹", "PL": "🇵🇱", "CS": "🇨🇿", "TR": "🇹🇷",
                "ZH": "🇨🇳", "JA": "🇯🇵", "KO": "🇰🇷", "HE": "🇮🇱",
                "EL": "🇬🇷", "FI": "🇫🇮", "SV": "🇸🇪", "HY": "🇦🇲",
                "KA": "🇬🇪", "UZ": "🇺🇿"][currentLabel()]
    }

    static func currentLabel() -> String {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return "—" }
        let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as! [String]
        guard let language = languages.first else { return "—" }
        return language.split(separator: "-").first.map { $0.uppercased() } ?? "—"
    }
    static func source(_ language: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceIsSelectCapable: true, kTISPropertyInputSourceIsEnabled: true] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
        return sources.first { source in
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
                  TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil else { return false }
            let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as! [String]
            return languages.contains(language)
        }
    }
    static func character(_ source: TISInputSource, key: UInt16, shifted: Bool) -> Character? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var count = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), shifted ? 2 : 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKey, buffer.count, &count, &buffer)
        guard status == noErr, count > 0 else { return nil }
        let string = String(utf16CodeUnits: buffer, count: count)
        guard string.count == 1, let character = string.first, !character.isWhitespace,
              !character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return character
    }
}

enum TextChange {
    // Standard English and Russian keyboard positions, including Shift symbols.
    static let english = Array("`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?")
    static let russian = Array("ё1234567890-=йцукенгшщзхъ\\фывапролджэячсмитьбю.Ё!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЪ/ФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,")
    static var nativeToRussian: [Character: Character]?
    static var nativeToEnglish: [Character: Character]?

    static func configure() {
        guard let en = KeyboardSources.source("en"), let ru = KeyboardSources.source("ru") else { return }
        var forward: [Character: Character] = [:]
        var reverse: [Character: Character] = [:]
        for key in UInt16(0)...UInt16(50) {
            for shifted in [false, true] {
                if let e = KeyboardSources.character(en, key: key, shifted: shifted), let r = KeyboardSources.character(ru, key: key, shifted: shifted) {
                    forward[e] = r; reverse[r] = e
                }
            }
        }
        if forward.count >= 60 { nativeToRussian = forward; nativeToEnglish = reverse }
    }

    static func apply(_ text: String, _ operation: Operation) -> String {
        if operation == .letterCase {
            let letters = text.filter { $0.isLetter }
            return !letters.isEmpty && letters == letters.uppercased() ? text.lowercased() : text.uppercased()
        }
        let forward = nativeToRussian ?? Dictionary(zip(english, russian), uniquingKeysWith: { first, _ in first })
        let reverse = nativeToEnglish ?? Dictionary(zip(russian, english), uniquingKeysWith: { first, _ in first })
        func isRussian(_ character: Character) -> Bool {
            character.unicodeScalars.contains { (0x0410...0x044F).contains($0.value) || $0.value == 0x0401 || $0.value == 0x0451 }
        }
        // Letters determine their own direction. Symbols follow the surrounding
        // word; standalone punctuation keeps the selection's overall direction.
        let defaultToEnglish = text.contains(where: isRussian)
        var result = ""
        var token = ""
        func convertToken() {
            guard !token.isEmpty else { return }
            let toEnglish = token.first(where: { isRussian($0) || ($0.isASCII && $0.isLetter) }).map(isRussian) ?? defaultToEnglish
            for character in token {
                let mapping = isRussian(character) ? reverse : character.isASCII && character.isLetter ? forward : toEnglish ? reverse : forward
                result.append(mapping[character] ?? character)
            }
            token = ""
        }
        for character in text {
            if character.isWhitespace { convertToken(); result.append(character) }
            else { token.append(character) }
        }
        convertToken()
        return result
    }
}

struct Shortcut: Codable, Equatable {
    let key: UInt16? // nil means a modifier tapped alone
    let modifiers: UInt64
    static let mask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
    static let layout = Shortcut(key: nil, modifiers: CGEventFlags.maskShift.rawValue)
    static let letterCase = Shortcut(key: 50, modifiers: CGEventFlags.maskShift.rawValue)

    var title: String {
        let flags = CGEventFlags(rawValue: modifiers)
        var name = ""
        if flags.contains(.maskControl) { name += "⌃" }
        if flags.contains(.maskAlternate) { name += "⌥" }
        if flags.contains(.maskShift) { name += "⇧" }
        if flags.contains(.maskCommand) { name += "⌘" }
        guard let key else { return name }
        let names: [UInt16: String] = [36: "Return", 48: "Tab", 49: "Space", 50: "` / ~", 51: "⌫", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        let letters: [UInt16: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:"."]
        return name + (names[key] ?? letters[key] ?? "Key \(key)")
    }
}

struct ModifierTap {
    var candidate: UInt64 = 0
    var started: TimeInterval = 0
    var active = false
    var eligible = false
    mutating func cancel() { eligible = false }
    mutating func update(_ flags: UInt64, now: TimeInterval) -> UInt64? {
        if flags == 0 {
            defer { active = false; eligible = false; candidate = 0 }
            return eligible && candidate != 0 && now - started < 0.8 ? candidate : nil
        }
        if !active { started = now; candidate = 0; active = true; eligible = true }
        candidate |= flags
        return nil
    }
}

final class SwitchApp: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let marker: Int64 = 0x524D4E4C
    private let verifyingRecovery = CommandLine.arguments.contains("--verify-recovery")
    private var statusItem: NSStatusItem!
    private var menuPanel: NSPanel?
    private var panelMonitor: Any?
    private var powerSwitch: NSSwitch?
    private var showSourceName = UserDefaults.standard.bool(forKey: "showSourceName")
    private var displayedLanguage = ""
    private var indicatorStyle = IndicatorStyle.load()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var word = ""
    private var modifierTap = ModifierTap()
    private var consumedKeys = Set<UInt16>()
    private var busy = false
    private var interrupted = false
    private var enabled = !UserDefaults.standard.bool(forKey: "paused")
    private var layoutShortcut = Shortcut.layout
    private var caseShortcut = Shortcut.letterCase
    private var window: NSWindow?
    private var settingsStack: NSStackView?
    private var settingsPageHeight: NSLayoutConstraint?
    private var settingsTabs: NSTabView?
    private var settingsTabPicker: NSSegmentedControl?
    private var layoutButton: NSButton?
    private var caseButton: NSButton?
    private var permissionStatus: NSTextField?
    private var permissionSettingsButton: NSButton?
    private var loginCheckbox: NSButton?
    private var loginStatus: NSTextField?
    private var loginApprovalButton: NSButton?
    private var setupStarted = false
    private var loginPromptScheduled = false
    private var loginPromptVisible = false
    private var recording: Operation?
    private var localMonitor: Any?
    private var recordingTap = ModifierTap()
    private let inputMenuDomain = "com.apple.TextInputMenu" as CFString
    private let inputMenuRestoreKey = "systemInputMenuVisibleBeforeSwitch"

    func applicationDidFinishLaunching(_ notification: Notification) {
        TextChange.configure()
        for (key, operation) in [("layoutShortcut", Operation.layout), ("caseShortcut", Operation.letterCase)] {
            if let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode(Shortcut.self, from: data) {
                if operation == .layout { layoutShortcut = value } else { caseShortcut = value }
            }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateInputSource()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(updateInputSource), name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(updateInputSource), name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: .leftMouseDown)
        if CommandLine.arguments.contains("--preview-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.togglePanel() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(clearWord), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(clearWord), name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshPermission), name: NSWorkspace.didWakeNotification, object: nil)
        refreshPermission()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPermission() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if (event.type == .leftMouseDown || event.type == .rightMouseDown), self.menuPanel?.isVisible == true, !self.isStatusButtonClick(event), event.window !== self.menuPanel || self.menuPanel?.contentView?.subviews.first?.frame.contains(event.locationInWindow) != true { self.closePanel() }
            if event.type == .keyDown && event.keyCode == 53 && self.menuPanel?.isVisible == true { self.closePanel(); return nil }
            guard let operation = self.recording else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.finishRecording(nil, operation); return nil }
                self.recordingTap.cancel()
                let flags = event.cgEvent?.flags.intersection(Shortcut.mask).rawValue ?? 0
                // Unmodified letters would make normal typing impossible.
                if flags == 0 && event.charactersIgnoringModifiers?.first?.isLetter == true { NSSound.beep(); return nil }
                self.finishRecording(Shortcut(key: event.keyCode, modifiers: flags), operation)
            } else {
                let flags = event.cgEvent?.flags.intersection(Shortcut.mask).rawValue ?? 0
                if let tapped = self.recordingTap.update(flags, now: ProcessInfo.processInfo.systemUptime) {
                    self.finishRecording(Shortcut(key: nil, modifiers: tapped), operation)
                }
            }
            return nil
        }
        if UserDefaults.standard.object(forKey: inputMenuRestoreKey) == nil {
            let visible = CFPreferencesCopyAppValue("visible" as CFString, inputMenuDomain) as? Bool ?? true
            UserDefaults.standard.set(visible, forKey: inputMenuRestoreKey)
            UserDefaults.standard.synchronize()
        }
        setSystemInputMenuVisible(false)
        if CommandLine.arguments.contains("--verify-input-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let hidden = self.systemInputMenuItem() == nil
                self.setSystemInputMenuVisible(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let restored = self.systemInputMenuItem() != nil
                    print("Input menu hidden: \(hidden); restored: \(restored); Accessibility: \(AXIsProcessTrusted())")
                    NSApp.terminate(nil)
                }
            }
        }
        NSApp.setActivationPolicy(.accessory)
        if verifyingRecovery {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.verifyRecovery() }
        } else if !CommandLine.arguments.contains("--verify-input-menu") && !CommandLine.arguments.contains("--preview-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.beginInitialSetup() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let previous = UserDefaults.standard.object(forKey: inputMenuRestoreKey) as? Bool {
            setSystemInputMenuVisible(previous)
            UserDefaults.standard.removeObject(forKey: inputMenuRestoreKey)
            UserDefaults.standard.synchronize()
        }
        timer?.invalidate(); stopTap()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let panelMonitor { NSEvent.removeMonitor(panelMonitor) }
    }

    private func setSystemInputMenuVisible(_ visible: Bool) {
        CFPreferencesSetAppValue("visible" as CFString, visible as CFBoolean, inputMenuDomain)
        CFPreferencesAppSynchronize(inputMenuDomain)
    }

    private func systemInputMenuItem() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextInputMenuAgent").first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        for attribute in [kAXExtrasMenuBarAttribute, kAXMenuBarAttribute] {
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(root, attribute as CFString, &bar) == .success, let bar else { continue }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
               let items = children as? [AXUIElement] {
                for item in items {
                    var value: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &value) == .success, let value else { continue }
                    var size = CGSize.zero
                    if AXValueGetValue(value as! AXValue, .cgSize, &size), size.width > 0 && size.height > 0 { return item }
                }
            }
        }
        return nil
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if menuPanel?.isVisible == true { closePanel(); return }
        clearWord()
        let bounds = NSRect(x: 0, y: 0, width: 312, height: 180)
        let content = NSView(frame: bounds)
        let glass: NSView
        if #available(macOS 26.0, *) {
            let effect = NSGlassEffectView(frame: bounds)
            effect.cornerRadius = 18
            effect.style = .regular
            effect.contentView = content
            glass = effect
        } else {
            let effect = NSVisualEffectView(frame: bounds)
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            let mask = NSImage(size: NSSize(width: 37, height: 37), flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
            effect.maskImage = mask
            content.autoresizingMask = [.width, .height]
            effect.addSubview(content)
            glass = effect
        }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -7),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 8)
        ])
        func label(_ text: String, _ size: CGFloat = 13, _ weight: NSFont.Weight = .regular) -> NSTextField {
            let view = NSTextField(labelWithString: text)
            view.font = .systemFont(ofSize: size, weight: weight)
            return view
        }
        func fullWidth(_ view: NSView, _ height: CGFloat) {
            let row: NSView
            if view is NSButton {
                row = view
            } else {
                row = NSView()
                row.addSubview(view)
                view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    view.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 7),
                    view.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -7),
                    view.topAnchor.constraint(equalTo: row.topAnchor),
                    view.bottomAnchor.constraint(equalTo: row.bottomAnchor)
                ])
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: height).isActive = true
        }
        func divider() {
            let holder = NSView()
            let line = NSBox(); line.boxType = .separator
            line.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(line)
            NSLayoutConstraint.activate([line.leadingAnchor.constraint(equalTo: holder.leadingAnchor), line.trailingAnchor.constraint(equalTo: holder.trailingAnchor), line.centerYAnchor.constraint(equalTo: holder.centerYAnchor)])
            fullWidth(holder, 17)
        }
        func action(_ title: String, _ selector: Selector) -> NSButton {
            let button = SwitchMenuButton(title: title, target: self, action: selector)
            button.isBordered = false
            button.alignment = .left
            button.font = .systemFont(ofSize: 13)
            button.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
            fullWidth(button, 24)
            return button
        }
        let heading = NSStackView()
        heading.spacing = 10
        let title = label("RMN Switch App", 13, .semibold)
        let control = NSSwitch(); control.target = self; control.action = #selector(toggleEnabled)
        control.state = enabled ? .on : .off
        control.setAccessibilityLabel("RMN Switch App")
        powerSwitch = control
        heading.addArrangedSubview(title); heading.addArrangedSubview(NSView()); heading.addArrangedSubview(control)
        fullWidth(heading, 26)
        divider()
        for (title, shortcut) in [("Сменить раскладку", layoutShortcut), ("Сменить регистр", caseShortcut)] {
            let row = NSStackView(); row.spacing = 10
            row.addArrangedSubview(label(title)); row.addArrangedSubview(NSView())
            let key = label(shortcut.title, 13); key.textColor = .secondaryLabelColor; row.addArrangedSubview(key)
            fullWidth(row, 24)
        }
        divider()
        _ = action("Настройки Switch…", #selector(showSettings))
        _ = action("Завершить Switch", #selector(quit))
        let size = NSSize(width: 312, height: stack.fittingSize.height + 16)
        glass.setFrameSize(size)
        let shadowInset: CGFloat = 40
        let frameView = NSView(frame: NSRect(x: 0, y: 0, width: size.width + shadowInset * 2, height: size.height + shadowInset * 2))
        glass.setFrameOrigin(NSPoint(x: shadowInset, y: shadowInset))
        frameView.addSubview(glass)
        frameView.wantsLayer = true
        let shadow = CALayer()
        shadow.frame = frameView.bounds
        shadow.shadowColor = NSColor.black.cgColor
        shadow.shadowOpacity = 0.16
        shadow.shadowRadius = 10
        shadow.shadowOffset = CGSize(width: 0, height: -3)
        shadow.shadowPath = CGPath(roundedRect: glass.frame, cornerWidth: 18, cornerHeight: 18, transform: nil)
        if NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua {
            let path = CGMutablePath()
            path.addRect(frameView.bounds)
            path.addPath(shadow.shadowPath!)
            let mask = CAShapeLayer()
            mask.frame = frameView.bounds
            mask.path = path
            mask.fillRule = .evenOdd
            shadow.mask = mask
        }
        frameView.layer?.insertSublayer(shadow, at: 0)
        let panel = SwitchMenuPanel(contentRect: frameView.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = frameView
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let anchor = button.window!.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = button.window!.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        panel.setFrameOrigin(NSPoint(x: min(max(anchor.maxX - size.width, screen.minX + 8), screen.maxX - size.width - 8) - shadowInset, y: screen.maxY - size.height - shadowInset))
        menuPanel = panel
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        panelMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, !self.isStatusButtonClick(event) else { return }
            self.closePanel()
        }
        if CommandLine.arguments.contains("--preview-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                frameView.layoutSubtreeIfNeeded()
                if let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
                    frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/rmn-switch-panel.png"))
                }
            }
        }
    }

    @objc private func toggleSourceName(_ sender: NSButton) {
        showSourceName = sender.state == .on
        UserDefaults.standard.set(showSourceName, forKey: "showSourceName")
        updateInputSource()
    }

    private func isStatusButtonClick(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown || event.type == .rightMouseDown,
              let button = statusItem.button, let window = button.window else { return false }
        let point = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? NSEvent.mouseLocation
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
    }

    private func closePanel() {
        menuPanel?.orderOut(nil)
        statusItem.button?.highlight(false)
        if let panelMonitor { NSEvent.removeMonitor(panelMonitor); self.panelMonitor = nil }
    }

    @objc private func openPermissions() {
        closePanel()
        requestAccessibility()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func requestAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func beginInitialSetup() {
        setupStarted = true
        if !AXIsProcessTrusted() {
            showSettings()
            requestAccessibility()
        } else { scheduleLoginPrompt() }
    }

    private func scheduleLoginPrompt() {
        guard setupStarted, !loginPromptScheduled, !loginPromptVisible,
              !UserDefaults.standard.bool(forKey: "loginPromptAnswered") else { return }
        if LaunchAtLogin.state != .disabled {
            UserDefaults.standard.set(true, forKey: "loginPromptAnswered")
            return
        }
        loginPromptScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.loginPromptScheduled = false
            guard AXIsProcessTrusted(), !UserDefaults.standard.bool(forKey: "loginPromptAnswered") else { return }
            self.loginPromptVisible = true
            self.closePanel()
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Запускать Switch при входе в систему?"
            alert.informativeText = "Switch будет готов к замене раскладки сразу после входа в macOS. Выбор можно изменить в настройках приложения."
            alert.addButton(withTitle: "Включить автозапуск")
            alert.addButton(withTitle: "Не сейчас")
            let response = alert.runModal()
            UserDefaults.standard.set(true, forKey: "loginPromptAnswered")
            self.loginPromptVisible = false
            if response == .alertFirstButtonReturn { self.setLaunchAtLogin(true) }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            if enabled && LaunchAtLogin.state == .requiresApproval { LaunchAtLogin.openSettings() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось изменить автозапуск"
            alert.informativeText = "\(error.localizedDescription)\nУстановите Switch в папку «Программы» и повторите попытку. Автозапуск также можно настроить в macOS."
            alert.addButton(withTitle: "Открыть настройки macOS")
            alert.addButton(withTitle: "Закрыть")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { LaunchAtLogin.openSettings() }
        }
        refreshSetupControls()
    }

    @objc private func changeLaunchAtLogin(_ sender: NSButton) {
        UserDefaults.standard.set(true, forKey: "loginPromptAnswered")
        setLaunchAtLogin(sender.state == .on)
    }

    @objc private func openLoginSettings() { LaunchAtLogin.openSettings() }

    private func refreshSetupControls() {
        let trusted = AXIsProcessTrusted()
        permissionSettingsButton?.title = trusted ? "Настройки…" : "Разрешить…"
        permissionStatus?.stringValue = !trusted ? "Разрешите доступ, чтобы Shift мог менять текст в других приложениях." : tap == nil ? "Доступ разрешён. Если Shift не работает, перезапустите Switch." : "Доступ разрешён. Обработка клавиш работает."
        let state = LaunchAtLogin.state
        loginCheckbox?.state = state == .disabled ? .off : .on
        loginStatus?.stringValue = state == .enabled ? "Автозапуск включён." : state == .requiresApproval ? "Подтвердите автозапуск в настройках macOS." : "Автозапуск выключен."
        loginApprovalButton?.isHidden = state != .requiresApproval
        fitSettingsWindow()
    }

    @objc private func clearWord() { word = ""; modifierTap.cancel(); if busy { interrupted = true } }
    @objc private func toggleEnabled() {
        enabled.toggle()
        powerSwitch?.state = enabled ? .on : .off
        UserDefaults.standard.set(!enabled, forKey: "paused")
        clearWord()
        refreshPermission()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openLanguageSettings() {
        closePanel()
        let url: URL
        if #available(macOS 13.0, *) {
            url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources")!
        } else {
            url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?InputSources")!
        }
        if !NSWorkspace.shared.open(url) { NSSound.beep() }
    }

    @objc private func updateInputSource() {
        let language = KeyboardSources.currentLabel()
        displayedLanguage = language
        let english = language == "EN"
        let label = english ? "A" : language == "RU" ? "РУ" : language
        let flag = indicatorStyle == .flags ? KeyboardSources.currentFlag() : nil
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { bounds in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            (flag == nil ? NSColor.black : NSColor.labelColor).set()
            let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            if let flag {
                NSGraphicsContext.saveGraphicsState()
                frame.addClip()
                if !FlatFlag.draw(flag, in: bounds.insetBy(dx: 0.5, dy: 0.5)) {
                    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Apple Color Emoji", size: 16) ?? .systemFont(ofSize: 16)]
                    let text = flag as NSString
                    let size = text.size(withAttributes: attributes)
                    text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
                }
                NSGraphicsContext.restoreGraphicsState()
                frame.lineWidth = 1
                frame.stroke()
                return true
            }
            if english { frame.fill() } else { frame.lineWidth = 1; frame.stroke() }
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: english ? 13 : 11, weight: .semibold), .foregroundColor: NSColor.black]
            let text = label as NSString
            let size = text.size(withAttributes: attributes)
            if english { NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut) }
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = flag == nil
        statusItem.button?.image = image
        if showSourceName, let pointer = TISGetInputSourceProperty(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), kTISPropertyLocalizedName) {
            statusItem.button?.title = " " + (Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String)
        } else { statusItem.button?.title = "" }
        statusItem.button?.attributedTitle = NSAttributedString(string: statusItem.button?.title ?? "", attributes: [.font: NSFont.menuBarFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        statusItem.button?.setAccessibilityLabel(language == "RU" ? "Русская раскладка" : english ? "Английская раскладка" : language)
        if !busy { clearWord() }
    }

    @objc private func refreshPermission() {
        let trusted = AXIsProcessTrusted()
        if let tap, !trusted || !CFMachPortIsValid(tap) { stopTap() }
        if trusted {
            if let tap, !CGEvent.tapIsEnabled(tap: tap) {
                clearWord(); consumedKeys.removeAll()
                CGEvent.tapEnable(tap: tap, enable: true)
                if !CGEvent.tapIsEnabled(tap: tap) { stopTap() }
            }
            if tap == nil { startTap() }
            scheduleLoginPrompt()
        }
        refreshSetupControls()
        statusItem.button?.appearsDisabled = !enabled
        statusItem.button?.toolTip = !trusted ? "RMN Switch App — разрешите Универсальный доступ" : tap == nil ? "RMN Switch App — обработка клавиш недоступна; перезапустите приложение" : "RMN Switch App"
        let label = KeyboardSources.currentLabel()
        if displayedLanguage != label { updateInputSource() }
    }

    private func stopTap() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; source = nil; consumedKeys.removeAll(); clearWord()
    }

    // Live diagnostic: recreate only this process's own keyboard event tap.
    private func verifyRecovery() {
        guard AXIsProcessTrusted() else { print("BLOCKED: Accessibility permission required"); exit(2) }
        guard let original = tap, CFMachPortIsValid(original), CGEvent.tapIsEnabled(tap: original) else {
            print("FAIL: initial event tap unavailable"); exit(1)
        }
        CGEvent.tapEnable(tap: original, enable: false)
        refreshPermission()
        guard CGEvent.tapIsEnabled(tap: original) else { print("FAIL: disabled tap not restored"); exit(1) }
        CFMachPortInvalidate(original)
        // Let the actual two-second timer detect and rebuild the invalid port.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard let restored = self.tap, CFMachPortIsValid(restored), CGEvent.tapIsEnabled(tap: restored) else {
                print("FAIL: invalid tap not recreated by timer"); exit(1)
            }
            print("PASS: disabled tap restored; invalid tap recreated automatically")
            self.openLanguageSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let settings = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.systempreferences" }) {
                    let root = AXUIElementCreateApplication(settings.processIdentifier)
                    var queue = [root]; var index = 0; var inputSheet = false
                    while index < queue.count && index < 500 {
                        let element = queue[index]; index += 1
                        var title: CFTypeRef?; var description: CFTypeRef?; var children: CFTypeRef?
                        AXUIElementCopyAttributeValue(element, "AXTitle" as CFString, &title)
                        AXUIElementCopyAttributeValue(element, "AXDescription" as CFString, &description)
                        let label = (title as? String ?? "") + " " + (description as? String ?? "")
                        if ["All Input Sources", "Все источники ввода", "Input Sources", "Источники ввода"].contains(where: { label.contains($0) }) { inputSheet = true }
                        AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &children)
                        queue += children as? [AXUIElement] ?? []
                    }
                    print(inputSheet ? "PASS: keyboard input sources opened" : "CHECK: System Settings opened; input source sheet not identified")
                }
                NSApp.terminate(nil)
            }
        }
    }

    private func startTap() {
        let events: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let app = Unmanaged<SwitchApp>.fromOpaque(context).takeUnretainedValue()
            return app.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            clearWord()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if verifyingRecovery || CommandLine.arguments.contains("--verify-input-menu") || CommandLine.arguments.contains("--preview-panel") { return false }
        if event.getIntegerValueField(.eventSourceUserData) == marker { return false }
        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp && consumedKeys.remove(key) != nil { return true }
        guard enabled, recording == nil, NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { clearWord(); return false }
        guard !IsSecureEventInputEnabled() else { clearWord(); return false }
        if busy {
            if type != .flagsChanged && type != .keyUp { interrupted = true; word = "" }
            return false
        }
        let flags = event.flags.intersection(Shortcut.mask).rawValue
        if type == .flagsChanged {
            if let tapped = modifierTap.update(flags, now: ProcessInfo.processInfo.systemUptime) {
                if layoutShortcut == Shortcut(key: nil, modifiers: tapped) { schedule(.layout) }
                else if caseShortcut == Shortcut(key: nil, modifiers: tapped) { schedule(.letterCase) }
            }
            return false
        }
        if type == .keyDown {
            modifierTap.cancel()
            for (shortcut, operation) in [(layoutShortcut, Operation.layout), (caseShortcut, Operation.letterCase)] {
                if shortcut.key == key && shortcut.modifiers == flags {
                    consumedKeys.insert(key)
                    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { schedule(operation) }
                    return true
                }
            }
            if event.flags.contains(.maskCommand) || event.flags.contains(.maskControl) || event.flags.contains(.maskAlternate) { word = ""; return false }
            if key == 51 { if !word.isEmpty { word.removeLast() }; return false }
            var characters = [UniChar](repeating: 0, count: 32)
            var length = 0
            event.keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &length, unicodeString: &characters)
            let typed = String(utf16CodeUnits: characters, count: length)
            if typed.isEmpty || typed.contains(where: { $0.isWhitespace || $0.isNewline || $0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) { word = "" }
            else { word += typed; if word.count > 256 { word = "" } }
        } else if type != .keyUp { clearWord() }
        return false
    }

    private func schedule(_ operation: Operation) {
        guard !busy else { return }
        busy = true; interrupted = false
        DispatchQueue.main.async { [weak self] in self?.convert(operation) }
    }

    private func focusedElement() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.15)
        return element
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func convert(_ operation: Operation) {
        guard !interrupted, !IsSecureEventInputEnabled(), let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { finish(); return }
        let element = focusedElement()
        if let element, attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { word = ""; finish(); return }
        let selected = element.flatMap { attribute($0, kAXSelectedTextAttribute) as? String }
        var range: CFRange?
        if let element, let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            var result = CFRange()
            if AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &result) { range = result }
        }
        if let selected, !selected.isEmpty {
            replace(selected, operation, pid: pid, selectWord: false)
        } else if selected != nil || range != nil {
            if let range, range.length > 0 { copySelection(operation, pid: pid, allowWord: false) }
            else if !word.isEmpty {
                // Ignore stale keystrokes after autocorrection or a cursor move.
                if let element, let range, let value = attribute(element, kAXValueAttribute) as? String {
                    let value = value as NSString
                    let length = word.utf16.count
                    guard range.location >= length, range.location <= value.length,
                          value.substring(with: NSRange(location: range.location - length, length: length)) == word else { word = ""; finish(); return }
                }
                replace(word, operation, pid: pid, selectWord: true)
            }
            else { finish() }
        } else if !word.isEmpty {
            // No copy probe while typing: Cmd+C can interrupt a terminal process.
            replace(word, operation, pid: pid, selectWord: true)
        } else {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Terminal" { finish(); return }
            copySelection(operation, pid: pid, allowWord: true)
        }
    }

    private func validTarget(_ pid: pid_t) -> Bool {
        enabled && !interrupted && !IsSecureEventInputEnabled() && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    private typealias Clipboard = [[NSPasteboard.PasteboardType: Data]]
    private func snapshotClipboard() -> Clipboard {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { values[type] = data } }
            return values
        }
    }
    private func restoreClipboard(_ saved: Clipboard, ifUnchanged count: Int) {
        let board = NSPasteboard.general
        guard board.changeCount == count else { return }
        board.clearContents()
        let items = saved.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { board.writeObjects(items) }
    }

    private func copySelection(_ operation: Operation, pid: pid_t, allowWord: Bool) {
        let saved = snapshotClipboard()
        let board = NSPasteboard.general
        let initial = board.changeCount
        guard validTarget(pid) else { finish(); return }
        sendKey(8, flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            let copied = board.changeCount != initial
            let copiedCount = board.changeCount
            let text = copied ? board.string(forType: .string) : nil
            // A user's new copy takes precedence over restoring our snapshot.
            if self.interrupted { self.word = ""; self.finish(); return }
            if copied { self.restoreClipboard(saved, ifUnchanged: copiedCount) }
            guard self.validTarget(pid) else { self.word = ""; self.finish(); return }
            if let text, !text.isEmpty { self.replace(text, operation, pid: pid, selectWord: false) }
            else if allowWord && !self.word.isEmpty { self.replace(self.word, operation, pid: pid, selectWord: true) }
            else { self.finish() }
        }
    }

    private func replace(_ text: String, _ operation: Operation, pid: pid_t, selectWord: Bool) {
        let converted = TextChange.apply(text, operation)
        guard converted != text, validTarget(pid) else { finish(); return }
        let saved = snapshotClipboard()
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(converted, forType: .string)
        let written = board.changeCount
        if selectWord { for _ in text { sendKey(123, flags: .maskShift) } }
        // Let the target application apply the selection before pasting.
        DispatchQueue.main.asyncAfter(deadline: .now() + (selectWord ? 0.05 : 0.01)) {
            guard self.validTarget(pid), board.changeCount == written else {
                self.restoreClipboard(saved, ifUnchanged: written); self.word = ""; self.finish(); return
            }
            self.sendKey(9, flags: .maskCommand)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.restoreClipboard(saved, ifUnchanged: written)
                if self.validTarget(pid) {
                    self.word = selectWord ? converted : ""
                    if operation == .layout { self.selectInputSource(for: converted) }
                } else { self.word = "" }
                self.finish()
            }
        }
    }

    private func sendKey(_ key: UInt16, flags: CGEventFlags) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.setIntegerValueField(.eventSourceUserData, value: marker)
            event?.post(tap: .cgSessionEventTap)
        }
    }

    private func selectInputSource(for text: String) {
        let language = text.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil ? "ru" : "en"
        if let source = KeyboardSources.source(language) { TISSelectInputSource(source) }
    }

    private func finish() { busy = false; interrupted = false; modifierTap.cancel() }

    @objc private func showSettings() {
        closePanel()
        clearWord()
        NSApp.setActivationPolicy(.accessory)
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 370), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "RMN Switch App"
            panel.delegate = self
            panel.isReleasedWhenClosed = false
            panel.center()
            let windowBackground = NSHostingView(rootView: Color.clear.background(.regularMaterial))
            windowBackground.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView!.addSubview(windowBackground)
            NSLayoutConstraint.activate([
                windowBackground.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
                windowBackground.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
                windowBackground.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
                windowBackground.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
            ])
            let stack = NSStackView()
            stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView?.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -22), stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 22)])
            settingsStack = stack
            let header = NSStackView()
            header.spacing = 12; header.alignment = .centerY
            header.heightAnchor.constraint(equalToConstant: 38).isActive = true
            let icon = NSImageView(image: NSImage(systemSymbolName: "keyboard", accessibilityDescription: "RMN Switch App")!)
            icon.contentTintColor = .secondaryLabelColor
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            let name = NSTextField(labelWithString: "RMN Switch App")
            name.font = .systemFont(ofSize: 20, weight: .semibold)
            let version = NSTextField(labelWithString: "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"))
            version.font = .systemFont(ofSize: 13)
            version.textColor = .secondaryLabelColor
            let title = NSStackView()
            title.spacing = 6; title.alignment = .lastBaseline
            title.addArrangedSubview(name); title.addArrangedSubview(version)
            header.addArrangedSubview(icon); header.addArrangedSubview(title)
            stack.addArrangedSubview(header)
            stack.setCustomSpacing(16, after: header)
            let tabPicker = NSSegmentedControl()
            tabPicker.segmentCount = 3
            tabPicker.trackingMode = .selectOne
            tabPicker.segmentStyle = .rounded
            tabPicker.controlSize = .large
            tabPicker.target = self
            tabPicker.action = #selector(changeSettingsTab(_:))
            for (index, item) in [("keyboard", "Клавиши"), ("paintbrush", "Внешний вид"), ("gearshape", "Система")].enumerated() {
                let image = NSImage(systemSymbolName: item.0, accessibilityDescription: item.1)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .regular))
                tabPicker.setImage(image, forSegment: index)
                tabPicker.setImageScaling(.scaleProportionallyDown, forSegment: index)
                tabPicker.setWidth(60, forSegment: index)
                tabPicker.setToolTip(item.1, forSegment: index)
            }
            tabPicker.setAccessibilityLabel("Раздел настроек")
            let tabRow = NSView()
            tabRow.translatesAutoresizingMaskIntoConstraints = false
            tabPicker.translatesAutoresizingMaskIntoConstraints = false
            tabRow.addSubview(tabPicker)
            stack.addArrangedSubview(tabRow)
            NSLayoutConstraint.activate([
                tabRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
                tabPicker.centerXAnchor.constraint(equalTo: tabRow.centerXAnchor),
                tabPicker.heightAnchor.constraint(equalToConstant: 38),
                tabPicker.topAnchor.constraint(equalTo: tabRow.topAnchor),
                tabPicker.bottomAnchor.constraint(equalTo: tabRow.bottomAnchor)
            ])
            settingsTabPicker = tabPicker
            let card = NSBox()
            card.boxType = .custom; card.titlePosition = .noTitle
            card.fillColor = .clear
            card.borderWidth = 0; card.cornerRadius = 8
            card.contentViewMargins = NSSize(width: 16, height: 16)
            let background: NSView
            if #available(macOS 26.0, *) {
                let shape = ConcentricRectangle(corners: .concentric(minimum: 8), isUniform: true)
                background = NSHostingView(rootView: shape.fill(.clear).glassEffect(.regular, in: shape))
            } else {
                let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                background = NSHostingView(rootView: Color.clear.background(.regularMaterial, in: shape)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.08))))
            }
            background.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(background, positioned: .below, relativeTo: card.contentView)
            NSLayoutConstraint.activate([
                background.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                background.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                background.topAnchor.constraint(equalTo: card.topAnchor),
                background.bottomAnchor.constraint(equalTo: card.bottomAnchor)
            ])
            stack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            let tabs = NSTabView()
            tabs.tabViewType = .noTabsNoBorder
            tabs.translatesAutoresizingMaskIntoConstraints = false
            card.contentView!.addSubview(tabs)
            NSLayoutConstraint.activate([
                tabs.leadingAnchor.constraint(equalTo: card.contentView!.leadingAnchor),
                tabs.trailingAnchor.constraint(equalTo: card.contentView!.trailingAnchor),
                tabs.topAnchor.constraint(equalTo: card.contentView!.topAnchor),
                tabs.bottomAnchor.constraint(equalTo: card.contentView!.bottomAnchor)
            ])
            settingsPageHeight = tabs.heightAnchor.constraint(equalToConstant: 200)
            settingsPageHeight?.isActive = true
            settingsTabs = tabs
            func page(_ title: String) -> NSStackView {
                let item = NSTabViewItem(identifier: title)
                item.label = title
                let content = NSView()
                item.view = content
                tabs.addTabViewItem(item)
                let settings = NSStackView()
                settings.orientation = .vertical; settings.alignment = .leading; settings.spacing = 12
                settings.translatesAutoresizingMaskIntoConstraints = false
                content.addSubview(settings)
                NSLayoutConstraint.activate([
                    settings.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                    settings.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                    settings.topAnchor.constraint(equalTo: content.topAnchor),
                    settings.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor)
                ])
                let heading = NSTextField(labelWithString: title)
                heading.font = .systemFont(ofSize: 13, weight: .semibold)
                settings.addArrangedSubview(heading)
                return settings
            }
            let keyboard = page("Клавиши замены")
            let appearance = page("Внешний вид")
            let system = page("Системные настройки")
            let appearanceRow = NSStackView()
            appearanceRow.spacing = 8
            let appearanceLabel = NSTextField(labelWithString: "Значок в меню")
            let appearancePicker = NSPopUpButton(frame: .zero, pullsDown: false)
            appearancePicker.addItems(withTitles: ["Буквы", "Флаги"])
            appearancePicker.selectItem(at: IndicatorStyle.allCases.firstIndex(of: indicatorStyle) ?? 0)
            appearancePicker.target = self
            appearancePicker.action = #selector(changeIndicatorStyle(_:))
            appearancePicker.setAccessibilityLabel("Отображение раскладки в строке меню")
            appearancePicker.widthAnchor.constraint(equalToConstant: 120).isActive = true
            appearanceRow.addArrangedSubview(appearanceLabel)
            appearanceRow.addArrangedSubview(NSView())
            appearanceRow.addArrangedSubview(appearancePicker)
            appearance.addArrangedSubview(appearanceRow)
            appearanceRow.widthAnchor.constraint(equalTo: appearance.widthAnchor).isActive = true
            let sourceNameCheckbox = NSButton(checkboxWithTitle: "Показывать название раскладки", target: self, action: #selector(toggleSourceName(_:)))
            sourceNameCheckbox.state = showSourceName ? .on : .off
            appearance.addArrangedSubview(sourceNameCheckbox)
            let permissionRow = NSStackView()
            permissionRow.spacing = 8
            permissionRow.addArrangedSubview(NSTextField(labelWithString: "Универсальный доступ"))
            permissionRow.addArrangedSubview(NSView())
            let permissionAction = NSButton(title: "Разрешить…", target: self, action: #selector(openPermissions))
            permissionAction.bezelStyle = .rounded
            permissionRow.addArrangedSubview(permissionAction)
            permissionSettingsButton = permissionAction
            system.addArrangedSubview(permissionRow)
            permissionRow.widthAnchor.constraint(equalTo: system.widthAnchor).isActive = true
            let permissionNote = NSTextField(wrappingLabelWithString: "")
            permissionNote.font = .systemFont(ofSize: 12)
            permissionNote.textColor = .secondaryLabelColor
            system.addArrangedSubview(permissionNote)
            permissionNote.widthAnchor.constraint(equalTo: system.widthAnchor).isActive = true
            permissionStatus = permissionNote
            let login = NSButton(checkboxWithTitle: "Запускать при входе в систему", target: self, action: #selector(changeLaunchAtLogin(_:)))
            system.addArrangedSubview(login)
            loginCheckbox = login
            let loginNote = NSTextField(wrappingLabelWithString: "")
            loginNote.font = .systemFont(ofSize: 12)
            loginNote.textColor = .secondaryLabelColor
            system.addArrangedSubview(loginNote)
            loginNote.widthAnchor.constraint(equalTo: system.widthAnchor).isActive = true
            loginStatus = loginNote
            let approval = NSButton(title: "Подтвердить в macOS…", target: self, action: #selector(openLoginSettings))
            approval.bezelStyle = .rounded
            system.addArrangedSubview(approval)
            loginApprovalButton = approval
            for (title, action, operation) in [("Раскладка", #selector(recordLayout), Operation.layout), ("Регистр", #selector(recordCase), Operation.letterCase)] {
                let row = NSStackView(); row.spacing = 8
                let icon = NSImageView(image: NSImage(systemSymbolName: operation == .layout ? "keyboard" : "textformat", accessibilityDescription: nil)!)
                icon.contentTintColor = .secondaryLabelColor
                icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
                let label = NSTextField(labelWithString: title)
                label.widthAnchor.constraint(equalToConstant: 88).isActive = true
                let button = NSButton(title: "", target: self, action: action)
                button.bezelStyle = .rounded
                button.widthAnchor.constraint(equalToConstant: 120).isActive = true
                row.addArrangedSubview(icon); row.addArrangedSubview(label); row.addArrangedSubview(button)
                keyboard.addArrangedSubview(row)
                if operation == .layout { layoutButton = button } else { caseButton = button }
            }
            let shortcutNote = NSTextField(wrappingLabelWithString: "Нажмите на сочетание, затем задайте новое. Esc — отмена.")
            shortcutNote.font = .systemFont(ofSize: 12)
            shortcutNote.textColor = .secondaryLabelColor
            keyboard.addArrangedSubview(shortcutNote)
            shortcutNote.widthAnchor.constraint(equalTo: keyboard.widthAnchor).isActive = true
            tabPicker.selectedSegment = AXIsProcessTrusted() ? 0 : 2
            tabs.selectTabViewItem(at: tabPicker.selectedSegment)
            window = panel
        }
        if !AXIsProcessTrusted() {
            settingsTabPicker?.selectedSegment = 2
            settingsTabs?.selectTabViewItem(at: 2)
        }
        refreshButtons(); refreshPermission()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func changeSettingsTab(_ sender: NSSegmentedControl) {
        guard let tabs = settingsTabs, tabs.tabViewItems.indices.contains(sender.selectedSegment) else { return }
        recording = nil
        recordingTap = ModifierTap()
        refreshButtons()
        tabs.selectTabViewItem(at: sender.selectedSegment)
        fitSettingsWindow()
    }

    private func fitSettingsWindow() {
        guard let window, let stack = settingsStack,
              let page = settingsTabs?.selectedTabViewItem?.view,
              let pageStack = page.subviews.first as? NSStackView else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        settingsPageHeight?.constant = ceil(pageStack.fittingSize.height)
        window.contentView?.layoutSubtreeIfNeeded()
        let height = ceil(stack.fittingSize.height) + 44
        let contentSize = NSSize(width: 380, height: height)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        if abs(window.frame.height - frame.height) > 0.5 {
            window.setFrame(frame, display: true)
        }
    }

    @objc private func changeIndicatorStyle(_ sender: NSPopUpButton) {
        guard IndicatorStyle.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        indicatorStyle = IndicatorStyle.allCases[sender.indexOfSelectedItem]
        UserDefaults.standard.set(indicatorStyle.rawValue, forKey: "indicatorStyle")
        updateInputSource()
    }
    @objc private func recordLayout() { startRecording(.layout) }
    @objc private func recordCase() { startRecording(.letterCase) }
    private func startRecording(_ operation: Operation) {
        recording = operation; recordingTap = ModifierTap(); refreshButtons()
    }
    private func finishRecording(_ shortcut: Shortcut?, _ operation: Operation) {
        recording = nil
        if let shortcut {
            let other = operation == .layout ? caseShortcut : layoutShortcut
            if shortcut == other { NSSound.beep() }
            else {
                if operation == .layout { layoutShortcut = shortcut } else { caseShortcut = shortcut }
                UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: operation == .layout ? "layoutShortcut" : "caseShortcut")
            }
        }
        refreshButtons()
    }
    private func refreshButtons() {
        layoutButton?.title = recording == .layout ? "…" : layoutShortcut.title
        caseButton?.title = recording == .letterCase ? "…" : caseShortcut.title
    }
    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === menuPanel { closePanel(); return }
        recording = nil; recordingTap = ModifierTap(); refreshButtons(); clearWord()
    }
    func windowDidBecomeKey(_ notification: Notification) {
        if notification.object as? NSWindow === window { refreshPermission() }
    }
    func windowWillClose(_ notification: Notification) {
        windowDidResignKey(notification)
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
enum SwitchMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            func check(_ condition: @autoclosure () -> Bool, _ title: String) {
                if !condition() { fputs("FAIL: \(title)\n", stderr); exit(1) }
            }
            check(TextChange.english.count == TextChange.russian.count, "keyboard mapping size")
            check(TextChange.apply("ghbdtn", .layout) == "привет", "English → Russian")
            check(TextChange.apply("Привет", .layout) == "Ghbdtn", "Russian → English")
            check(TextChange.apply("руддщ", .layout) == "hello", "Russian typo")
            check(TextChange.apply("`~[]{};:'\",.<>", .layout) == "ёЁхъХЪжЖэЭбюБЮ", "punctuation")
            check(TextChange.apply("hello/ @#$%^&|?", .layout) == "руддщ. \"№;%:?/,", "number row and slash")
            check(TextChange.apply("привет. \"№;%:?/,", .layout) == "ghbdtn/ @#$%^&|?", "reverse punctuation")
            check(TextChange.apply("Hello 123 👋", .letterCase) == "HELLO 123 👋", "uppercase")
            check(TextChange.apply("ПРИВЕТ Ё", .letterCase) == "привет ё", "lowercase")
            check(TextChange.apply("123 👋", .letterCase) == "123 👋", "nonletters")
            func checkMixedLayouts() {
                check(TextChange.apply("ghbdtn руддщ", .layout) == "привет hello", "mixed layouts in one selection")
                check(TextChange.apply("руддщ ghbdtn", .layout) == "hello привет", "mixed layouts in reverse order")
                check(TextChange.apply("Ghbdtn! Руддщ!\nVbh цщкдв", .layout) == "Привет! Hello!\nМир world", "mixed layouts preserve case and line breaks")
                check(TextChange.apply("ghbdtnруддщ", .layout) == "приветhello", "mixed layouts without spaces")
                check(TextChange.apply("123 👋\t\n", .layout) == "123 👋\t\n", "layout preserves digits emoji and whitespace")
            }
            checkMixedLayouts()
            check(TextChange.apply("ghbdtn/ руддщю", .layout) == "привет. hello.", "punctuation follows each word")
            let testDomain = "ru.rmn.LangSwitch.self-test." + UUID().uuidString
            let testDefaults = UserDefaults(suiteName: testDomain)!
            defer { testDefaults.removePersistentDomain(forName: testDomain) }
            check(IndicatorStyle.load(from: testDefaults) == .letters, "default indicator uses letters")
            testDefaults.set(IndicatorStyle.flags.rawValue, forKey: "indicatorStyle")
            check(IndicatorStyle.load(from: UserDefaults(suiteName: testDomain)!) == .flags, "indicator preference reload")
            testDefaults.set("unsupported", forKey: "indicatorStyle")
            check(IndicatorStyle.load(from: testDefaults) == .letters, "unknown indicator preference fallback")
            let loginTestDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: loginTestDirectory) }
            let loginTestFile = loginTestDirectory.appendingPathComponent("LaunchAgents/test.plist")
            let loginTestApp = URL(fileURLWithPath: "/Applications/RMN Switch App.app")
            do {
                try LaunchAtLogin.setLegacyEnabled(true, appURL: loginTestApp, fileURL: loginTestFile)
                let data = try Data(contentsOf: loginTestFile)
                let config = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
                check(config["ProgramArguments"] as? [String] == ["/usr/bin/open", "-g", loginTestApp.path], "Monterey login item preserves app path with spaces")
                check(config["RunAtLoad"] as? Bool == true && config["KeepAlive"] == nil, "login launches once without restart loop")
                check(config["Label"] as? String == LaunchAtLogin.label, "login item has app-specific identity")
                try LaunchAtLogin.setLegacyEnabled(false, appURL: loginTestApp, fileURL: loginTestFile)
                try LaunchAtLogin.setLegacyEnabled(false, appURL: loginTestApp, fileURL: loginTestFile)
                check(!FileManager.default.fileExists(atPath: loginTestFile.path), "login item can be disabled repeatedly")
            } catch { check(false, "login item configuration: \(error)") }
            var tap = ModifierTap()
            check(tap.update(CGEventFlags.maskShift.rawValue, now: 1) == nil, "Shift press")
            check(tap.update(0, now: 1.2) == CGEventFlags.maskShift.rawValue, "Shift tap")
            _ = tap.update(CGEventFlags.maskShift.rawValue, now: 2)
            tap.cancel()
            check(tap.update(0, now: 2.2) == nil, "Shift used for typing")
            _ = tap.update(CGEventFlags.maskShift.rawValue, now: 3)
            check(tap.update(0, now: 4) == nil, "held Shift")
            _ = tap.update(CGEventFlags.maskShift.rawValue, now: 5)
            _ = tap.update(Shortcut.mask.rawValue, now: 5.1)
            tap.cancel()
            _ = tap.update(CGEventFlags.maskShift.rawValue, now: 5.2)
            check(tap.update(0, now: 5.3) == nil, "modifier chord does not rearm Shift")
            check(Shortcut.letterCase.title == "⇧` / ~", "default case shortcut")
            TextChange.configure()
            checkMixedLayouts()
            check(TextChange.apply("ghbdtn", .layout) == "привет", "native keyboard layout")
            if let en = TextChange.nativeToRussian, let ru = TextChange.nativeToEnglish {
                for (e, r) in en where e.isLetter { check(ru[r] == e, "native letter round trip") }
            }
            print("PASS: text conversion, mixed layouts, indicator preferences, login configuration and shortcuts")
        } else {
            let app = NSApplication.shared
            let delegate = SwitchApp()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
