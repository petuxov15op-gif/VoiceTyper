import Carbon
import Foundation

@MainActor
final class GlobalHotKeyManager {
    enum Action: UInt32, Sendable {
        case dictation = 1
        case assistant = 2
    }

    enum Phase: Sendable {
        case pressed
        case released
    }

    enum RegistrationError: LocalizedError {
        case conflict
        case registrationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .conflict:
                "Сочетания для диктовки и помощника совпадают."
            case .registrationFailed(let status):
                "macOS не зарегистрировала сочетание клавиш (код \(status))."
            }
        }
    }

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var onAction: ((Action, Phase) -> Void)?

    init() {
        installHandler()
    }

    func register(
        dictation: KeyboardShortcut,
        assistant: KeyboardShortcut,
        onAction: @escaping (Action, Phase) -> Void
    ) throws {
        guard dictation != assistant else { throw RegistrationError.conflict }
        unregisterAll()
        self.onAction = onAction
        try register(dictation, action: .dictation)
        do {
            try register(assistant, action: .assistant)
        } catch {
            unregisterAll()
            throw error
        }
    }

    private func installHandler() {
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr,
                      let action = Action(rawValue: identifier.id)
                else { return status }
                let manager = Unmanaged<GlobalHotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                let phase: Phase = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                    ? .pressed
                    : .released
                MainActor.assumeIsolated {
                    manager.onAction?(action, phase)
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            pointer,
            &eventHandler
        )
    }

    private func register(_ shortcut: KeyboardShortcut, action: Action) throws {
        let signature = OSType(0x56545950) // VTYP
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            EventHotKeyID(signature: signature, id: action.rawValue),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            throw RegistrationError.registrationFailed(status)
        }
        hotKeyRefs.append(reference)
    }

    private func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
    }
}
