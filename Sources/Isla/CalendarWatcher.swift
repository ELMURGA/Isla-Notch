import EventKit
import SwiftUI

/// Next meeting from the Mac's Calendar app (iCloud, Google, Exchange… whatever is
/// added there). Notices 10 minutes before and when it starts.
@MainActor
final class CalendarWatcher {
    static let shared = CalendarWatcher()

    private let store = EKEventStore()
    private var timer: Timer?
    /// "eventId|minutes" already announced, so each notice fires once.
    private var announced = Set<String>()

    func start() {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                IslaModel.shared.calendarAccess = granted
                guard granted else { return }
                self.refresh()
                NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: self.store, queue: .main) { _ in
                    MainActor.assumeIsolated { self.refresh() }
                }
                self.timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                    MainActor.assumeIsolated { self.refresh() }
                }
            }
        }
    }

    func refresh() {
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60 * 60),
                                                 end: now.addingTimeInterval(24 * 60 * 60), calendars: nil)
        let next = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .filter { ev in
                // Skip events I declined.
                !(ev.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined }
            }
            .sorted { $0.startDate < $1.startDate }
            .first { $0.startDate > now.addingTimeInterval(-5 * 60) }

        guard let ev = next else { IslaModel.shared.nextEvent = nil; return }
        let id = ev.calendarItemIdentifier + "\(ev.startDate.timeIntervalSince1970)"
        let color = ev.calendar.map { Color(nsColor: $0.color) } ?? NoticeSource.calendar.color
        IslaModel.shared.nextEvent = UpcomingEvent(id: id, title: ev.title ?? "Evento",
                                                   start: ev.startDate, end: ev.endDate,
                                                   calendarColor: color, url: ev.url)

        let minutes = ev.startDate.timeIntervalSince(now) / 60
        if minutes <= 10, minutes > 1, !announced.contains(id + "|10") {
            announced.insert(id + "|10")
            IslaModel.shared.post(Notice(source: .calendar, title: ev.title ?? "Evento",
                                         subtitle: "Empieza en \(Int(minutes.rounded())) min", duration: 10))
        }
        if minutes <= 1, minutes > -5, !announced.contains(id + "|0") {
            announced.insert(id + "|0")
            announced.insert(id + "|10")
            IslaModel.shared.post(Notice(source: .calendar, title: ev.title ?? "Evento",
                                         subtitle: "Empieza ahora", duration: 15, symbol: "calendar.badge.clock"))
        }
    }

    /// Opens the meeting link if it has one, otherwise the Calendar app.
    func open() {
        if let url = IslaModel.shared.nextEvent?.url {
            NSWorkspace.shared.open(url)
        } else if let cal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: cal, configuration: .init())
        }
    }
}
