import Darwin
import Foundation
import os

enum IPCEvent {
    case idle
    case searching
    case connected(DiscordUser)
    case disconnected(String)
    case activityError(String)
}

enum IPCError: LocalizedError {
    case notConnected
    case timeout
    case closed
    case badFrame
    case pathTooLong
    case discord(String)
    case encoding

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Open Discord and sign in on this Mac. Rich Presence only works while the Discord desktop app is running."
        case .timeout:
            return "Discord didn’t answer the status update. Check that the desktop app is still signed in."
        case .closed:
            return "Discord closed the connection."
        case .badFrame:
            return "Discord sent an unexpected response."
        case .pathTooLong:
            return "The Discord socket path is too long to open."
        case .discord(let message):
            return "Discord rejected this activity: \(message)"
        case .encoding:
            return "Couldn’t build the status payload."
        }
    }
}

/// Discord local RPC: an 8-byte little-endian header (opcode, length) followed by JSON.
/// Opcodes: 0 handshake, 1 frame, 2 close, 3 ping, 4 pong.
final class DiscordIPCClient: @unchecked Sendable {
    var eventHandler: ((IPCEvent) -> Void)?

    private let log = Logger(subsystem: "com.discordstatus.modifier", category: "ipc")
    private let stateLock = NSLock()
    private let writeLock = NSLock()
    private let wake = DispatchSemaphore(value: 0)
    private var clientID: String?
    private var fd: Int32 = -1
    private var stop = false
    private var thread: Thread?
    private var pending: [String: (Result<[String: Any], Error>) -> Void] = [:]
    private var pingTimer: DispatchSourceTimer?

    func setClientID(_ rawID: String?) {
        let trimmed = rawID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (trimmed?.isEmpty == false) ? trimmed : nil
        stateLock.lock()
        clientID = next
        stateLock.unlock()
        closeCurrentSocket()
        wake.signal()
        startThreadIfNeeded()
    }

    /// Sends SET_ACTIVITY and returns the activity Discord confirmed.
    func setActivity(_ activity: [String: Any]) async throws -> [String: Any] {
        try await sendFrame(activity: activity)
    }

    func clearActivity() async throws {
        _ = try await sendFrame(activity: nil)
    }

