import SwiftUI

struct InboxView: View {
    @EnvironmentObject var store: MailStore
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if !store.accountConfig.isConfigured {
                    unconfiguredView
                } else if store.isLoading && store.emails.isEmpty {
                    loadingView
                } else if let msg = store.errorMessage {
                    errorView(msg)
                } else if store.emails.isEmpty {
                    emptyView
                } else {
                    emailList
                }
            }
            .navigationTitle("受信トレイ")
            .searchable(text: $searchText, prompt: "件名・差出人を検索")
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    await store.search(query: newValue)
                }
            }
            .onSubmit(of: .search) {
                searchTask?.cancel()
                Task { await store.search(query: searchText) }
            }
            .refreshable {
                searchText = ""
                await store.loadInbox()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if store.isLoading {
                        ProgressView()
                    }
                }
            }
        }
        .task { await store.loadInbox() }
    }

    private var emailList: some View {
        List(store.emails) { email in
            NavigationLink(destination: EmailDetailView(email: email)) {
                EmailRowView(email: email)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        .listStyle(.plain)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("メールを読み込んでいます…")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            searchText.isEmpty ? "メールなし" : "検索結果なし",
            systemImage: searchText.isEmpty ? "tray" : "magnifyingglass",
            description: Text(searchText.isEmpty
                ? "受信トレイにメールはありません"
                : "「\(searchText)」に一致するメールはありません")
        )
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView(
            "エラー",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
        .overlay(alignment: .bottom) {
            Button("再試行") {
                Task { await store.loadInbox() }
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 40)
        }
    }

    private var unconfiguredView: some View {
        ContentUnavailableView(
            "アカウント未設定",
            systemImage: "envelope.badge.shield.half.filled",
            description: Text("「設定」タブからIMAPアカウントを設定してください")
        )
    }
}

struct EmailRowView: View {
    let email: Email

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(email.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(displayName(from: email.from))
                        .font(.headline)
                        .fontWeight(email.isRead ? .regular : .semibold)
                        .lineLimit(1)
                    Spacer()
                    Text(formattedDate(email.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(email.subject)
                    .font(.subheadline)
                    .fontWeight(email.isRead ? .regular : .medium)
                    .foregroundStyle(email.isRead ? .secondary : .primary)
                    .lineLimit(1)
            }
        }
    }

    private func displayName(from: String) -> String {
        if let nameEnd = from.firstIndex(of: "<") {
            let name = String(from[..<nameEnd]).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? from : name
        }
        return from
    }

    private func formattedDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "昨日"
        } else {
            let f = DateFormatter()
            f.dateFormat = "M/d"
            return f.string(from: date)
        }
    }
}
