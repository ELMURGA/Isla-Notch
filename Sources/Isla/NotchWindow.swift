import AppKit
import SwiftUI
import Combine

/// Borderless panel that sits over the menu bar, centred on the notch.
/// Same approach as Coucou (MIT): non-activating, above the menu bar, on every Space.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Keep macOS from pushing the panel below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

enum NotchGeometry {
    /// The built-in screen with a notch, or the main screen.
    static var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Notch size in points. On a screen without notch, a small pill under the menu bar.
    static func notchSize(on screen: NSScreen) -> CGSize {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea?.width, let right = screen.auxiliaryTopRightArea?.width {
            return CGSize(width: screen.frame.width - left - right, height: top)
        }
        return CGSize(width: 180, height: NSStatusBar.system.thickness)
    }
}

/// Sizes of the island in each state (points).
enum IslandSize {
    static let panel = CGSize(width: 700, height: 340)
    static let alertWidth: CGFloat = 400
    static let alertExtra: CGFloat = 58
    static let approvalWidth: CGFloat = 470
    static let approvalExtra: CGFloat = 128
    static let expandedWidth: CGFloat = 600
    static let expandedExtra: CGFloat = 236
    static let musicWing: CGFloat = 34
    static let textWing: CGFloat = 64

    /// What the closed island shows beside the notch, most important first.
    enum Wings { case none, timer, meeting, music }

    @MainActor
    static func wings(for model: IslaModel) -> Wings {
        if model.timer != nil { return .timer }
        if let ev = model.nextEvent, ev.start.timeIntervalSinceNow < 15 * 60, ev.end > Date() { return .meeting }
        if model.nowPlaying?.isPlaying == true { return .music }
        return .none
    }

    @MainActor
    static func shape(for model: IslaModel) -> CGSize {
        let n = model.notchSize
        if model.isAskingApproval {
            return CGSize(width: approvalWidth, height: n.height + approvalExtra)
        }
        switch model.state {
        case .idle:
            switch wings(for: model) {
            case .none:  return n
            case .music: return CGSize(width: n.width + musicWing * 2, height: n.height)
            case .timer, .meeting: return CGSize(width: n.width + textWing * 2, height: n.height)
            }
        case .alert:
            return CGSize(width: max(alertWidth, n.width + 120), height: n.height + alertExtra)
        case .expanded:
            return CGSize(width: expandedWidth, height: n.height + expandedExtra)
        }
    }
}

@MainActor
final class NotchWindowController {
    private let panel: NotchPanel
    private let model = IslaModel.shared
    private var mouseTimer: Timer?
    private var collapseWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()

    init() {
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: IslandSize.panel),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isMovable = false

        let host = NSHostingView(rootView: IslandView().environmentObject(model))
        host.frame = NSRect(origin: .zero, size: IslandSize.panel)
        panel.contentView = host

        place()
        panel.orderFrontRegardless()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.place() }
            .store(in: &bag)

        // Accept clicks only while the island is open, so the menu bar keeps working.
        model.$state
            .sink { [weak self] state in self?.panel.ignoresMouseEvents = (state == .idle) }
            .store(in: &bag)

        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }
    }

    private func place() {
        guard let screen = NotchGeometry.screen else { return }
        model.notchSize = NotchGeometry.notchSize(on: screen)
        let size = IslandSize.panel
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// The island's current rectangle in screen coordinates.
    private func islandRect() -> NSRect {
        guard let screen = NotchGeometry.screen else { return .zero }
        let s = IslandSize.shape(for: model)
        return NSRect(x: screen.frame.midX - s.width / 2, y: screen.frame.maxY - s.height,
                      width: s.width, height: s.height)
    }

    private func trackMouse() {
        let p = NSEvent.mouseLocation
        let inside = islandRect().insetBy(dx: -6, dy: -2).contains(p)
        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if model.state != .expanded {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.state = .expanded }
            }
        } else if model.state == .expanded, collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.collapseWork = nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    self.model.state = self.model.current == nil ? .idle : .alert
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }
}
