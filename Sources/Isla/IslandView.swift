import SwiftUI

/// Black shape hanging from the top of the screen: flat top, rounded bottom corners,
/// with small outward curves where it meets the menu bar (like the hardware notch).
struct IslandShape: Shape {
    var bottomRadius: CGFloat
    var topFlare: CGFloat = 6

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height / 2, rect.width / 4)
        let f = topFlare
        var p = Path()
        p.move(to: CGPoint(x: rect.minX - f, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + f), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + f, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    @EnvironmentObject var model: IslaModel

    var body: some View {
        let size = IslandSize.shape(for: model)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(bottomRadius: model.state == .idle ? 10 : 22)
                    .fill(Color.black)
                content
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipped()
            }
            .frame(width: size.width, height: size.height)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.state)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.nowPlaying?.isPlaying)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.isAskingApproval)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.timer)
            Spacer(minLength: 0)
        }
        .frame(width: IslandSize.panel.width, height: IslandSize.panel.height, alignment: .top)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        if model.isAskingApproval {
            ApprovalContent()
        } else {
            switch model.state {
            case .idle:     IdleContent()
            case .alert:    AlertContent()
            case .expanded: ExpandedContent()
            }
        }
    }
}

// MARK: - Idle: what shows beside the notch while it is closed

private struct IdleContent: View {
    @EnvironmentObject var model: IslaModel

    var body: some View {
        Group {
            switch IslandSize.wings(for: model) {
            case .none:
                EmptyView()
            case .music:
                HStack {
                    Artwork(image: model.artwork, size: 20, radius: 5)
                    Spacer()
                    EqualizerBars(color: NoticeSource.music.color)
                }
            case .timer:
                if let t = model.timer {
                    HStack {
                        Image(systemName: t.kind == .rest ? "cup.and.saucer.fill" : "timer")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NoticeSource.timer.color)
                        Spacer()
                        CountdownText(to: t.end, size: 13).foregroundStyle(NoticeSource.timer.color)
                    }
                }
            case .meeting:
                if let ev = model.nextEvent {
                    HStack {
                        Image(systemName: "calendar").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NoticeSource.calendar.color)
                        Spacer()
                        MeetingCountdown(event: ev, size: 12).foregroundStyle(NoticeSource.calendar.color)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: model.notchSize.height)
        .transition(.opacity)
    }
}

// MARK: - Claude Code permission request: Allow / Deny

private struct ApprovalContent: View {
    @EnvironmentObject var model: IslaModel

