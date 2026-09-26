import Foundation

final class CodexRateLimitClient {
    var onSnapshot: ((RateLimitSnapshot) -> Void)?
    var onStatus: ((ClientStatus) -> Void)?
    var onError: ((ClientIssue) -> Void)?
    var onSnapshotInvalidated: (() -> Void)?

    private let queue = DispatchQueue(label: "app.codexlimitbar.client")
    private let executablePath: String?
    private let refreshInterval: TimeInterval
    private let reconnectDelay: TimeInterval
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var refreshTimer: DispatchSourceTimer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var initializeTimeoutWorkItem: DispatchWorkItem?
    private var requestTimeoutWorkItems: [Int: DispatchWorkItem] = [:]
    private var initialized = false
    private var stopped = true
    private var retriedThisRefresh = false
    private var accountVerified = false
    private var accountIdentity: Data?
    private var pendingAccountRequestID: Int?
    private var processGeneration = 0
    private var nextRequestID = 10
    private var pendingRateLimitRequestIDs = Set<Int>()

    init(executablePath: String? = nil, refreshInterval: TimeInterval = 60, reconnectDelay: TimeInterval = 5) {
        self.executablePath = executablePath
        self.refreshInterval = refreshInterval
        self.reconnectDelay = reconnectDelay
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = false
            self.startRefreshTimer()
            self.refreshConnection()
        }
    }

    func refresh() {
        queue.async { [weak self] in
            self?.refreshConnection()
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            refreshTimer?.cancel()
            refreshTimer = nil
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            invalidateCurrentProcess(terminate: true)
        }
    }

    private func refreshConnection() {
        guard !stopped else { return }
        retriedThisRefresh = false
        // A desktop account switch need not notify this independent server.
        // Restart on each refresh so Codex reloads its own file/keychain credentials.
        // ponytail: one launch per refresh; reuse needs reliable cross-process account-change detection.
        invalidateCurrentProcess(terminate: true)
        startProcessIfNeeded()
    }

    private func startProcessIfNeeded() {
        guard !stopped, process?.isRunning != true else { return }

        if process != nil {
            invalidateCurrentProcess(terminate: false)
        }

        guard let executablePath = executablePath ?? Self.findCodexExecutable() else {
            reportError(.codexNotFound)
            return
        }

        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        reportStatus(.connecting)
        initialized = false
        pendingRateLimitRequestIDs.removeAll()
        outputBuffer.removeAll(keepingCapacity: true)
        processGeneration += 1
        let generation = processGeneration

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["app-server"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existingPath = environment["PATH"], !existingPath.isEmpty {
            environment["PATH"] = existingPath + ":" + fallbackPath
        } else {
            environment["PATH"] = fallbackPath
        }
        process.environment = environment

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                guard let self, self.processGeneration == generation else { return }
                self.consumeOutput(data)
            }
        }

        // Always drain stderr so the child process cannot block. Details stay out of the UI.
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            self?.queue.async {
                self?.handleTermination(
                    process: terminatedProcess,
                    generation: generation,
                    status: terminatedProcess.terminationStatus
                )
            }
        }

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe

        do {
            try process.run()
            guard send([
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "codex_limit_bar",
                        "title": "Codex Limit Bar",
                        "version": "1.0.1"
                    ]
                ]
            ]) else {
                resetConnection(.initializationRequestFailed)
                return
            }
            scheduleInitializeTimeout(generation: generation)
        } catch {
            resetConnection(.launchFailed(error.localizedDescription))
        }
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)

        while let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer.prefix(upTo: newlineIndex)
            outputBuffer.removeSubrange(...newlineIndex)

            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let message = object as? [String: Any] else {
                continue
            }

            handleMessage(message)
        }
    }

    private func handleMessage(_ message: [String: Any]) {
        if let requestID = (message["id"] as? NSNumber)?.intValue {
            if let error = message["error"] as? [String: Any] {
                let errorMessage = (error["message"] as? String) ?? "Unknown error"
                if requestID == 1 {
                    initializeTimeoutWorkItem?.cancel()
                    initializeTimeoutWorkItem = nil
                    resetConnection(Self.classifyIssue(from: errorMessage))
                } else if pendingRateLimitRequestIDs.contains(requestID) {
                    pendingRateLimitRequestIDs.remove(requestID)
                    requestTimeoutWorkItems.removeValue(forKey: requestID)?.cancel()
                    handleRequestIssue(Self.classifyIssue(from: errorMessage))
                } else if requestID == pendingAccountRequestID {
                    pendingAccountRequestID = nil
                    requestTimeoutWorkItems.removeValue(forKey: requestID)?.cancel()
                    handleRequestIssue(Self.classifyIssue(from: errorMessage))
                }
                return
            }

            if requestID == 1 {
                initializeTimeoutWorkItem?.cancel()
                initializeTimeoutWorkItem = nil
                initialized = true
                guard send(["method": "initialized", "params": [:]]) else {
                    resetConnection(.initializationHandshakeFailed)
                    return
                }
                requestAccount()
                return
            }

            if requestID == pendingAccountRequestID {
                pendingAccountRequestID = nil
                requestTimeoutWorkItems.removeValue(forKey: requestID)?.cancel()
                guard let result = message["result"] as? [String: Any] else {
                    invalidateSnapshot()
                    reportError(.missingResponseData)
                    return
                }
                guard let account = result["account"] as? [String: Any] else {
                    handleRequestIssue(.loginRequired)
                    return
                }
                guard account["type"] as? String == "chatgpt" else {
                    invalidateSnapshot()
                    reportError(account["type"] as? String == "apiKey" ? .apiKeyUnsupported : .noQuotaWindows)
                    return
                }

                // Keep account metadata only in memory, never tokens. If the server
                // cannot identify the account, do not reuse an earlier snapshot.
                var identity: Data?
                if let email = account["email"] as? String, !email.isEmpty {
                    identity = try? JSONSerialization.data(withJSONObject: [
                        "account": account,
                        "workspaceRouting": result["workspaceRouting"] ?? NSNull()
                    ], options: .sortedKeys)
                }
                if identity == nil || identity != accountIdentity {
                    invalidateSnapshot()
                    accountIdentity = identity
                }
                accountVerified = true
                requestRateLimits()
                return
            }

            if pendingRateLimitRequestIDs.remove(requestID) != nil {
                requestTimeoutWorkItems.removeValue(forKey: requestID)?.cancel()
                do {
                    let snapshot = try RateLimitSnapshot.parse(from: message)
                    DispatchQueue.main.async { [weak self] in
                        self?.onSnapshot?(snapshot)
                    }
                } catch let parseError as RateLimitParseError {
                    switch parseError {
                    case .missingResult:
                        reportError(.missingResponseData)
                    case .missingLimits:
                        reportError(.noQuotaWindows)
                    }
                } catch {
                    reportError(.readFailed(error.localizedDescription))
                }
            }
            return
        }

        guard let method = message["method"] as? String else { return }
        if method == "account/updated" {
            cancelPendingRequests()
            invalidateSnapshot()
            requestAccount()
        } else if method == "account/rateLimits/updated" {
            // Update notifications can be sparse. Re-read the full snapshot instead of
            // accidentally treating omitted windows or metadata as deleted.
            requestRateLimits()
        }
    }

    private func requestAccount() {
        guard initialized, pendingAccountRequestID == nil else { return }
        let requestID = nextRequestID
        nextRequestID += 1
        pendingAccountRequestID = requestID
        guard send(["method": "account/read", "id": requestID, "params": ["refreshToken": false]]) else {
            resetConnection(.rateLimitRequestFailed)
            return
        }
        scheduleRequestTimeout(requestID: requestID, generation: processGeneration)
    }

    private func requestRateLimits() {
        guard initialized, accountVerified, pendingAccountRequestID == nil,
              pendingRateLimitRequestIDs.isEmpty else { return }
        let requestID = nextRequestID
        nextRequestID += 1
        pendingRateLimitRequestIDs.insert(requestID)
        reportStatus(.refreshing)
        guard send(["method": "account/rateLimits/read", "id": requestID]) else {
            pendingRateLimitRequestIDs.remove(requestID)
            resetConnection(.rateLimitRequestFailed)
            return
        }
        scheduleRequestTimeout(requestID: requestID, generation: processGeneration)
    }

    private func startRefreshTimer() {
        refreshTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        timer.setEventHandler { [weak self] in
            self?.refreshConnection()
        }
        refreshTimer = timer
        timer.resume()
    }

    @discardableResult
    private func send(_ message: [String: Any]) -> Bool {
        guard JSONSerialization.isValidJSONObject(message),
              var data = try? JSONSerialization.data(withJSONObject: message) else {
            return false
        }
        data.append(0x0A)

        guard let handle = inputPipe?.fileHandleForWriting else {
            return false
        }

        do {
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    private func scheduleInitializeTimeout(generation: Int) {
        initializeTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.initialized,
                  self.processGeneration == generation else { return }
            self.resetConnection(.initializationTimedOut)
        }
        initializeTimeoutWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 12, execute: workItem)
    }

    private func scheduleRequestTimeout(requestID: Int, generation: Int) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.processGeneration == generation,
                  self.pendingRateLimitRequestIDs.contains(requestID) || self.pendingAccountRequestID == requestID else { return }
            self.resetConnection(.rateLimitTimedOut)
        }
        requestTimeoutWorkItems[requestID] = workItem
        queue.asyncAfter(deadline: .now() + 15, execute: workItem)
    }

    private func handleTermination(process terminatedProcess: Process, generation: Int, status: Int32) {
        guard processGeneration == generation, process === terminatedProcess else { return }
        let shouldRestart = !stopped
        invalidateCurrentProcess(terminate: false)

        guard shouldRestart else { return }
        reportError(status == 0 ? .serverStopped : .serverExited(status))
        scheduleReconnect()
    }

    private func resetConnection(_ issue: ClientIssue) {
        guard !stopped else { return }
        if !accountVerified { invalidateSnapshot() }
        reportError(issue)
        invalidateCurrentProcess(terminate: true)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        // One quick retry per refresh cycle; the regular timer keeps checking
        // after logout or persistent failures without a rapid restart loop.
        guard !stopped, !retriedThisRefresh else { return }
        retriedThisRefresh = true
        reconnectWorkItem?.cancel()
        let generation = processGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, self.processGeneration == generation else { return }
            self.reconnectWorkItem = nil
            self.startProcessIfNeeded()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + reconnectDelay, execute: workItem)
    }

    private func handleRequestIssue(_ issue: ClientIssue) {
        switch issue {
        case .loginRequired:
            accountVerified = false
            resetConnection(issue)
        case .apiKeyUnsupported:
            invalidateSnapshot()
            reportError(issue)
        default:
            if !accountVerified { invalidateSnapshot() }
            reportError(issue)
        }
    }

    private func invalidateSnapshot() {
        accountIdentity = nil
        accountVerified = false
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshotInvalidated?()
        }
    }

    private func cancelPendingRequests() {
        for workItem in requestTimeoutWorkItems.values { workItem.cancel() }
        requestTimeoutWorkItems.removeAll()
        pendingAccountRequestID = nil
        pendingRateLimitRequestIDs.removeAll()
    }

    private func invalidateCurrentProcess(terminate: Bool) {
        let oldProcess = process
        processGeneration += 1

        initializeTimeoutWorkItem?.cancel()
        initializeTimeoutWorkItem = nil
        cancelPendingRequests()
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        inputPipe?.fileHandleForWriting.closeFile()
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        initialized = false
        accountVerified = false
        outputBuffer.removeAll(keepingCapacity: true)

        if terminate, oldProcess?.isRunning == true {
            oldProcess?.terminate()
        }
    }

    private func reportStatus(_ status: ClientStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(status)
        }
    }

    private func reportError(_ issue: ClientIssue) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(issue)
        }
    }

    private static func findCodexExecutable() -> String? {
        var candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        candidates.append(contentsOf: [
            home + "/.local/bin/codex",
            home + "/bin/codex"
        ])

        if let pathValue = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: pathValue.split(separator: ":").map { String($0) + "/codex" })
        }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func classifyIssue(from rawMessage: String) -> ClientIssue {
        let lowercased = rawMessage.lowercased()
        if lowercased.contains("not logged in") ||
           lowercased.contains("unauthorized") ||
           lowercased.contains("authentication") ||
           lowercased.contains("401") ||
           lowercased.contains("refresh token") ||
           lowercased.contains("refresh_token") ||
           lowercased.contains("access token") ||
           lowercased.contains("logged out") ||
           lowercased.contains("sign in again") {
            return .loginRequired
        }
        if lowercased.contains("api key") {
            return .apiKeyUnsupported
        }
        return .readFailed(rawMessage)
    }
}
