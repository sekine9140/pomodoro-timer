import Foundation

struct Email: Identifiable {
    let id: Int
    let messageId: String
    let from: String
    let to: String
    let subject: String
    let date: Date
    var isRead: Bool
    var body: String?
}

struct AccountConfig: Codable {
    var displayName: String = ""
    var emailAddress: String = ""
    var imapHost: String = ""
    var imapPort: UInt16 = 993
    var username: String = ""
    var password: String = ""

    static let presets: [(name: String, host: String, port: UInt16)] = [
        ("Gmail",           "imap.gmail.com",            993),
        ("iCloud",          "imap.mail.me.com",           993),
        ("Yahoo! Japan",    "imap.mail.yahoo.co.jp",     993),
        ("Outlook/Hotmail", "outlook.office365.com",     993),
    ]

    static func load() -> AccountConfig {
        guard let data = UserDefaults.standard.data(forKey: "accountConfig"),
              let config = try? JSONDecoder().decode(AccountConfig.self, from: data)
        else { return AccountConfig() }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "accountConfig")
        }
    }

    var isConfigured: Bool {
        !imapHost.isEmpty && !username.isEmpty && !password.isEmpty
    }
}

enum IMAPError: Error, LocalizedError {
    case connectionFailed(String)
    case authFailed
    case commandFailed(String)
    case networkError(Error)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "接続失敗: \(msg)"
        case .authFailed:               return "認証失敗。\nGmailはアプリパスワードが必要です。"
        case .commandFailed(let msg):   return "コマンドエラー: \(msg)"
        case .networkError(let e):      return "ネットワークエラー: \(e.localizedDescription)"
        case .notConnected:             return "未接続"
        }
    }
}
