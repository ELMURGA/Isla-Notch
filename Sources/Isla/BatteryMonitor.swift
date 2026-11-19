import Foundation
import IOKit.ps

/// Watches the battery through IOKit power-source notifications (no polling).
/// Posts a notice when the level drops to 20, 10 and 5 % on battery, and when the
/// charger is connected or disconnected.
@MainActor
final class BatteryMonitor {
    static let shared = BatteryMonitor()
    private static let thresholds = [20, 10, 5]

    private var source: CFRunLoopSource?
    private var lastCharging: Bool?
    private var warned = Set<Int>()

    static func symbol(for level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default:    return "battery.100percent"
        }
    }

    func start() {
        let callback: IOPowerSourceCallbackType = { _ in
            DispatchQueue.main.async { BatteryMonitor.shared.update() }
        }
        if let src = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            source = src
        }
        update()
    }

    private func read() -> (level: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (cur * 100 / max, onAC)
        }
        return nil
    }

    private func update() {
        guard let (level, charging) = read() else { return }
        let model = IslaModel.shared
        model.batteryLevel = level
        model.batteryCharging = charging

        if let last = lastCharging, last != charging {
            model.post(Notice(source: .battery,
                              title: charging ? "Cargando" : "Usando batería",
                              subtitle: "\(level) %",
                              duration: 3,
                              symbol: charging ? "bolt.fill" : Self.symbol(for: level)))
        }
        lastCharging = charging

        if charging {
            warned.removeAll()
            return
        }
        for t in Self.thresholds where level <= t && !warned.contains(t) {
            // Mark every threshold already passed so one drop gives one notice.
            Self.thresholds.filter { $0 >= t }.forEach { warned.insert($0) }
            model.post(Notice(source: .battery,
                              title: "Batería baja · \(level) %",
                              subtitle: t <= 5 ? "Conecta el cargador ya" : "Conecta el cargador pronto",
                              duration: t <= 10 ? 10 : 7,
                              symbol: "battery.25percent"))
            break
        }
    }
}
