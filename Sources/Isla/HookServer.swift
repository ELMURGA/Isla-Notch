import Foundation
import Darwin

/// Local Unix socket that receives one JSON line per event:
///   {"event": "Stop", "payload": {...Claude Code hook input...}}
/// Same design as Coucou's HookServer (MIT): private folder (0700), socket only for the
/// owner (0600), connections from other users rejected, size and time limits.
final class HookServer: @unchecked Sendable {
    static let shared = HookServer()

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Isla")
    }
    static var socketPath: String { supportDir.appendingPathComponent("isla.sock").path }
    static var hookScriptPath: String { supportDir.appendingPathComponent("isla-hook").path }
    static var notifyScriptPath: String { supportDir.appendingPathComponent("isla-notify").path }
    static var permissionScriptPath: String { supportDir.appendingPathComponent("isla-permission").path }

    private static let maxPayload = 256 * 1024

    func start() {
        let dir = Self.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        installScripts()
        Thread.detachNewThread { self.serve() }
    }

    // MARK: - Scripts Claude Code (and anything else) calls

    private func installScripts() {
        // Reads the hook input from stdin and forwards it. Always exits 0 and never
        // waits more than a second, so Claude Code is never blocked if Isla is closed.
        let hook = """
        #!/bin/sh
        SOCK="$HOME/Library/Application Support/Isla/isla.sock"
        PAYLOAD=$(cat)
        [ -S "$SOCK" ] || exit 0
        [ -n "$PAYLOAD" ] || PAYLOAD='{}'
        printf '{"event":"%s","payload":%s}\\n' "${1:-unknown}" "$PAYLOAD" | /usr/bin/nc -U -w 1 "$SOCK" >/dev/null 2>&1
        exit 0

        """
        // isla-notify [--source custom|vscode|chatgpt] "Título" "Texto".
        let notify = """
        #!/bin/sh
        SOCK="$HOME/Library/Application Support/Isla/isla.sock"
        [ -S "$SOCK" ] || exit 0
        SOURCE=custom
        if [ "${1:-}" = "--source" ]; then
            SOURCE="${2:-custom}"
            shift 2
        fi
        /usr/bin/python3 -c 'import json,sys; print(json.dumps({"event":"Notify","payload":{"source":sys.argv[1],"title":sys.argv[2],"message":sys.argv[3] if len(sys.argv)>3 else ""}}))' "$SOURCE" "${1:-Aviso}" "${2:-}" | /usr/bin/nc -U -w 1 "$SOCK" >/dev/null 2>&1
        exit 0

        """
        // isla-permission: waits for Allow / Deny in the notch and gives Claude Code the
        // answer. Isla closed, no answer or any error: prints nothing, so Claude Code asks
        // in the terminal as usual.
        let permission = """
        #!/usr/bin/python3
        import json, os, socket, sys
        sock = os.path.expanduser("~/Library/Application Support/Isla/isla.sock")
        try:
            payload = json.load(sys.stdin)
        except Exception:
            sys.exit(0)
        if not os.path.exists(sock):
            sys.exit(0)
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(115)
            s.connect(sock)
            s.sendall((json.dumps({"event": "PermissionRequest", "payload": payload}) + "\\n").encode())
            data = b""
            while b"\\n" not in data:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
            s.close()
            decision = json.loads(data.decode().strip() or "{}").get("decision", "")
        except Exception:
            sys.exit(0)
        if decision == "allow":
            out = {"behavior": "allow"}
        elif decision == "deny":
            out = {"behavior": "deny", "message": "Denegado desde el notch (Isla)"}
        else:
            sys.exit(0)
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": out}}))

        """
        for (path, text) in [(Self.hookScriptPath, hook), (Self.notifyScriptPath, notify),
                             (Self.permissionScriptPath, permission)] {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
    }

    // MARK: - Socket

    private func serve() {
        let path = Self.socketPath
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = UInt8(bitPattern: b) }
        }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else { close(fd); return }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else { close(fd); return }

        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EBADF || errno == EINVAL { break }
                continue
            }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { close(client); continue }
            Thread.detachNewThread { self.handle(client) }
        }
    }

    private func handle(_ fd: Int32) {
        var keepOpen = false
        defer { if !keepOpen { close(fd) } }
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        read: while data.count < Self.maxPayload {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            for i in 0..<n {
                if buf[i] == UInt8(ascii: "\n") { break read }
                data.append(buf[i])
            }
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = obj["event"] as? String else { return }
        let payload = obj["payload"] as? [String: Any] ?? [:]
        if event == "PermissionRequest" {
            keepOpen = holdApproval(fd: fd, payload: payload)
            return
        }
        DispatchQueue.main.async { IslaEvents.handle(event: event, payload: payload) }
    }

    // MARK: - Permission requests (Allow / Deny from the notch)

    /// Requests waiting for a click: the socket stays open until it is answered.
    private var waiting: [UUID: Int32] = [:]
    private let waitingLock = NSLock()
    /// Seconds before Isla gives the request back to the terminal (the hook allows 120).
    private static let approvalTimeout: TimeInterval = 110

    /// Returns true when the connection is kept open for an answer.
    private func holdApproval(fd: Int32, payload: [String: Any]) -> Bool {
        let tool = payload["tool_name"] as? String ?? "una herramienta"
        // Questions and plans need the terminal: answer "ask" straight away.
        if tool == "AskUserQuestion" || tool == "ExitPlanMode" {
            send(fd: fd, decision: "ask")
            return false
        }
        let id = UUID()
        waitingLock.lock(); waiting[id] = fd; waitingLock.unlock()

        let input = payload["tool_input"] as? [String: Any] ?? [:]
        let detail = (input["command"] as? String)
            ?? (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? (input["url"] as? String)
            ?? (input["pattern"] as? String)
            ?? ""
        let project = (payload["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        DispatchQueue.main.async {
            IslaModel.shared.post(Notice(source: .claude,
                                         title: "Claude quiere usar \(IslaEvents.toolName(tool))",
                                         subtitle: project,
                                         duration: Self.approvalTimeout,
                                         symbol: "hand.raised.fill",
                                         approvalId: id,
                                         detail: detail))
        }
        // Nobody answered in time: hand it back to the terminal.
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.approvalTimeout) { [weak self] in
            self?.answer(id, decision: "ask")
        }
        return true
    }

    /// decision: "allow", "deny" or "ask" (let Claude Code ask in the terminal).
    func answer(_ id: UUID, decision: String) {
        waitingLock.lock()
        let fd = waiting.removeValue(forKey: id)
        waitingLock.unlock()
        guard let fd else { return }
        send(fd: fd, decision: decision)
        close(fd)
        DispatchQueue.main.async { IslaModel.shared.removeApproval(id) }
    }

    private func send(fd: Int32, decision: String) {
        let line = "{\"decision\":\"\(decision)\"}\n"
        _ = line.withCString { Darwin.send(fd, $0, strlen($0), 0) }
    }
}

/// Turns Claude Code hook events and source-tagged local messages into notices.
@MainActor
enum IslaEvents {
    /// Claude Code tool names in plain Spanish.
    nonisolated static func toolName(_ tool: String) -> String {
        switch tool {
        case "Bash": return "la terminal"
        case "Edit", "MultiEdit": return "editar un archivo"
        case "Write": return "crear un archivo"
        case "Read": return "leer un archivo"
        case "WebFetch": return "abrir una web"
        case "WebSearch": return "buscar en internet"
        default: return tool.hasPrefix("mcp__") ? "una herramienta externa" : tool
        }
    }

    static func handle(event: String, payload: [String: Any]) {
        let project = (payload["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        switch event {
        case "Notification":
            let message = payload["message"] as? String ?? ""
            let type = payload["notification_type"] as? String ?? ""
            if type == "permission_prompt" || message.localizedCaseInsensitiveContains("permission") {
                IslaModel.shared.post(Notice(source: .claude, title: "Claude necesita tu permiso",
                                             subtitle: project.isEmpty ? message : project, duration: 12,
                                             symbol: "hand.raised.fill"))
            } else if type == "idle_prompt" || message.localizedCaseInsensitiveContains("waiting") {
                IslaModel.shared.post(Notice(source: .claude, title: "Claude te está esperando",
                                             subtitle: project, duration: 8, symbol: "ellipsis.bubble.fill"))
            } else {
                IslaModel.shared.post(Notice(source: .claude, title: "Claude", subtitle: message, duration: 6))
            }
        case "Stop":
            IslaModel.shared.post(Notice(source: .claude, title: "Claude ha terminado",
                                         subtitle: project, duration: 5, symbol: "checkmark.circle.fill"))
        case "Notify":
            let source = (payload["source"] as? String).flatMap { NoticeSource(rawValue: $0) } ?? .custom
            let title = payload["title"] as? String ?? "Aviso"
            let message = payload["message"] as? String ?? ""
            IslaModel.shared.post(Notice(source: source, title: title, subtitle: message, duration: 6))
        default:
            break
        }
    }
}