    var body: some View {
        if let n = model.current, let id = n.approvalId {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    NoticeIcon(notice: n, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(n.subtitle.isEmpty ? "Claude Code" : "Claude Code · \(n.subtitle)")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                if !n.detail.isEmpty {
                    Text(n.detail)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                }
                HStack(spacing: 10) {
                    Button("Responder en la terminal") { HookServer.shared.answer(id, decision: "ask") }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    PillButton(title: "Denegar", fill: Color.white.opacity(0.14)) {
                        HookServer.shared.answer(id, decision: "deny")
                    }
                    PillButton(title: "Permitir", fill: n.source.color) {
                        HookServer.shared.answer(id, decision: "allow")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, model.notchSize.height + 8)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            .id(n.id)
        }
    }
}

// MARK: - Alert: one notice below the notch

private struct AlertContent: View {
    @EnvironmentObject var model: IslaModel

    var body: some View {
        if let n = model.current {
            HStack(spacing: 12) {
                NoticeIcon(notice: n, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !n.subtitle.isEmpty {
                        Text(n.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, model.notchSize.height + 6)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            .id(n.id)
        }
    }
}

// MARK: - Expanded: music, battery and the latest notices

private struct ExpandedContent: View {
    @EnvironmentObject var model: IslaModel

    var body: some View {
        VStack(spacing: 10) {
            // The row beside the notch: name on the left, battery on the right.
            HStack {
                Text("Isla").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                BatteryLabel()
            }
            .padding(.horizontal, 20)
            .frame(height: model.notchSize.height)

            HStack(alignment: .top, spacing: 14) {
                MusicCard()
                    .frame(width: 240)
                VStack(alignment: .leading, spacing: 10) {
                    MeetingCard()
                    NoticeList()
                }
            }
            .padding(.horizontal, 16)
            TimerBar()
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }
}

private struct MeetingCard: View {
    @EnvironmentObject var model: IslaModel

    var body: some View {
        if let ev = model.nextEvent {
            Button { CalendarWatcher.shared.open() } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(ev.calendarColor).frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ev.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(ev.start, style: .time)
                            Text("·")
                            MeetingCountdown(event: ev, size: 11)
                        }
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                    if ev.url != nil {
                        Image(systemName: "video.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if !model.calendarAccess {
            Text("Calendario sin permiso: actívalo en Ajustes del Sistema → Privacidad → Calendarios")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).lineLimit(2)
        } else {
            Label("Nada más en el calendario hoy", systemImage: "calendar")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.4))
        }
    }
}

private struct TimerBar: View {
    @EnvironmentObject var model: IslaModel

    var body: some View {
        HStack(spacing: 10) {
            if let t = model.timer {
                Image(systemName: t.kind == .rest ? "cup.and.saucer.fill" : "timer")
                    .foregroundStyle(NoticeSource.timer.color)
                Text(t.label).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let left = max(0, t.end.timeIntervalSince(ctx.date))
                    ProgressView(value: 1 - left / t.total)
                        .progressViewStyle(.linear)
                        .tint(NoticeSource.timer.color)
                }
                CountdownText(to: t.end, size: 14).foregroundStyle(.white)
                PillButton(title: "Parar", fill: Color.white.opacity(0.14)) { TimerController.shared.stop() }
            } else {
                Image(systemName: "timer").foregroundStyle(.white.opacity(0.5))
                PillButton(title: "Pomodoro 25", fill: NoticeSource.timer.color.opacity(0.85)) {
                    TimerController.shared.startPomodoro()
                }
                ForEach([5, 10, 15, 30], id: \.self) { m in
                    PillButton(title: "\(m) min", fill: Color.white.opacity(0.12)) {
                        TimerController.shared.startTimer(minutes: Double(m))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
    }
}

private struct BatteryLabel: View {
    @EnvironmentObject var model: IslaModel

    var body: some View {
        if let level = model.batteryLevel {
            HStack(spacing: 5) {
                Text("\(level) %").font(.system(size: 12, weight: .medium)).monospacedDigit()
                Image(systemName: model.batteryCharging ? "battery.100percent.bolt" : BatteryMonitor.symbol(for: level))
                    .font(.system(size: 13))
            }
            .foregroundStyle(level <= 20 && !model.batteryCharging ? Color.red : .white.opacity(0.8))
        }
    }
}

private struct MusicCard: View {
    @EnvironmentObject var model: IslaModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let np = model.nowPlaying {
                HStack(spacing: 10) {
                    Artwork(image: model.artwork, size: 48, radius: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(np.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(np.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        Text(np.player == "Music" ? "Apple Music" : "Spotify")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(NoticeSource.music.color)
                    }
                }
                HStack(spacing: 26) {
                    ControlButton(symbol: "backward.fill") { MusicController.shared.previous() }
                    ControlButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 20) { MusicController.shared.playPause() }
                    ControlButton(symbol: "forward.fill") { MusicController.shared.next() }
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 10) {
                    Artwork(image: nil, size: 48, radius: 9)
                    Text("No suena nada").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.07)))
    }
}

private struct NoticeList: View {
    @EnvironmentObject var model: IslaModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Avisos").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
            if model.history.isEmpty {
                Text("Sin avisos por ahora").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
            }
            ForEach(model.history.prefix(3)) { n in
                HStack(spacing: 8) {
                    NoticeIcon(notice: n, size: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(n.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                        if !n.subtitle.isEmpty {
                            Text(n.subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(n.date, style: .time).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Small pieces

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

struct EqualizerBars: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: 5 + 9 * abs(sin(t * (2.2 + Double(i) * 0.7) + Double(i))))
                }
            }
            .frame(height: 16)
        }
    }
}

/// Round icon of a notice. App sources show their brand logo, with the notice's own
/// symbol (permission, done, failed…) as a small badge in the corner.
struct NoticeIcon: View {
    let notice: Notice
    let size: CGFloat

    var body: some View {
        let src = notice.source
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(src.color.opacity(src.logo == nil ? 0.22 : 0.16))
                if let logo = src.logo {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size * 0.56, height: size * 0.56)
                } else {
                    Image(systemName: notice.symbol ?? src.symbol)
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(src.color)
                }
            }
            .frame(width: size, height: size)

            if src.logo != nil, let badge = notice.symbol {
                Image(systemName: badge)
                    .font(.system(size: size * 0.24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .background(Circle().fill(badgeColor(badge)))
                    .overlay(Circle().stroke(Color.black, lineWidth: max(1.5, size * 0.05)))
                    .offset(x: size * 0.08, y: size * 0.08)
            }
        }
    }

    private func badgeColor(_ symbol: String) -> Color {
        if symbol.contains("exclamation") { return Color(red: 0.95, green: 0.27, blue: 0.27) }
        if symbol.contains("checkmark") { return Color(red: 0.20, green: 0.75, blue: 0.40) }
        if symbol.contains("hand") { return Color(red: 0.98, green: 0.62, blue: 0.15) }
        return Color(white: 0.35)
    }
}

/// mm:ss counting down to a date, refreshed every half second.
struct CountdownText: View {
    let to: Date
    var size: CGFloat = 13

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            Text(TimerController.format(to.timeIntervalSince(ctx.date)))
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
        }
    }
}

/// "en 12 min", "ahora" or "en curso" for a calendar event.
struct MeetingCountdown: View {
    let event: UpcomingEvent
    var size: CGFloat = 12

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let mins = Int((event.start.timeIntervalSince(ctx.date) / 60).rounded(.up))
            Group {
                if event.start <= ctx.date { Text("en curso") }
                else if mins <= 1 { Text("ahora") }
                else if mins < 60 { Text("en \(mins) min") }
                else { Text("en \(mins / 60) h \(mins % 60) min") }
            }
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
        }
    }
}

struct PillButton: View {
    let title: String
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 15
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