    /// Writes a null activity and a close frame before the process exits.
    func shutdownClearingActivity() {
        stateLock.lock()
        stop = true
        let current = fd
        stateLock.unlock()
        wake.signal()
        guard current >= 0 else {
            closeCurrentSocket()
            return
        }
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let body: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": pid,
                "activity": NSNull()
            ],
            "nonce": UUID().uuidString.lowercased()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            try? writeFrame(fd: current, opcode: 1, payload: data)
        }
        if let closePayload = "{}".data(using: .utf8) {
            try? writeFrame(fd: current, opcode: 2, payload: closePayload)
        }
        Thread.sleep(forTimeInterval: 0.2)
        closeCurrentSocket()
    }

    @discardableResult
    private func sendFrame(activity: [String: Any]?) async throws -> [String: Any] {
        let current = currentFD()
        guard current >= 0 else { throw IPCError.notConnected }
        let nonce = UUID().uuidString.lowercased()
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        var args: [String: Any] = ["pid": pid]
        if let activity {
            args["activity"] = activity
        } else {
            args["activity"] = NSNull()
        }
        let body: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": args,
            "nonce": nonce
        ]
        let payload: Data
        do {
            payload = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw IPCError.encoding
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            stateLock.lock()
            pending[nonce] = { result in
                continuation.resume(with: result)
            }
            stateLock.unlock()

            do {
                try writeFrame(fd: current, opcode: 1, payload: payload)
            } catch {
                failPending(nonce: nonce, error: error)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.failPending(nonce: nonce, error: IPCError.timeout)
            }
        }
    }

    private func failPending(nonce: String, error: Error) {
        stateLock.lock()
        let callback = pending.removeValue(forKey: nonce)
        stateLock.unlock()
        callback?(.failure(error))
    }

    private func startThreadIfNeeded() {
        stateLock.lock()
        if thread != nil {
            stateLock.unlock()
            return
        }
        let created = Thread { [weak self] in
            self?.run()
        }
        created.name = "Discord IPC"
        thread = created
        stateLock.unlock()
        created.start()
    }

    private func run() {
        var delay: TimeInterval = 0.5
        while !isStopped {
            guard let id = currentClientID() else {
                emit(.idle)
                interruptibleSleep(0.4)
                continue
            }
            emit(.searching)
            do {
                let user = try connectAndHandshake(clientID: id)
                if currentClientID() != id || isStopped {
                    closeCurrentSocket()
                    continue
                }
                delay = 0.5
                emit(.connected(user))
                startPings()
                let current = currentFD()
                if current >= 0 {
                    readFrames(fd: current)
                }
                stopPings()
                closeCurrentSocket()
                if !isStopped, currentClientID() != nil {
                    emit(.disconnected(message(for: ConnectFailure.discordNotRunning)))
                }
            } catch {
                stopPings()
                closeCurrentSocket()
                if let failure = error as? ConnectFailure, case .superseded = failure {
                    delay = 0.2
                } else {
                    emit(.disconnected(message(for: error)))
                }
            }
            if isStopped { break }
            interruptibleSleep(delay)
            delay = min(delay * 2, 15)
        }
    }

    private func connectAndHandshake(clientID: String) throws -> DiscordUser {
        let sockets = SocketLocator.existingSockets()
        if sockets.isEmpty {
            throw ConnectFailure.discordNotRunning
        }
        var rejection: String?
        for path in sockets {
            if isStopped || currentClientID() != clientID {
                throw ConnectFailure.superseded
            }
            do {
                let socketFD = try connectUnix(path: path, timeoutMilliseconds: 500)
                storeFD(socketFD)
                do {
                    let user = try performHandshake(fd: socketFD, clientID: clientID)
                    log.info("Connected to Discord IPC at \(path, privacy: .public)")
                    return user
                } catch {
                    closeCurrentSocket()
                    if case let IPCError.discord(message) = error {
                        rejection = message
                    }
                }
            } catch {
                continue
            }
        }
        if isStopped || currentClientID() != clientID {
            throw ConnectFailure.superseded
        }
        if let rejection {
            throw ConnectFailure.rejected(rejection)
        }
        throw ConnectFailure.discordNotRunning
    }

    private func performHandshake(fd: Int32, clientID: String) throws -> DiscordUser {
        let hello = try JSONSerialization.data(withJSONObject: [
            "v": 1,
            "client_id": clientID
        ])
        try writeFrame(fd: fd, opcode: 0, payload: hello)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let remaining = max(Int32(deadline.timeIntervalSinceNow * 1000), 1)
            let frame = try readFrame(fd: fd, timeoutMilliseconds: remaining)
            switch frame.opcode {
            case 3:
                try writeFrame(fd: fd, opcode: 4, payload: frame.payload)
            case 2:
                throw IPCError.closed
            case 1:
                guard let json = jsonObject(frame.payload) else { continue }
                if let user = parseReady(json) {
                    return user
                }
                if let message = discordError(json) {
                    throw IPCError.discord(message)
                }
            default:
                break
            }
        }
        throw IPCError.timeout
    }

    private func readFrames(fd socketFD: Int32) {
        while !isStopped && currentFD() == socketFD {
            do {
                let frame = try readFrame(fd: socketFD, timeoutMilliseconds: nil)
                switch frame.opcode {
                case 3:
                    try writeFrame(fd: socketFD, opcode: 4, payload: frame.payload)
                case 2:
                    return
                case 1:
                    guard let json = jsonObject(frame.payload) else { continue }
                    if let user = parseReady(json) {
                        emit(.connected(user))
                    }
                    resolve(json)
                default:
                    break
                }
            } catch {
                return
            }
        }
    }

    private func resolve(_ json: [String: Any]) {
        guard let nonce = json["nonce"] as? String else {
            if let message = discordError(json) {
                emit(.activityError("Discord rejected this activity: \(message)"))
            }
            return
        }
        stateLock.lock()
        let callback = pending.removeValue(forKey: nonce)
        stateLock.unlock()
        guard let callback else { return }
        if let message = discordError(json) {
            callback(.failure(IPCError.discord(message)))
        } else if let data = json["data"] as? [String: Any] {
            callback(.success(data))
        } else {
            callback(.success([:]))
        }
    }

    private func startPings() {
        stopPings()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 20, repeating: 20)
        timer.setEventHandler { [weak self] in
            self?.sendPing()
        }
        timer.resume()
        pingTimer = timer
    }

    private func stopPings() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    private func sendPing() {
        let current = currentFD()
        guard current >= 0 else { return }
        let payload = "{}".data(using: .utf8) ?? Data()
        do {
            try writeFrame(fd: current, opcode: 3, payload: payload)
        } catch {
            closeCurrentSocket()
        }
    }

    private func message(for error: Error) -> String {
        if let failure = error as? ConnectFailure {
            switch failure {
            case .discordNotRunning:
                return "Open Discord and sign in on this Mac. Rich Presence only works while the Discord desktop app is running."
            case .rejected(let message):
                return "Discord rejected the connection. \(message)"
            case .superseded:
                return "Open Discord and sign in on this Mac. Rich Presence only works while the Discord desktop app is running."
            }
        }
        return "Open Discord and sign in on this Mac. Rich Presence only works while the Discord desktop app is running."
    }

    private func emit(_ event: IPCEvent) {
        let handler = eventHandler
        DispatchQueue.main.async {
            handler?(event)
        }
    }

    private func currentClientID() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return clientID
    }

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stop
    }

    private func currentFD() -> Int32 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return fd
    }

    private func storeFD(_ newFD: Int32) {
        stateLock.lock()
        let previous = fd
        fd = newFD
        stateLock.unlock()
        if previous >= 0 && previous != newFD {
            Darwin.close(previous)
        }
    }

    private func closeCurrentSocket() {
        stateLock.lock()
        let current = fd
        fd = -1
        let callbacks = pending
        pending.removeAll()
        stateLock.unlock()
        if current >= 0 {
            Darwin.close(current)
        }
        guard !callbacks.isEmpty else { return }
        DispatchQueue.main.async {
            for callback in callbacks.values {
                callback(.failure(IPCError.closed))
            }
        }
    }

    private func interruptibleSleep(_ seconds: TimeInterval) {
        _ = wake.wait(timeout: .now() + seconds)
    }

    private struct Frame {
        var opcode: UInt32
        var payload: Data
    }

    private func readFrame(fd socketFD: Int32, timeoutMilliseconds: Int32?) throws -> Frame {
        if let timeoutMilliseconds {
            var pollFD = pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0)
            let result = poll(&pollFD, nfds_t(1), timeoutMilliseconds)
            if result == 0 { throw IPCError.timeout }
            if result < 0 { throw IPCError.closed }
        }
        guard let header = readExact(fd: socketFD, count: 8) else {
            throw IPCError.closed
        }
        let opcode = header.withUnsafeBytes { raw in
            UInt32(littleEndian: raw.load(fromByteOffset: 0, as: UInt32.self))
        }
        let length = header.withUnsafeBytes { raw in
            UInt32(littleEndian: raw.load(fromByteOffset: 4, as: UInt32.self))
        }
        guard length <= 1_048_576 else { throw IPCError.badFrame }
        if length == 0 {
            return Frame(opcode: opcode, payload: Data())
        }
        guard let payload = readExact(fd: socketFD, count: Int(length)) else {
            throw IPCError.closed
        }
        return Frame(opcode: opcode, payload: payload)
    }

    private func readExact(fd socketFD: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        var received = 0
        while received < count {
            let bytes = data.withUnsafeMutableBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.read(socketFD, base.advanced(by: received), count - received)
            }
            if bytes < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if bytes == 0 { return nil }
            received += bytes
        }
        return data
    }

    private func writeFrame(fd socketFD: Int32, opcode: UInt32, payload: Data) throws {
        var packet = Data(capacity: 8 + payload.count)
        var op = opcode.littleEndian
        var length = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &op) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        packet.append(payload)
        try writeAll(fd: socketFD, data: packet)
    }

    private func writeAll(fd socketFD: Int32, data: Data) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let bytes = Darwin.write(socketFD, base.advanced(by: sent), raw.count - sent)
                if bytes < 0 {
                    if errno == EINTR { continue }
                    throw IPCError.closed
                }
                if bytes == 0 { throw IPCError.closed }
                sent += bytes
            }
        }
    }

    private func connectUnix(path: String, timeoutMilliseconds: Int32) throws -> Int32 {
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw IPCError.closed }
        _ = fcntl(socketFD, F_SETFD, FD_CLOEXEC)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            Darwin.close(socketFD)
            throw IPCError.pathTooLong
        }
        path.withCString { cString in
            withUnsafeMutablePointer(to: &address.sun_path) { tuple in
                tuple.withMemoryRebound(to: CChar.self, capacity: capacity) { buffer in
                    _ = strlcpy(buffer, cString, capacity)
                }
            }
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let flags = fcntl(socketFD, F_GETFL, 0)
        _ = fcntl(socketFD, F_SETFL, flags | O_NONBLOCK)
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connectResult != 0 && errno != EINPROGRESS {
            Darwin.close(socketFD)
            throw IPCError.closed
        }
        if connectResult != 0 {
            var pollFD = pollfd(fd: socketFD, events: Int16(POLLOUT), revents: 0)
            let pollResult = poll(&pollFD, nfds_t(1), timeoutMilliseconds)
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            let socketErrorResult = withUnsafeMutablePointer(to: &socketError) { pointer in
                getsockopt(socketFD, SOL_SOCKET, SO_ERROR, UnsafeMutableRawPointer(pointer), &length)
            }
            if pollResult <= 0 || socketErrorResult != 0 || socketError != 0 {
                Darwin.close(socketFD)
                throw IPCError.closed
            }
        }
        _ = fcntl(socketFD, F_SETFL, flags)
        return socketFD
    }

    private func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func parseReady(_ json: [String: Any]) -> DiscordUser? {
        guard (json["evt"] as? String) == "READY" else { return nil }
        guard let data = json["data"] as? [String: Any] else { return nil }
        let userJSON = (data["user"] as? [String: Any]) ?? data
        guard let id = stringField(userJSON["id"]), !id.isEmpty else { return nil }
        return DiscordUser(
            id: id,
            username: stringField(userJSON["username"]) ?? "",
            globalName: stringField(userJSON["global_name"]),
            discriminator: stringField(userJSON["discriminator"]) ?? "0",
            avatar: stringField(userJSON["avatar"])
        )
    }

    private func discordError(_ json: [String: Any]) -> String? {
        let event = json["evt"] as? String
        let data = json["data"] as? [String: Any]
        let message = data?["message"] as? String
        if event == "ERROR" {
            if let message, !message.isEmpty { return message }
            return "Discord rejected the request."
        }
        if let code = data?["code"] as? Int, code >= 4000, let message, !message.isEmpty {
            return message
        }
        return nil
    }

    private func stringField(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }
}

