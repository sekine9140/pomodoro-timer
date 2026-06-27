import Foundation

@MainActor
class MailStore: ObservableObject {
    @Published var emails: [Email] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var accountConfig = AccountConfig.load()

    func loadInbox() async {
        guard accountConfig.isConfigured else {
            errorMessage = "設定からアカウントを設定してください。"
            return
        }
        isLoading = true
        errorMessage = nil

        let client = IMAPClient(host: accountConfig.imapHost, port: accountConfig.imapPort)
        do {
            try await client.connect()
            try await client.login(user: accountConfig.username, password: accountConfig.password)
            let count = try await client.selectInbox()
            if count > 0 {
                let from = max(1, count - 49)
                let fetched = try await client.fetchHeaders(sequence: "\(from):\(count)")
                emails = fetched.sorted { $0.date > $1.date }
            } else {
                emails = []
            }
            try await client.logout()
        } catch {
            await client.disconnect()
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            await loadInbox()
            return
        }
        guard accountConfig.isConfigured else { return }
        isLoading = true
        errorMessage = nil

        let client = IMAPClient(host: accountConfig.imapHost, port: accountConfig.imapPort)
        do {
            try await client.connect()
            try await client.login(user: accountConfig.username, password: accountConfig.password)
            _ = try await client.selectInbox()
            let seqNums = try await client.search(query: query)
            if seqNums.isEmpty {
                emails = []
            } else {
                let seqStr = seqNums.map { String($0) }.joined(separator: ",")
                let fetched = try await client.fetchHeaders(sequence: seqStr)
                emails = fetched.sorted { $0.date > $1.date }
            }
            try await client.logout()
        } catch {
            await client.disconnect()
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func fetchBody(for email: Email) async -> String? {
        guard accountConfig.isConfigured else { return nil }

        let client = IMAPClient(host: accountConfig.imapHost, port: accountConfig.imapPort)
        do {
            try await client.connect()
            try await client.login(user: accountConfig.username, password: accountConfig.password)
            _ = try await client.selectInbox()
            let body = try await client.fetchBody(seqNum: email.id)
            try await client.logout()
            return body
        } catch {
            await client.disconnect()
            return nil
        }
    }
}
