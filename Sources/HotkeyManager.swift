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

    private init() {
        NotificationCenter.default.addObserver(
            forName: .statusBarHotkeyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reregister()
            }
        }
    }

    var displayString: String { HotkeyConfig.displayString }

    func reregister() {
        unregister()
        register()
    }

    func register() {
        guard hotkeyRef == nil, HotkeyConfig.enabled else { return }
        let keyCode = UInt32(HotkeyConfig.keyCode)
        let modifiers = UInt32(HotkeyConfig.modifiers)

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
