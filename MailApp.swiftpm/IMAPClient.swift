import Foundation
import Network

actor IMAPClient {
    private var connection: NWConnection?
    private let host: String
    private let port: UInt16
    private var tagCounter = 0
    private var receiveBuffer = Data()

    init(host: String, port: UInt16 = 993) {
        self.host = host
        self.port = port
    }

    private func nextTag() -> String {
        tagCounter += 1
        return String(format: "T%04d", tagCounter)
    }

    func connect() async throws {
        let params = NWParameters(tls: NWProtocolTLS.Options())
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port),
            using: params
        )

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            conn.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true; cont.resume()
                case .failed(let e):
                    resumed = true; cont.resume(throwing: IMAPError.networkError(e))
                case .waiting(let e):
                    resumed = true; cont.resume(throwing: IMAPError.networkError(e))
                case .cancelled:
                    resumed = true; cont.resume(throwing: IMAPError.connectionFailed("キャンセル"))
                default: break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }

        connection = conn

        let greeting = try await readLine()
        guard greeting.hasPrefix("* OK") || greeting.hasPrefix("* PREAUTH") else {
            throw IMAPError.connectionFailed(greeting)
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func login(user: String, password: String) async throws {
        let tag = nextTag()
        let u = escape(user)
        let p = escape(password)
        try await send("\(tag) LOGIN \"\(u)\" \"\(p)\"\r\n")
        let lines = try await readTaggedResponse(tag: tag)
        guard lines.last?.hasPrefix("\(tag) OK") == true else {
            throw IMAPError.authFailed
        }
    }

    func selectInbox() async throws -> Int {
        let tag = nextTag()
        try await send("\(tag) SELECT INBOX\r\n")
        let lines = try await readTaggedResponse(tag: tag)
        guard lines.last?.hasPrefix("\(tag) OK") == true else {
            throw IMAPError.commandFailed("SELECT INBOX")
        }
        for line in lines {
            if line.hasSuffix(" EXISTS") {
                let parts = line.split(separator: " ")
                if parts.count >= 3, let n = Int(parts[1]) { return n }
            }
        }
        return 0
    }

    func fetchHeaders(sequence: String) async throws -> [Email] {
        let tag = nextTag()
        try await send("\(tag) FETCH \(sequence) (FLAGS RFC822.HEADER)\r\n")
        return try await parseFetchHeadersResponse(tag: tag)
    }

    func search(query: String) async throws -> [Int] {
        let tag = nextTag()
        let q = escape(query)
        try await send("\(tag) SEARCH OR SUBJECT \"\(q)\" FROM \"\(q)\"\r\n")
        let lines = try await readTaggedResponse(tag: tag)
        for line in lines {
            if line.hasPrefix("* SEARCH") {
                return line.split(separator: " ").dropFirst(2).compactMap { Int($0) }
            }
        }
        return []
    }

    func fetchBody(seqNum: Int) async throws -> String {
        let tag = nextTag()
        try await send("\(tag) FETCH \(seqNum) BODY[TEXT]\r\n")

        var bodyData = Data()
        while true {
            let line = try await readLine()
            if line.hasPrefix(tag + " ") { break }
            if line.hasSuffix("}"), let braceIdx = line.lastIndex(of: "{") {
                let countStr = String(line[line.index(after: braceIdx)...].dropLast())
                if let n = Int(countStr) {
                    bodyData = try await readExact(n)
                }
            }
        }

        return decodeBody(data: bodyData)
    }

    func logout() async throws {
        guard connection != nil else { return }
        let tag = nextTag()
        try? await send("\(tag) LOGOUT\r\n")
        _ = try? await readTaggedResponse(tag: tag)
        disconnect()
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func send(_ string: String) async throws {
        guard let conn = connection else { throw IMAPError.notConnected }
        guard let data = string.data(using: .utf8) else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let e = error { cont.resume(throwing: IMAPError.networkError(e)) }
                else { cont.resume() }
            })
        }
    }

    private func receive() async throws -> Data {
        guard let conn = connection else { throw IMAPError.notConnected }
        return try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let e = error { cont.resume(throwing: IMAPError.networkError(e)) }
                else if let d = data, !d.isEmpty { cont.resume(returning: d) }
                else if isComplete { cont.resume(throwing: IMAPError.connectionFailed("接続が閉じられました")) }
                else { cont.resume(returning: Data()) }
            }
        }
    }

    private func readLine() async throws -> String {
        let crlf = Data([0x0D, 0x0A])
        while true {
            if let range = receiveBuffer.range(of: crlf) {
                let lineData = receiveBuffer[..<range.lowerBound]
                receiveBuffer.removeSubrange(..<range.upperBound)
                return String(data: lineData, encoding: .utf8)
                    ?? String(data: lineData, encoding: .isoLatin1)
                    ?? ""
            }
            let chunk = try await receive()
            receiveBuffer.append(chunk)
        }
    }

    private func readExact(_ count: Int) async throws -> Data {
        while receiveBuffer.count < count {
            let chunk = try await receive()
            receiveBuffer.append(chunk)
        }
        let result = Data(receiveBuffer.prefix(count))
        receiveBuffer.removeFirst(count)
        return result
    }

    private func readTaggedResponse(tag: String) async throws -> [String] {
        var lines: [String] = []
        while true {
            let line = try await readLine()
            lines.append(line)
            if line.hasSuffix("}"), let braceIdx = line.lastIndex(of: "{") {
                let countStr = String(line[line.index(after: braceIdx)...].dropLast())
                if let n = Int(countStr) {
                    let data = try await readExact(n)
                    lines.append(String(data: data, encoding: .utf8) ?? "")
                }
                continue
            }
            if line.hasPrefix(tag + " ") { return lines }
        }
    }

    private func parseFetchHeadersResponse(tag: String) async throws -> [Email] {
        var emails: [Email] = []
        var pendingSeqNum: Int? = nil
        var pendingIsRead = false

        while true {
            let line = try await readLine()
            if line.hasPrefix(tag + " ") { break }

            if line.hasPrefix("* ") {
                let parts = line.split(separator: " ")
                if parts.count >= 3, parts[2] == "FETCH", let n = Int(parts[1]) {
                    pendingSeqNum = n
                    pendingIsRead = line.contains("\\Seen")
                }
            }

            if line.hasSuffix("}"), let braceIdx = line.lastIndex(of: "{") {
                let countStr = String(line[line.index(after: braceIdx)...].dropLast())
                if let byteCount = Int(countStr), let seqNum = pendingSeqNum {
                    let headerData = try await readExact(byteCount)
                    let email = parseHeaderData(seqNum: seqNum, data: headerData, isRead: pendingIsRead)
                    emails.append(email)
                    pendingSeqNum = nil
                    pendingIsRead = false
                }
            }
        }
        return emails
    }

    private func parseHeaderData(seqNum: Int, data: Data, isRead: Bool) -> Email {
        let raw = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        var from = ""; var to = ""; var subject = ""; var dateStr = ""; var messageId = ""
        var field = ""; var value = ""

        func commit() {
            switch field.lowercased() {
            case "from":       from      = value
            case "to":         to        = value
            case "subject":    subject   = value
            case "date":       dateStr   = value
            case "message-id": messageId = value
            default: break
            }
        }

        for line in raw.components(separatedBy: "\r\n") {
            if line.isEmpty { break }
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                value += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colonIdx = line.firstIndex(of: ":") {
                commit()
                field = String(line[..<colonIdx])
                value = String(line[line.index(after: colonIdx)...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        commit()

        return Email(
            id: seqNum,
            messageId: messageId,
            from:    decodeMIME(from.isEmpty    ? "(不明)"    : from),
            to:      decodeMIME(to),
            subject: decodeMIME(subject.isEmpty ? "(件名なし)" : subject),
            date:    parseDate(dateStr) ?? Date(),
            isRead:  isRead
        )
    }

    private func decodeMIME(_ str: String) -> String {
        guard str.contains("=?") else { return str }
        guard let regex = try? NSRegularExpression(
            pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#
        ) else { return str }

        let ns = str as NSString
        let range = NSRange(location: 0, length: ns.length)
        var result = str

        for match in regex.matches(in: str, range: range).reversed() {
            let charset  = ns.substring(with: match.range(at: 1)).lowercased()
            let encoding = ns.substring(with: match.range(at: 2)).uppercased()
            let encoded  = ns.substring(with: match.range(at: 3))

            let strEnc: String.Encoding = {
                switch charset {
                case "iso-2022-jp": return .iso2022JP
                case "shift_jis", "shift-jis", "sjis", "x-sjis": return .shiftJIS
                case "euc-jp":      return .japaneseEUC
                case "iso-8859-1":  return .isoLatin1
                default:            return .utf8
                }
            }()

            var decoded = encoded
            if encoding == "B" {
                if let d = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
                   let s = String(data: d, encoding: strEnc) ?? String(data: d, encoding: .utf8) {
                    decoded = s
                }
            } else {
                let qp = encoded.replacingOccurrences(of: "_", with: " ")
                var bytes = [UInt8]()
                var i = qp.startIndex
                while i < qp.endIndex {
                    if qp[i] == "=",
                       let i1 = qp.index(i, offsetBy: 1, limitedBy: qp.endIndex),
                       let i2 = qp.index(i, offsetBy: 2, limitedBy: qp.endIndex),
                       i1 < qp.endIndex, i2 < qp.endIndex,
                       let byte = UInt8(String(qp[i1..<i2]), radix: 16) {
                        bytes.append(byte)
                        i = i2
                    } else {
                        bytes.append(contentsOf: String(qp[i]).utf8)
                        i = qp.index(after: i)
                    }
                }
                decoded = String(bytes: bytes, encoding: strEnc)
                    ?? String(bytes: bytes, encoding: .utf8)
                    ?? encoded
            }

            if let r = Range(match.range, in: result) {
                result.replaceSubrange(r, with: decoded)
            }
        }
        return result
    }

    private func decodeBody(data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .shiftJIS) { return s }
        if let s = String(data: data, encoding: .japaneseEUC) { return s }
        if let s = String(data: data, encoding: .iso2022JP) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return "(本文のデコードに失敗しました)"
    }

    private func parseDate(_ str: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss z",
            "d MMM yyyy HH:mm:ss z",
        ]
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: str) { return d }
        }
        return nil
    }
}
