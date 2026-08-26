import Foundation

struct ShortcutPressTracker: Equatable {
    enum Release: Equatable {
        case quickTap
        case held
    }

    private(set) var pressedAt: TimeInterval?
    let holdThreshold: TimeInterval

    init(holdThreshold: TimeInterval = 0.35) {
        self.holdThreshold = holdThreshold
    }

    mutating func press(at time: TimeInterval) -> Bool {
        guard pressedAt == nil else { return false }
        pressedAt = time
        return true
    }

    mutating func release(at time: TimeInterval) -> Release? {
        guard let pressedAt else { return nil }
        self.pressedAt = nil
        return time - pressedAt >= holdThreshold ? .held : .quickTap
    }

    mutating func reset() {
        pressedAt = nil
    }
}
