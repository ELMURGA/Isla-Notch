import SwiftUI

/// Where a notice comes from. Each source has its own colour and symbol in the island.
enum NoticeSource: String {
    case claude, vscode, chatgpt, n8n, battery, music, calendar, timer, custom

    var symbol: String {
        switch self {
        case .claude:   return "sparkle"
        case .vscode:   return "chevron.left.forwardslash.chevron.right"
        case .chatgpt:  return "bubble.left.and.bubble.right.fill"
        case .n8n:      return "point.3.connected.trianglepath.dotted"
        case .battery:  return "battery.25percent"
        case .music:    return "music.note"
        case .calendar: return "calendar"
        case .timer:    return "timer"
        case .custom:   return "bell.fill"
        }
    }

    /// Brand logo shipped in the app's Resources (Simple Icons, CC0), if this source has one.
    @MainActor var logo: NSImage? {
        let name: String
        switch self {
        case .claude: name = "claude"
        case .vscode: name = "vscode"
        case .chatgpt: name = "chatgpt"
        case .n8n:    name = "n8n"
        default:      return nil
        }
        if let cached = Self.logoCache[name] { return cached }
        let img = Bundle.main.url(forResource: name, withExtension: "svg").flatMap { NSImage(contentsOf: $0) }
        Self.logoCache[name] = img
        return img
    }
    @MainActor private static var logoCache: [String: NSImage?] = [:]

    var color: Color {
        switch self {
        case .claude:   return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .vscode:   return Color(red: 0.18, green: 0.58, blue: 0.88)
        case .chatgpt:  return Color(red: 0.25, green: 0.72, blue: 0.56)
        case .n8n:      return Color(red: 0.92, green: 0.30, blue: 0.40)
        case .battery:  return Color(red: 0.95, green: 0.75, blue: 0.20)
        case .music:    return Color(red: 0.11, green: 0.84, blue: 0.38)
        case .calendar: return Color(red: 0.98, green: 0.36, blue: 0.33)
        case .timer:    return Color(red: 1.00, green: 0.62, blue: 0.20)
        case .custom:   return Color(red: 0.40, green: 0.60, blue: 1.00)
        }
    }
}

struct Notice: Identifiable, Equatable {
    let id = UUID()
    let source: NoticeSource
    let title: String
    let subtitle: String
    let date = Date()
    /// Seconds the notice stays open in the island.
    var duration: TimeInterval = 5
    /// Overrides the source symbol (for example a battery level).
    var symbol: String? = nil
    /// Set for a Claude Code permission request waiting for Allow / Deny.
    var approvalId: UUID? = nil
    /// The command or file the request is about.
    var detail: String = ""
}

struct NowPlaying: Equatable {
    var player: String          // "Spotify" or "Music"
    var title: String
    var artist: String
    var isPlaying: Bool
    var artworkURL: URL?
}

struct UpcomingEvent: Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarColor: Color
    let url: URL?
}

/// A running countdown: a plain timer or a pomodoro phase.
struct RunningTimer: Equatable {
    enum Kind: Equatable { case timer, focus, rest }
    let kind: Kind
    let end: Date
    let total: TimeInterval

    var label: String {
        switch kind {
        case .timer: return "Temporizador"
        case .focus: return "Concentración"
        case .rest:  return "Descanso"
        }
    }
}

enum IslandState: Equatable {
    case idle, alert, expanded
}

/// Shared state the island draws. Everything runs on the main thread.
@MainActor
final class IslaModel: ObservableObject {
    static let shared = IslaModel()

    @Published var state: IslandState = .idle
    @Published var current: Notice?
    @Published var history: [Notice] = []
    @Published var nowPlaying: NowPlaying?
    @Published var artwork: NSImage?
    @Published var batteryLevel: Int?
    @Published var batteryCharging = false
    @Published var nextEvent: UpcomingEvent?
    @Published var calendarAccess = true
    @Published var timer: RunningTimer?

    /// Size of the physical notch, filled in by the window controller.
    @Published var notchSize = CGSize(width: 185, height: 32)

    private var queue: [Notice] = []
    private var hideWork: DispatchWorkItem?

    var isAskingApproval: Bool { current?.approvalId != nil }

    func post(_ notice: Notice) {
        if notice.approvalId == nil {
            history.insert(notice, at: 0)
            if history.count > 20 { history.removeLast(history.count - 20) }
        }
        if current == nil {
            show(notice)
        } else if notice.approvalId != nil, current?.approvalId == nil {
            // A permission request jumps ahead of plain notices.
            if let cur = current { queue.insert(cur, at: 0) }
            show(notice)
        } else {
            queue.append(notice)
        }
    }

    private func show(_ notice: Notice) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            current = notice
            if state != .expanded { state = .alert }
        }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissCurrent() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + notice.duration, execute: work)
    }

    func dismissCurrent() {
        hideWork?.cancel()
        if !queue.isEmpty {
            show(queue.removeFirst())
            return
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            current = nil
            if state == .alert { state = .idle }
        }
    }

    /// Removes a permission request that was answered or expired, shown or queued.
    func removeApproval(_ id: UUID) {
        queue.removeAll { $0.approvalId == id }
        if current?.approvalId == id { dismissCurrent() }
    }
}
