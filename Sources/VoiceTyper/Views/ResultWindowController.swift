import AppKit
import SwiftUI

@MainActor
final class ResultWindowController: NSObject {
    static let shared = ResultWindowController()

    private var window: NSWindow?

    func showProcessing(actionTitle: String) {
        present(
            title: actionTitle,
            rootView: AnyView(ProcessingResultView(actionTitle: actionTitle))
        )
    }

    func showResult(text: String, actionTitle: String, costUSD: Double?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        present(
            title: actionTitle,
            rootView: AnyView(
                TranscriptionResultView(
                    actionTitle: actionTitle,
                    text: text,
                    costUSD: costUSD,
                    close: { [weak self] in self?.window?.close() }
                )
            )
        )
    }

    func showError(_ message: String, actionTitle: String) {
        present(
            title: "Ошибка — \(actionTitle)",
            rootView: AnyView(
                TranscriptionErrorView(
                    actionTitle: actionTitle,
                    message: message,
                    close: { [weak self] in self?.window?.close() }
                )
            )
        )
    }

    private func present(title: String, rootView: AnyView) {
        let controller = NSHostingController(rootView: rootView)

        if let window {
            window.title = title
            window.contentViewController = controller
        } else {
            let window = NSWindow(contentViewController: controller)
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 520, height: 340))
            window.minSize = NSSize(width: 380, height: 240)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct ProcessingResultView: View {
    let actionTitle: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Распознаю запись")
                .font(.title3.weight(.semibold))
            Text("Окно останется открытым — здесь появится текст или описание ошибки.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(actionTitle): идёт распознавание записи")
    }
}

private struct TranscriptionResultView: View {
    let actionTitle: String
    let text: String
    let costUSD: Double?
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Текст готов", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)

            Text("Результат уже скопирован в буфер обмена.")
                .foregroundStyle(.secondary)

            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Распознанный текст \(actionTitle.lowercased())")

            HStack {
                if let costUSD {
                    Text("Стоимость: $\(costUSD, specifier: "%.5f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Скопировать") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("Закрыть", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TranscriptionErrorView: View {
    let actionTitle: String
    let message: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Не удалось распознать запись", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.red)
            Text(message)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("Проверьте ключ OpenRouter, подключение к интернету и выбранный режим в настройках.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Spacer()
                Button("Закрыть", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ошибка \(actionTitle): \(message)")
    }
}
