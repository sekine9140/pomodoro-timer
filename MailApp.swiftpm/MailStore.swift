import Foundation

@MainActor
class MailStore: ObservableObject {
    @Published var emails: [Email] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var accountConfig = AccountConfig.load()

    private var activeClient: IMAPClient?

    func loadInbox() async {
        guard accountConfig.isConfigured else {
            errorMessage = "設定からアカウントを設定してください。"
            return
        }
        await runWithClient { client in
            let count = try await client.selectInbox()
            if count > 0 {
                let from = max(1, count - 49)
                let fetched = try await client.fetchHeaders(sequence: "\(from):\(count)")
                self.emails = fetched.sorted { $0.date > $1.date }
            } else {
                self.emails = []
            }
        }
    }

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            await loadInbox()
            return
        }
        guard accountConfig.isConfigured else { return }
        await runWithClient { client in
            _ = try await client.selectInbox()
            let seqNums = try await client.search(query: query)
            if seqNums.isEmpty {
                self.emails = []
            } else {
                let seqStr = seqNums.map { String($0) }.joined(separator: ",")
                let fetched = try await client.fetchHeaders(sequence: seqStr)
                self.emails = fetched.sorted { $0.date > $1.date }
            }
        }
    }

    func fetchBody(for email: Email) async -> String? {
        guard accountConfig.isConfigured else { return nil }
        var body: String? = nil
        await runWithClient { client in
            _ = try await client.selectInbox()
            body = try await client.fetchBody(seqNum: email.id)
        }
        return body
    }

    private func runWithClient(_ work: @escaping (IMAPClient) async throws -> Void) async {
        isLoading = true
        errorMessage = nil

        let client = IMAPClient(host: accountConfig.imapHost, port: accountConfig.imapPort)
        do {
            try await client.connect()
            try await client.login(user: accountConfig.username, password: accountConfig.password)
            try await work(client)
            try await client.logout()
        } catch {
            client.disconnect()
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
