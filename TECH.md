# VoiceTyper technical design

## Modules

- `AppState`: user-visible state and action routing.
- `AppSettings`: persisted non-secret preferences.
- `GlobalHotKeyManager`: Carbon hot-key registration and dispatch.
- `ShortcutRecorderView`: native key-event capture in Settings.
- `AudioRecorder`: microphone capture and temporary files.
- `SpeechRecognizer`: provider-independent transcription protocol.
- `LocalWhisperRecognizer`: actor-isolated WhisperKit/Core ML implementation using
  multilingual Small model with a reusable model pipeline.
- `OpenRouterRecognizer`: cloud implementation; API key loaded from Keychain.
- `TextInserter`: captures the focused Accessibility element before recording,
  uses AX selected-text insertion first, CGEvent paste second, and clipboard-only fallback last.
- `AssistantService`: command interpretation and result routing.

## Delivery sequence

1. App shell, settings, shortcut model and registration.
2. Audio capture and permission handling.
3. OpenRouter transcription.
4. Local Whisper integration and model management.
5. Text insertion and end-to-end dictation.
6. Assistant command pipeline.
7. Packaging, signing guidance, accessibility QA, and release tests.

## Security boundaries

- No secret enters `UserDefaults`.
- Network calls are only made from cloud provider implementations.
- Audio URLs have short lifetimes and deterministic cleanup.
- Assistant actions that mutate external state require confirmation.

## Validation

- Unit-test shortcut press tracking, including ignored key auto-repeat and hold/tap distinction.
- Integration-test two consecutive local transcriptions using one WhisperKit instance.
- Exercise the installed app twice in one process and verify recording, transcription,
  process survival, and insertion outcome separately.
