import Foundation
import Security

/// Stores small secrets (the n8n API key) in the login Keychain.
enum Keychain {
    private static let service = "com.dazenty.isla"

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Asks n8n every minute for finished executions and posts a notice for each new
/// failure (and, if enabled, for each success). The first poll only remembers where
/// it is, so old executions never fire.
final class N8nPoller: @unchecked Sendable {
    static let shared = N8nPoller()

    static let urlKey = "n8n-url"
    static let apiKeyKey = "n8n-api-key"
    static let notifySuccessDefault = "n8nNotifySuccess"
    static let defaultURL = ""

    private var timer: DispatchSourceTimer?
    private var lastSeenId = 0
    private var workflowNames: [String: String] = [:]
    private var lastSuccessNotice: [String: Date] = [:]
    private let queue = DispatchQueue(label: "isla.n8n")

    var isConfigured: Bool { Keychain.get(Self.apiKeyKey) != nil }

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 60, leeway: .seconds(5))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    /// Forget the position after the settings change, then poll again.
    func restart() {
        queue.async {
            self.lastSeenId = 0
            self.workflowNames = [:]
            self.poll()
        }
    }

    private var base: String {
        (Keychain.get(Self.urlKey) ?? Self.defaultURL).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    private func request(_ path: String, apiKey: String) -> URLRequest? {
        guard let url = URL(string: base + path) else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 15)
        r.setValue(apiKey, forHTTPHeaderField: "X-N8N-API-KEY")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    /// Checks the URL and key; the result is a short sentence for the settings window.
    func test(completion: @escaping @Sendable (String) -> Void) {
        guard let key = Keychain.get(Self.apiKeyKey), let req = request("/api/v1/executions?limit=1", apiKey: key) else {
            completion("Falta la API key.")
            return
        }
        URLSession.shared.dataTask(with: req) { _, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let err { completion("No conecta: \(err.localizedDescription)") }
            else if code == 200 { completion("Conectado con n8n.") }
            else if code == 401 { completion("La API key no es válida (401).") }
            else { completion("n8n respondió \(code).") }
        }.resume()
    }

    private func poll() {
        guard let key = Keychain.get(Self.apiKeyKey),
              let req = request("/api/v1/executions?limit=20&includeData=false", apiKey: key) else { return }
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            guard let self, (resp as? HTTPURLResponse)?.statusCode == 200, let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = obj["data"] as? [[String: Any]] else { return }
            self.queue.async { self.process(items, apiKey: key) }
        }.resume()
    }

    private static func intId(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s) ?? 0 }
        return 0
    }

    private func process(_ items: [[String: Any]], apiKey: String) {
        let finished = items.filter { ["success", "error", "crashed"].contains($0["status"] as? String ?? "") }
        let maxId = finished.map { Self.intId($0["id"]) }.max() ?? 0
        if lastSeenId == 0 {
            lastSeenId = maxId
            return
        }
        let notifySuccess = UserDefaults.standard.bool(forKey: Self.notifySuccessDefault)
        let fresh = finished.filter { Self.intId($0["id"]) > lastSeenId }.sorted { Self.intId($0["id"]) < Self.intId($1["id"]) }
        lastSeenId = max(lastSeenId, maxId)

        for item in fresh {
            let status = item["status"] as? String ?? ""
            let failed = status != "success"
            let wfId = (item["workflowId"] as? String) ?? "\(Self.intId(item["workflowId"]))"
            if !failed {
                guard notifySuccess else { continue }
                // Runs started by a schedule ("Cada minuto", "Cada hora"…) are routine checks:
                // a queue that looks every minute would fill the island. Only runs started
                // by something real (webhook, Telegram, a form, a manual run) are announced.
                if (item["mode"] as? String) == "trigger" { continue }
                // At most one success notice per workflow every 10 minutes.
                if let last = lastSuccessNotice[wfId], Date().timeIntervalSince(last) < 600 { continue }
                lastSuccessNotice[wfId] = Date()
            }
            workflowName(wfId, apiKey: apiKey) { name in
                DispatchQueue.main.async {
                    IslaModel.shared.post(Notice(
                        source: .n8n,
                        title: failed ? "Ha fallado un flujo de n8n" : "Flujo de n8n completado",
                        subtitle: name,
                        duration: failed ? 10 : 5,
                        symbol: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                }
            }
        }
    }

    private func workflowName(_ id: String, apiKey: String, completion: @escaping @Sendable (String) -> Void) {
        if let cached = workflowNames[id] { completion(cached); return }
        guard let req = request("/api/v1/workflows/\(id)", apiKey: apiKey) else { completion("Flujo \(id)"); return }
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let name = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["name"] as? String ?? "Flujo \(id)"
            self?.queue.async { self?.workflowNames[id] = name }
            completion(name)
        }.resume()
    }
}
