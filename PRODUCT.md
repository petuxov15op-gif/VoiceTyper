# VoiceTyper product specification

## Goal

Provide private, affordable voice input anywhere on macOS through two configurable actions:

1. Dictation: speech is transcribed and inserted at the current cursor.
2. Voice assistant: speech is interpreted as a command and the assistant response is shown or applied.

## First release

- Menu-bar app with no Dock requirement in the packaged build.
- Configurable global shortcut for dictation.
- Configurable global shortcut for the voice assistant.
- Local Whisper transcription.
- OpenRouter speech-to-text transcription.
- Russian recognition mode.
- Recognition context for names, product names, and specialist terms.
- Optional OpenRouter spelling and punctuation correction.
- Selectable microphone with optional voice processing.
- Automatic insertion with clipboard fallback.
- Explicit microphone, Accessibility, and network states.
- OpenRouter credentials stored in macOS Keychain.

## Interaction

- Shortcuts are independently editable.
- A shortcut supports both push-to-talk (hold, speak, release) and toggle mode
  (tap once to start, tap again to finish); key auto-repeat is ignored.
- Recording ends when the user releases a held shortcut or presses the shortcut again in toggle mode.
- A shortcut conflict prevents saving/registration and is explained next to the control.
- The menu always shows one of: ready, listening, processing, or error.
- Dictation and assistant modes use visibly distinct labels and icons.
- Escape cancels an active capture or recording.

## Privacy

- Local mode never uploads audio.
- WhisperKit downloads the multilingual Whisper Large V3 Turbo Core ML model once;
  model files are cached locally.
- Cloud mode clearly identifies the selected provider.
- Smart correction is opt-in and available only in OpenRouter mode.
- Temporary recordings are deleted after success, cancellation, or failure.
- No audio history is enabled by default.

## Acceptance criteria

- Both shortcuts work while another application is active.
- Local mode transcribes Russian without internet.
- OpenRouter mode returns Russian text from a valid account.
- Dictation inserts text into common macOS applications.
- The app recovers gracefully from missing permissions and provider failures.
- Two consecutive dictations work in one running app process.
