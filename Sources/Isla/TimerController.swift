import AppKit

/// Plain timers and a pomodoro (25 min of focus, then 5 of rest).
@MainActor
final class TimerController {
    static let shared = TimerController()

    static let focusMinutes = 25.0
    static let restMinutes = 5.0

    private var tick: Timer?

    func startTimer(minutes: Double) { run(.timer, minutes: minutes) }
    func startPomodoro() { run(.focus, minutes: Self.focusMinutes) }

    func stop() {
        tick?.invalidate()
        tick = nil
        IslaModel.shared.timer = nil
    }

    private func run(_ kind: RunningTimer.Kind, minutes: Double) {
        let total = minutes * 60
        IslaModel.shared.timer = RunningTimer(kind: kind, end: Date().addingTimeInterval(total), total: total)
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func check() {
        guard let t = IslaModel.shared.timer, Date() >= t.end else { return }
        NSSound(named: "Glass")?.play()
        switch t.kind {
        case .timer:
            stop()
            IslaModel.shared.post(Notice(source: .timer, title: "Se acabó el tiempo",
                                         subtitle: Self.format(t.total), duration: 10, symbol: "timer"))
        case .focus:
            run(.rest, minutes: Self.restMinutes)
            IslaModel.shared.post(Notice(source: .timer, title: "Pomodoro terminado",
                                         subtitle: "Toca descansar 5 minutos", duration: 10, symbol: "cup.and.saucer.fill"))
        case .rest:
            stop()
            IslaModel.shared.post(Notice(source: .timer, title: "Fin del descanso",
                                         subtitle: "Vuelta al trabajo", duration: 10, symbol: "figure.walk"))
        }
    }

    /// 1500 → "25:00", 3725 → "1:02:05".
    static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
