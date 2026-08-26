import AppKit
import SwiftUI

@MainActor
final class RecordingOverlayController {
    static let shared = RecordingOverlayController()

    private var panel: NSPanel?

    func show(appState: AppState) {
        let panel = panel ?? makePanel(appState: appState)
        panel.contentViewController = NSHostingController(rootView: RecordingOverlayView().environmentObject(appState))
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(appState: AppState) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 132, height: 44),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentViewController = NSHostingController(rootView: RecordingOverlayView().environmentObject(appState))
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: screen.frame.midX - panel.frame.width / 2,
                y: frame.minY + 28
            )
        )
    }
}

private struct RecordingOverlayView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            TimelineView(.animation(minimumInterval: 1.0 / 18.0)) { timeline in
                WaveformBars(
                    level: appState.inputLevel,
                    phase: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                )
            }
            .frame(height: 14)
            .accessibilityLabel("Идёт запись голоса")
        }
        .padding(.horizontal, 14)
        .frame(width: 132, height: 44)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct WaveformBars: View {
    let level: Float
    let phase: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.accentColor.gradient)
                        .frame(
                            width: 2,
                            height: barHeight(index: index, maximum: proxy.size.height)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func barHeight(index: Int, maximum: CGFloat) -> CGFloat {
        let movement = (sin(phase * 7 + Double(index) * 0.8) + 1) / 2
        let shape = 0.45 + 0.55 * (1 - abs(Double(index - 3)) / 4)
        let intensity = max(0.18, min(1, Double(level) * 2.2))
        return min(maximum, max(3, maximum * (0.18 + intensity * shape * (0.30 + movement * 0.35))))
    }
}
