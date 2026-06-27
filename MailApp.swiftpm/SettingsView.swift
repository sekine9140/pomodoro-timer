import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: MailStore
    @State private var config: AccountConfig = AccountConfig.load()
    @State private var showPassword = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                presetsSection
                accountSection
                imapSection
                saveSection
            }
            .navigationTitle("設定")
        }
    }

    private var presetsSection: some View {
        Section("サーバープリセット") {
            ForEach(AccountConfig.presets, id: \.name) { preset in
                Button {
                    config.imapHost = preset.host
                    config.imapPort = preset.port
                } label: {
                    HStack {
                        Text(preset.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if config.imapHost == preset.host {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.accentColor)
                        }
                    }
                }
            }
            Button("カスタム") {
                config.imapHost = ""
                config.imapPort = 993
            }
        }
    }

    private var accountSection: some View {
        Section("アカウント情報") {
            LabeledContent("表示名") {
                TextField("山田 太郎", text: $config.displayName)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("メールアドレス") {
                TextField("you@example.com", text: $config.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var imapSection: some View {
        Section("IMAPサーバー") {
            LabeledContent("ホスト") {
                TextField("imap.example.com", text: $config.imapHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("ポート") {
                TextField("993", value: $config.imapPort, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("ユーザー名") {
                TextField("you@example.com", text: $config.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("パスワード") {
                HStack {
                    if showPassword {
                        TextField("パスワード", text: $config.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    } else {
                        SecureField("パスワード", text: $config.password)
                            .multilineTextAlignment(.trailing)
                    }
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if gmailSelected {
                Label("Gmailはアプリパスワードが必要です", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                store.accountConfig = config
                config.save()
                saved = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    saved = false
                }
            } label: {
                HStack {
                    Spacer()
                    Label(saved ? "保存しました" : "保存", systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(!config.isConfigured)
        }
    }

    private var gmailSelected: Bool {
        config.imapHost == "imap.gmail.com"
    }
}
