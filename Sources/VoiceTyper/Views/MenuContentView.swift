import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(appState.statusTitle, systemImage: appState.statusSymbol)
                .font(.headline)

            if appState.isRecording {
                Text("Отпустите удерживаемое сочетание или нажмите его ещё раз.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                appState.toggle(.dictation)
            } label: {
                Label(
                    appState.isRecording ? "Завершить диктовку" : "Начать диктовку",
                    systemImage: appState.isRecording ? "stop.circle" : "text.cursor"
                )
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button {
                appState.toggle(.assistant)
            } label: {
                Label(
                    appState.isRecording ? "Завершить запись" : "Вызвать помощника",
                    systemImage: appState.isRecording ? "stop.circle" : "sparkles"
                )
            }
            .keyboardShortcut("a", modifiers: [.command])

            if case .listening = appState.mode {
                Button("Завершить запись") { appState.finish() }
                    .keyboardShortcut(.return, modifiers: [])
                Button("Отменить", role: .cancel) { appState.cancel() }
                    .keyboardShortcut(.cancelAction)
            }

            if case .starting = appState.mode {
                Button("Отменить", role: .cancel) { appState.cancel() }
                    .keyboardShortcut(.cancelAction)
            }

            if case .error(let message) = appState.mode {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !appState.hasAccessibilityPermission {
                Label("Для вставки текста включите «Универсальный доступ» в настройках.", systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice = appState.insertionNotice {
                Label(notice, systemImage: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let transcript = appState.lastTranscript {
                Text(transcript)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Скопировать текст") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript, forType: .string)
                }

                if let cost = appState.lastCostUSD {
                    Text("Стоимость запроса: $\(cost, specifier: "%.5f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = appState.shortcutError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Настройки…") {
                SettingsWindowController.shared.show(appState: appState)
            }
            .keyboardShortcut(",", modifiers: [.command])

            Button("Завершить VoiceTyper") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(12)
        .frame(width: 290)
    }
}
