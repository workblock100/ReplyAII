import SwiftUI

/// `set-channels` — real connection status per channel + working
/// Connect/Disconnect actions. Replaces the design-time mock that always
/// said every channel was "connected · just now."
struct SetChannelsView: View {
    @State private var rows: [Row] = []
    @State private var showingSlackSetup = false
    @State private var slackClientID: String = ""
    @State private var slackClientSecret: String = ""
    @State private var connectInFlight: Bool = false
    @State private var connectError: String?

    private let oauth = SlackOAuthFlow()
    private let slackTokenStore = SlackTokenStore()

    struct Row: Identifiable {
        let id = UUID()
        let channel: Channel
        let label: String
        let status: Status
        let detail: String
        let canConnect: Bool

        enum Status {
            case connected, error, disconnected, comingSoon
            var color: Color {
                switch self {
                case .connected:    Theme.Color.accent
                case .error:        Theme.Color.err
                case .disconnected: Theme.Color.fgMute
                case .comingSoon:   Theme.Color.fgFaint
                }
            }
            var text: String {
                switch self {
                case .connected:    "CONNECTED"
                case .error:        "ERROR"
                case .disconnected: "DISCONNECTED"
                case .comingSoon:   "COMING SOON"
                }
            }
        }
    }

    var body: some View {
        SettingsShell(active: .channels) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Channels")
                        .font(Theme.Font.sans(26))
                        .tracking(-0.52)
                        .foregroundStyle(Theme.Color.fg)
                    Spacer()
                }

                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        channelRow(row)
                    }
                }
                .padding(.top, 24)

                if let connectError {
                    Text(connectError)
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Color.err)
                        .padding(.top, 12)
                }
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
        .sheet(isPresented: $showingSlackSetup) { slackSetupSheet }
    }

    // MARK: - Row

    private func channelRow(_ row: Row) -> some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: Theme.Radius.r10, style: .continuous)
                .fill(row.channel.dotColor.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: channelSymbol(row.channel))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(row.channel.dotColor)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Color.fg)
                Text(row.detail)
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Color.fgMute)
            }
            Spacer()
            Text(row.status.text)
                .font(Theme.Font.mono(11))
                .tracking(0.9)
                .foregroundStyle(row.status.color)

            actionButton(for: row)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Color.line).frame(height: 1) }
        .overlay(alignment: .bottom) {
            if row.id == rows.last?.id {
                Rectangle().fill(Theme.Color.line).frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func actionButton(for row: Row) -> some View {
        switch (row.channel, row.status) {
        case (.slack, .connected):
            Button("Disconnect") { disconnectSlack() }
                .buttonStyle(.plain)
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.fgMute)
        case (.slack, _) where row.canConnect:
            Button("Connect") { showingSlackSetup = true }
                .buttonStyle(.plain)
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.accent)
        case (.imessage, .error), (.sms, .error):
            Button("Open Settings") { openFDASettings() }
                .buttonStyle(.plain)
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Color.warn)
        default:
            EmptyView()
        }
    }

    // MARK: - Slack setup sheet

    private var slackSetupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect Slack").font(Theme.Font.sans(18, weight: .semibold))
            Text("Create a Slack app at api.slack.com → Apps. Grant scopes channels:read + chat:write. Set redirect URL to http://localhost:4242/callback. Paste the credentials below.")
                .font(Theme.Font.sans(12))
                .foregroundStyle(Theme.Color.fgMute)
                .fixedSize(horizontal: false, vertical: true)

            field("Client ID", text: $slackClientID)
            field("Client Secret", text: $slackClientSecret, secure: true)

            HStack {
                Spacer()
                Button("Cancel") {
                    showingSlackSetup = false
                    slackClientSecret = ""
                }
                .buttonStyle(.plain)
                Button(connectInFlight ? "Connecting…" : "Authorize") {
                    runSlackOAuth()
                }
                .disabled(connectInFlight || slackClientID.isEmpty || slackClientSecret.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func field(_ label: String, text: Binding<String>, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.Font.mono(10)).tracking(0.9)
                .foregroundStyle(Theme.Color.fgFaint)
            Group {
                if secure { SecureField("", text: text) }
                else      { TextField("", text: text) }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Actions

    private func runSlackOAuth() {
        connectInFlight = true
        connectError = nil
        let id = slackClientID, secret = slackClientSecret
        oauth.authorize(clientID: id, clientSecret: secret) { result in
            Task { @MainActor in
                connectInFlight = false
                switch result {
                case .success:
                    showingSlackSetup = false
                    slackClientSecret = ""
                    await refresh()
                case .failure(let err):
                    connectError = err.localizedDescription
                }
            }
        }
    }

    private func disconnectSlack() {
        slackTokenStore.delete()
        Task { await refresh() }
    }

    private func openFDASettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - State refresh

    @MainActor
    private func refresh() async {
        let imessage = currentIMessage()
        let slack    = currentSlack()
        rows = [
            .init(channel: .imessage, label: "iMessage",         status: imessage.0, detail: imessage.1, canConnect: false),
            .init(channel: .slack,    label: "Slack",            status: slack.0,    detail: slack.1,    canConnect: true),
            .init(channel: .sms,      label: "SMS",              status: imessage.0, detail: "Routed through Messages.app", canConnect: false),
            .init(channel: .whatsapp, label: "WhatsApp",         status: .comingSoon, detail: "Hosted WebView in a future build", canConnect: false),
            .init(channel: .teams,    label: "Microsoft Teams",  status: .comingSoon, detail: "Graph API integration in a future build", canConnect: false),
            .init(channel: .telegram, label: "Telegram",         status: .comingSoon, detail: "Bot API integration in a future build", canConnect: false),
        ]
    }

    private func currentIMessage() -> (Row.Status, String) {
        // Probe chat.db's SQLite header — same approach as ObPermissionsView's
        // FDA detector. If the read succeeds, we're connected.
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Messages/chat.db")
        guard let fh = FileHandle(forReadingAtPath: path) else {
            return (.error, "Full Disk Access required")
        }
        defer { try? fh.close() }
        let header = (try? fh.read(upToCount: 16)) ?? Data()
        if header.starts(with: Array("SQLite format 3\0".utf8)) {
            return (.connected, "Reading from chat.db")
        }
        return (.error, "Full Disk Access required")
    }

    private func currentSlack() -> (Row.Status, String) {
        if let creds = slackTokenStore.get(), !creds.token.isEmpty {
            let detail = creds.workspaceName.isEmpty
                ? "Connected via OAuth"
                : "Workspace: \(creds.workspaceName)"
            return (.connected, detail)
        }
        return (.disconnected, "Run OAuth to connect a workspace")
    }

    // MARK: - Helpers

    private func channelSymbol(_ c: Channel) -> String {
        switch c {
        case .imessage: "bubble.left.fill"
        case .slack:    "number"
        case .whatsapp: "message.fill"
        case .sms:      "message"
        case .teams:    "person.2.fill"
        case .telegram: "paperplane.fill"
        }
    }
}
