// HotkeyRecorder.swift
// Records a global hotkey combination via a local key monitor.
// Talks to HotkeyManager only through UserDefaults + notification so this
// file stays compilable in the test target (no Carbon import).

import AppKit
import SwiftUI

struct HotkeyRecorderView: View {
    @State private var isRecording = false
    @State private var monitor: Any?
    @AppStorage(HotkeyConfig.keyCodeKey) private var keyCode = HotkeyConfig.defaultKeyCode
    @AppStorage(HotkeyConfig.modifiersKey) private var modifiers = HotkeyConfig.defaultModifiers
    @AppStorage(HotkeyConfig.charKey) private var char = HotkeyConfig.defaultChar

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "Type shortcut\u{2026}" : HotkeyConfig.displayString)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isRecording ? Color.accentColor : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isRecording ? Color.accentColor : .clear, lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .help(isRecording ? "Press a key combination, or Escape to cancel" : "Click to change the hotkey")
        .accessibilityLabel(
            isRecording
                ? "Recording new hotkey, press a key combination"
                : "Global hotkey: \(HotkeyConfig.displayString). Click to change."
        )
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
            return nil  // swallow the event while recording
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Escape cancels
        if event.keyCode == 53 {
            stopRecording()
            return
        }

        var carbonModifiers = 0
        let flags = event.modifierFlags
        if flags.contains(.control) { carbonModifiers |= HotkeyConfig.carbonControl }
        if flags.contains(.option) { carbonModifiers |= HotkeyConfig.carbonOption }
        if flags.contains(.shift) { carbonModifiers |= HotkeyConfig.carbonShift }
        if flags.contains(.command) { carbonModifiers |= HotkeyConfig.carbonCommand }

        // Require at least one non-shift modifier so plain typing can't become a hotkey
        let hasAnchor =
            carbonModifiers
            & (HotkeyConfig.carbonControl | HotkeyConfig.carbonOption | HotkeyConfig.carbonCommand) != 0
        guard hasAnchor else { return }

        keyCode = Int(event.keyCode)
        modifiers = carbonModifiers
        char = (event.charactersIgnoringModifiers ?? "?").uppercased()
        stopRecording()
        NotificationCenter.default.post(name: .statusBarHotkeyChanged, object: nil)
    }
}
