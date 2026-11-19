import AppKit
import SwiftUI
import ServiceManagement

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // no Dock icon
        app.run()
    }

    private var notch: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchWindowController()
        HookServer.shared.start()
        BatteryMonitor.shared.start()
        MusicController.shared.start()
        N8nPoller.shared.start()
        CalendarWatcher.shared.start()
        buildStatusItem()
        buildEditMenu()

        IslaModel.shared.post(Notice(source: .custom, title: "Isla está activa",
                                     subtitle: "Pasa el ratón por el notch", duration: 3, symbol: "sparkles"))
    }

    /// An app without a Dock icon has no menu bar of its own, and without an Edit menu
    /// ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z do nothing in text fields. This menu is never shown.
    private func buildEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edición")
        edit.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Cerrar ventana", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: - Menu bar icon

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Isla")
        let menu = NSMenu()
        menu.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Probar un aviso", action: #selector(testNotice), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de Isla", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func testNotice() {
        IslaModel.shared.post(Notice(source: .custom, title: "Prueba de Isla",
                                     subtitle: "Este es un aviso de ejemplo", duration: 5))
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Ajustes de Isla"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @State private var n8nURL = Keychain.get(N8nPoller.urlKey) ?? N8nPoller.defaultURL
    @State private var apiKey = Keychain.get(N8nPoller.apiKeyKey) ?? ""
    @AppStorage(N8nPoller.notifySuccessDefault) private var notifySuccess = false
    @State private var n8nStatus = ""
    @State private var claudeInstalled = ClaudeHooksInstaller.isInstalled
    @State private var claudeStatus = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Claude Code") {
                HStack {
                    Text(claudeInstalled ? "Avisos instalados" : "Avisos sin instalar")
                    Spacer()
                    Button(claudeInstalled ? "Quitar" : "Instalar avisos") {
                        do {
                            if claudeInstalled { try ClaudeHooksInstaller.uninstall() } else { try ClaudeHooksInstaller.install() }
                            claudeInstalled = ClaudeHooksInstaller.isInstalled
                            claudeStatus = claudeInstalled
                                ? "Listo. Se aplica a las sesiones de Claude Code que abras a partir de ahora."
                                : "Quitados. Copia de seguridad junto a settings.json."
                        } catch {
                            claudeStatus = error.localizedDescription
                        }
                    }
                }
                Text("Añade los hooks Notification y Stop a ~/.claude/settings.json (con copia de seguridad).")
                    .font(.caption).foregroundStyle(.secondary)
                if !claudeStatus.isEmpty { Text(claudeStatus).font(.caption) }
            }

            Section("n8n") {
                TextField("URL", text: $n8nURL)
                HStack {
                    SecureField("API key", text: $apiKey)
                    Button("Pegar") {
                        if let text = NSPasteboard.general.string(forType: .string) {
                            apiKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                if !apiKey.isEmpty {
                    Text("Clave puesta (\(apiKey.count) caracteres, termina en …\(String(apiKey.suffix(4))))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Avisar también cuando un flujo termine bien", isOn: $notifySuccess)
                Text("Sin contar los que se lanzan solos por horario (cada minuto, cada hora…), y como mucho uno por flujo cada 10 minutos.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Guardar y probar") {
                        Keychain.set(N8nPoller.urlKey, n8nURL)
                        Keychain.set(N8nPoller.apiKeyKey, apiKey)
                        n8nStatus = "Probando…"
                        N8nPoller.shared.test { result in DispatchQueue.main.async { n8nStatus = result } }
                        N8nPoller.shared.restart()
                    }
                    Text(n8nStatus).font(.caption)
                }
                Text("Introduce la URL de tu instancia. La key se guarda en el Llavero. En n8n: Settings → n8n API → Create an API key.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Abrir Isla al iniciar sesión", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }
}
