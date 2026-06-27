import SwiftUI

struct EmailDetailView: View {
    @EnvironmentObject var store: MailStore
    let email: Email

    @State private var bodyText: String? = nil
    @State private var isLoadingBody = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                Divider()
                bodySection
            }
        }
        .navigationTitle("メール")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            bodyText = await store.fetchBody(for: email)
            isLoadingBody = false
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(email.subject)
                .font(.title3)
                .fontWeight(.semibold)

            infoRow(label: "差出人", value: email.from)
            infoRow(label: "宛先",   value: email.to.isEmpty ? "—" : email.to)
            infoRow(label: "日時",   value: fullDate(email.date))
        }
        .padding()
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var bodySection: some View {
        if isLoadingBody {
            HStack {
                Spacer()
                ProgressView()
                    .padding(40)
                Spacer()
            }
        } else if let text = bodyText {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .padding()
        } else {
            Text("本文を取得できませんでした。")
                .foregroundStyle(.secondary)
                .padding()
        }
    }

    private func fullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateStyle = .long
        f.timeStyle = .short
        return f.string(from: date)
    }
}
