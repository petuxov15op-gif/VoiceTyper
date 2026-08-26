import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcut
    @State private var isRecording = false

    var body: some View {
        ShortcutCaptureRepresentable(
            shortcut: $shortcut,
            isRecording: $isRecording
        )
        .frame(width: 150, height: 30)
        .accessibilityLabel("Сочетание клавиш")
        .accessibilityValue(shortcut.displayName)
    }
}
private struct ShortcutCaptureRepresentable: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView()
        view.onShortcut = { shortcut in self.shortcut = shortcut }
        view.onRecordingChange = { isRecording in self.isRecording = isRecording }
        view.update(shortcut: shortcut, isRecording: isRecording)
        return view
    }

    func updateNSView(_ view: ShortcutCaptureView, context: Context) {
        view.onShortcut = { shortcut in self.shortcut = shortcut }
        view.onRecordingChange = { isRecording in self.isRecording = isRecording }
        view.update(shortcut: shortcut, isRecording: isRecording)
    }
}

private final class ShortcutCaptureView: NSView {
    var onShortcut: ((KeyboardShortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var shortcut = KeyboardShortcut.defaultDictation
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        refreshAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        onRecordingChange?(true)
        refreshAppearance()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            onRecordingChange?(false)
            refreshAppearance()
            return
        }

        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }

        shortcut = KeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        )
        onShortcut?(shortcut)
        isRecording = false
        onRecordingChange?(false)
        refreshAppearance()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        onRecordingChange?(false)
        refreshAppearance()
        return super.resignFirstResponder()
    }

    func update(shortcut: KeyboardShortcut, isRecording: Bool) {
        self.shortcut = shortcut
        self.isRecording = isRecording
        refreshAppearance()
    }

    private func refreshAppearance() {
        label.stringValue = isRecording ? "Нажмите сочетание…" : shortcut.displayName
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