private enum ConnectFailure: Error {
    case discordNotRunning
    case rejected(String)
    case superseded
}

enum SocketLocator {
    static let prefixes = [
        "discord-ipc",
        "discord-ptb-ipc",
        "discord-canary-ipc",
        "discord-development-ipc"
    ]

    static func existingSockets() -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        for path in discoveredSocketPaths() + candidatePaths() {
            guard seen.insert(path).inserted, isSocket(path) else { continue }
            paths.append(path)
        }
        return paths.sorted(by: socketSort)
    }

    /// Matches discord-rpc IPC discovery: scan temp/runtime folders for live `discord-*-ipc-*` sockets.
    private static func discoveredSocketPaths() -> [String] {
        var paths: [String] = []
        var seen = Set<String>()
        for directory in searchDirectories() {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries {
                guard prefixes.contains(where: { entry.hasPrefix("\($0)-") }) else { continue }
                let path = URL(fileURLWithPath: directory).appendingPathComponent(entry).standardizedFileURL.path
                if seen.insert(path).inserted {
                    paths.append(path)
                }
            }
        }
        return paths
    }

    static func candidatePaths() -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        for index in 0...9 {
            for prefix in prefixes {
                for directory in searchDirectories() {
                    let path = URL(fileURLWithPath: directory)
                        .appendingPathComponent("\(prefix)-\(index)")
                        .standardizedFileURL
                        .path
                    if seen.insert(path).inserted {
                        paths.append(path)
                    }
                }
            }
        }
        return paths
    }

    /// Same directory order as discord-rpc: TEMP, TMPDIR, XDG_RUNTIME_DIR, /tmp, then Discord App Support.
    private static func searchDirectories() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        var directories: [String] = []
        func append(_ raw: String?) {
            guard let raw, !raw.isEmpty else { return }
            let path = URL(fileURLWithPath: raw).standardizedFileURL.path
            directories.append(path)
        }
        append(environment["TEMP"])
        append(environment["TMPDIR"])
        append(environment["XDG_RUNTIME_DIR"])
        append("/tmp")
        append(NSTemporaryDirectory())

        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        for folder in ["discord", "discordptb", "discordcanary", "discorddevelopment"] {
            directories.append(support.appendingPathComponent(folder, isDirectory: true).standardizedFileURL.path)
        }

        var seen = Set<String>()
        return directories.filter { seen.insert($0).inserted }
    }

    private static func socketSort(_ lhs: String, _ rhs: String) -> Bool {
        let left = URL(fileURLWithPath: lhs).lastPathComponent
        let right = URL(fileURLWithPath: rhs).lastPathComponent
        let leftRank = prefixRank(for: left)
        let rightRank = prefixRank(for: right)
        if leftRank != rightRank { return leftRank < rightRank }
        return indexRank(for: left) < indexRank(for: right)
    }

    private static func prefixRank(for name: String) -> Int {
        for (index, prefix) in prefixes.enumerated() {
            if name.hasPrefix("\(prefix)-") {
                return index
            }
        }
        return prefixes.count
    }

    private static func indexRank(for name: String) -> Int {
        guard let suffix = name.split(separator: "-").last,
              let value = Int(suffix) else {
            return Int.max
        }
        return value
    }

    private static func isSocket(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFSOCK
    }
}
