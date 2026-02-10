// HotkeyManager.swift
// Registers a global hotkey (Ctrl+Option+S) to toggle the StatusBar popover.

import Carbon
import Cocoa

// C function pointer for the Carbon event handler — must be a free function.
private func hotkeyEventHandler(
    _: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.onToggle?()
    }
    return noErr
}

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onToggle: (() -> Void)?

    // Default: Ctrl+Option+S
    let modifiers: UInt32 = UInt32(controlKey | optionKey)
    let keyCode: UInt32 = 1  // 's' key

    var displayString: String { "\u{2303}\u{2325}S" }

    func register() {
        guard hotkeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )

        let hotkeyID = EventHotKeyID(
            signature: OSType(0x5342_4152),  // "SBAR"
            id: 1)

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
