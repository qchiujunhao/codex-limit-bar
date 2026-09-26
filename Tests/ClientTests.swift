import AppKit

// The test executable also acts as an isolated JSON-RPC server. It caches the
// synthetic account at launch, reproducing the independent server's stale login.
@main
enum ClientTests {
    static let files = FileManager.default
    static var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["LIMIT_BAR_TEST_DIRECTORY"]!)
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func wait(_ message: String, timeout: TimeInterval = 5, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        check(condition(), message)
    }

    static func state(_ account: String, error: String = "", notification: String = "") throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "account": account, "error": error, "notification": notification
        ])
        try data.write(to: directory.appendingPathComponent("state.json"), options: .atomic)
    }

    static func launchCount() -> Int {
        (try? files.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("launch-") }.count) ?? 0
    }

    static func server() throws {
        let data = try Data(contentsOf: directory.appendingPathComponent("state.json"))
        let state = try JSONSerialization.jsonObject(with: data) as! [String: String]
        var account = state["account"]!
        var notification = state["notification"]!
        try Data().write(to: directory.appendingPathComponent("launch-\(ProcessInfo.processInfo.processIdentifier)"))

        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try FileHandle.standardOutput.write(contentsOf: data)
        }

        while let line = readLine() {
            let message = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            guard let id = message["id"] else { continue }
            let method = message["method"] as! String
            if (notification == "account" && method == "account/read") ||
                (notification == "limits" && method == "account/rateLimits/read") {
                notification = ""
                account = "B"
                try send(["method": "account/updated", "params": ["authMode": "chatgpt", "planType": "plus"]])
                // This late reply belongs to account A and must be ignored.
                let result: [String: Any] = method == "account/read"
                    ? ["account": ["type": "chatgpt", "email": "A@example.test", "planType": "plus"]]
                    : ["rateLimits": ["limitId": "codex", "primary": ["usedPercent": 10, "windowDurationMins": 300]]]
                try send(["id": id, "result": result])
                continue
            }
            switch method {
            case "initialize":
                try send(["id": id, "result": [:]])
            case "account/read":
                check((message["params"] as? [String: Any])?["refreshToken"] as? Bool == false,
                      "account check must not force token rotation")
                let value: Any = account.isEmpty ? NSNull() :
                    account == "api" ? ["type": "apiKey"] :
                    ["type": "chatgpt", "email": "\(account)@example.test", "planType": "plus"]
                try send(["id": id, "result": ["account": value]])
            case "account/rateLimits/read":
                if let error = state["error"], !error.isEmpty {
                    try send(["id": id, "error": ["code": -32000, "message": error]])
                } else {
                    try send(["id": id, "result": ["rateLimits": [
                        "limitId": "codex", "planType": "plus",
                        "primary": ["usedPercent": account == "A" ? 10 : 30, "windowDurationMins": 300]
                    ]]])
                }
            default:
                fatalError("Unexpected method \(method)")
            }
        }
    }

    static func main() throws {
        if CommandLine.arguments.contains("app-server") {
            try server()
            return
        }
        if CommandLine.arguments.contains("--live") {
            let client = CodexRateLimitClient()
            var received = false
            client.onSnapshot = { snapshot in
                print("Live account and rate-limit read succeeded (\(snapshot.quotaWindowsForDisplay().count) windows)")
                received = true
            }
            client.onError = { _ in fputs("Live account/rate-limit read failed\n", stderr) }
            client.start()
            wait("live snapshot", timeout: 35) { received }
            client.stop()
            return
        }

        let testDirectory = URL(fileURLWithPath: files.currentDirectoryPath)
            .appendingPathComponent("build/tests/client-\(UUID().uuidString)")
        try files.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        setenv("LIMIT_BAR_TEST_DIRECTORY", testDirectory.path, 1)
        defer { try? files.removeItem(at: testDirectory) }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).path
        var events: [String] = []
        var snapshots: [RateLimitSnapshot] = []
        let client = CodexRateLimitClient(executablePath: executable, refreshInterval: 1, reconnectDelay: 0.1)
        client.onSnapshot = {
            snapshots.append($0)
            events.append("snapshot:\(Int($0.fiveHourWindow!.remainingPercent))")
        }
        client.onSnapshotInvalidated = { events.append("clear") }
        client.onError = { _ in events.append("error") }
        defer { client.stop() }

        try state("A")
        client.start()
        wait("initial account A") { events.contains("snapshot:90") }
        let sample = snapshots[0]

        events.removeAll()
        try state("B")
        // No notification: another desktop process changed the persisted login.
        wait("automatic refresh adopts account B") { events.contains("snapshot:70") }
        check(events.firstIndex(of: "clear")! < events.firstIndex(of: "snapshot:70")!, "old account cleared before new quota")

        events.removeAll()
        try state("A")
        client.refresh()
        wait("manual refresh adopts account A") { events.contains("snapshot:90") }

        // Same-account network errors retain data, but expose the error.
        events.removeAll()
        try state("A", error: "503 service temporarily unavailable")
        client.refresh()
        wait("network error reported") { events.contains("error") }
        check(!events.contains("clear"), "same-account transient error preserves snapshot")

        events.removeAll()
        try state("A", error: "Your access token could not be refreshed because you have since logged out or signed in to another account.")
        client.refresh()
        wait("authentication failure clears old data") { events.contains("error") && events.contains("clear") }
        wait("one authentication retry") { events.filter { $0 == "error" }.count >= 2 }
        client.stop()

        // Use a long polling interval to assert the quick retry is bounded.
        let bounded = CodexRateLimitClient(executablePath: executable, refreshInterval: 30, reconnectDelay: 0.1)
        var failures = 0
        bounded.onError = { _ in failures += 1 }
        let launchesBefore = launchCount()
        bounded.start()
        wait("two failed attempts") { failures == 2 }
        let settle = Date().addingTimeInterval(0.4)
        wait("retry observation", timeout: 1) { Date() >= settle }
        check(launchCount() == launchesBefore + 2, "no rapid retry loop")
        bounded.stop()

        events.removeAll()
        try state("")
        client.start()
        wait("logout clears quota") { events.contains("clear") && events.contains("error") }
        events.removeAll()
        try state("B")
        wait("automatic recovery after login") { events.contains("snapshot:70") }

        events.removeAll()
        try state("api")
        client.refresh()
        wait("API key clears ChatGPT quota") { events.contains("clear") && events.contains("error") }
        check(!events.contains(where: { $0.hasPrefix("snapshot:") }), "no quota for API key")

        for phase in ["account", "limits"] {
            events.removeAll()
            try state("A", notification: phase)
            client.refresh()
            wait("account notification during \(phase) request") { events.contains("snapshot:70") }
            check(!events.contains("snapshot:90"), "late old-account \(phase) reply discarded")
        }
        client.stop()
        let stoppedLaunches = launchCount()
        client.refresh()
        let stoppedDeadline = Date().addingTimeInterval(1.2)
        wait("stopped client observation", timeout: 2) { Date() >= stoppedDeadline }
        check(launchCount() == stoppedLaunches, "stop cancels polling and queued retries")

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let view = LimitPopoverController(language: .english)
        view.update(snapshot: sample)
        view.updateError(.readFailed("example failure"))
        let labels = view.view.subviews.compactMap { $0 as? NSTextField }
        check(labels.contains { $0.stringValue.contains("example failure") }, "cached data must not hide detailed error")
        view.clearSnapshot()
        check(labels.contains { $0.stringValue == "Reading…" }, "popover clears old summary")
        check(!view.view.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).contains { $0 is RateWindowRowView },
              "popover clears old quota rows")
        print("ClientTests passed")
    }
}
