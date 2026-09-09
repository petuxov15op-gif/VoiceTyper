import AppKit
import ApplicationServices

enum TextInsertionError: LocalizedError {
    case accessibilityPermissionRequired
    case unavailable
    case clipboardChanged

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Чтобы вставлять текст в другие приложения, разрешите VoiceTyper в «Настройки системы → Конфиденциальность и безопасность → Универсальный доступ»."
        case .unavailable:
            "Не удалось отправить текст в активное поле. Поставьте курсор в поле ввода и повторите попытку."
        case .clipboardChanged:
            "Буфер обмена изменился во время вставки. Распознанный текст доступен в меню VoiceTyper — скопируйте его снова."
        }
    }
}

enum TextInsertionOutcome: Equatable {
    case inserted
    case copiedToClipboard
}

struct TextInsertionTarget {
    let application: NSRunningApplication?
    let focusedElement: AXUIElement?
}

@MainActor
final class TextInserter {
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted() || CGPreflightPostEventAccess()
    }

    func requestAccessibilityPermission() {
        promptForAccessibilityPermission()
        openAccessibilitySettings()
    }

    func promptForAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestPostEventAccess()
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func captureTarget() -> TextInsertionTarget {
        let application = NSWorkspace.shared.frontmostApplication.flatMap { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : app
        }
        return TextInsertionTarget(
            application: application,
            focusedElement: application == nil ? nil : focusedElement()
        )
    }

    func insert(_ text: String, into target: TextInsertionTarget) async throws -> TextInsertionOutcome {
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextInsertionError.unavailable
        }

        if let element = target.focusedElement,
           AXUIElementSetAttributeValue(
               element,
               kAXSelectedTextAttribute as CFString,
               text as CFTypeRef
           ) == .success {
            return .inserted
        }

        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            throw TextInsertionError.unavailable
        }
        let clipboardChangeCount = NSPasteboard.general.changeCount
        guard let application = target.application, !application.isTerminated,
              application.activate() else { return .copiedToClipboard }
        try await Task.sleep(for: .milliseconds(120))
        try Task.checkCancellation()
        guard NSPasteboard.general.changeCount == clipboardChangeCount else {
            throw TextInsertionError.clipboardChanged
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
            return .copiedToClipboard
        }

        if let element = focusedElement(),
           AXUIElementSetAttributeValue(
               element,
               kAXSelectedTextAttribute as CFString,
               text as CFTypeRef
           ) == .success {
            return .inserted
        }

        guard CGPreflightPostEventAccess(),
              let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return .copiedToClipboard
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .inserted
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }
}
