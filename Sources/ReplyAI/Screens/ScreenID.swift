import Foundation

/// Every screen in the 28-screen inventory. IDs match app-shell.jsx SCREEN_GROUPS.
enum ScreenID: String, CaseIterable, Hashable, Identifiable {
    // Onboarding
    case obWelcome       = "ob-welcome"
    case obPrivacy       = "ob-privacy"
    case obPermissions   = "ob-permissions"
    case obChannels      = "ob-channels"
    case obChannelDetail = "ob-channel-detail"
    case obVoice         = "ob-voice"
    case obTone          = "ob-tone"
    case obShortcuts     = "ob-shortcuts"
    case obDone          = "ob-done"

    // Main app
    case appInbox        = "app-inbox"
    case appInboxEmpty   = "app-inbox-empty"
    case appInboxLoading = "app-inbox-loading"
    case appOffline      = "app-offline"

    // Threads
    case thrGroup        = "thr-group"
    case thrMedia        = "thr-media"
    case thrLong         = "thr-long"

    // Composer
    case cmpTones        = "cmp-tones"
    case cmpCustom       = "cmp-custom"
    case cmpLowconf      = "cmp-lowconf"
    case cmpNothing      = "cmp-nothing"

    // Surfaces
    case sfcPalette      = "sfc-palette"
    case sfcSnooze       = "sfc-snooze"
    case sfcRules        = "sfc-rules"
    case sfcMenubar      = "sfc-menubar"
    case sfcNotification = "sfc-notification"

    // Settings
    case setAccount      = "set-account"
    case setVoice        = "set-voice"
    case setChannels     = "set-channels"
    case setShortcuts    = "set-shortcuts"
    case setPrivacy      = "set-privacy"
    case setModel        = "set-model"

    // Errors
    case errDisconnected = "err-disconnected"
    case errAuth         = "err-auth"
    case errModelUpdate  = "err-model-update"

    var id: String { rawValue }
}

/// Grouped navigation order matching app-shell.jsx SCREEN_GROUPS.
struct ScreenGroup: Hashable {
    let title: String
    let items: [ScreenItem]
}
struct ScreenItem: Hashable, Identifiable {
    let id: ScreenID
    let label: String
}

enum ScreenInventory {
    static let groups: [ScreenGroup] = [
        .init(title: "Onboarding", items: [
            .init(id: .obWelcome,       label: "01 Welcome"),
            .init(id: .obPrivacy,       label: "02 Privacy promise"),
            .init(id: .obPermissions,   label: "03 Permissions"),
            .init(id: .obChannels,      label: "04 Connect channels"),
            .init(id: .obChannelDetail, label: "05 Channel · Slack OAuth"),
            .init(id: .obVoice,         label: "06 Voice sample"),
            .init(id: .obTone,          label: "07 Default tones"),
            .init(id: .obShortcuts,     label: "08 Keyboard tour"),
            .init(id: .obDone,          label: "09 Ready"),
        ]),
        .init(title: "Main app", items: [
            .init(id: .appInbox,        label: "Unified inbox"),
            .init(id: .appInboxEmpty,   label: "Inbox · empty"),
            .init(id: .appInboxLoading, label: "Inbox · loading"),
            .init(id: .appOffline,      label: "Offline"),
        ]),
        .init(title: "Threads", items: [
            .init(id: .thrGroup, label: "Group chat (Slack)"),
            .init(id: .thrMedia, label: "Media & voice memo"),
            .init(id: .thrLong,  label: "Long thread · summary"),
        ]),
        .init(title: "Composer", items: [
            .init(id: .cmpTones,   label: "Three tones"),
            .init(id: .cmpCustom,  label: "Custom instruction"),
            .init(id: .cmpLowconf, label: "Low-confidence draft"),
            .init(id: .cmpNothing, label: "Nothing to reply"),
        ]),
        .init(title: "Surfaces", items: [
            .init(id: .sfcPalette,      label: "⌘K command palette"),
            .init(id: .sfcSnooze,       label: "Snooze picker"),
            .init(id: .sfcRules,        label: "Smart Rules builder"),
            .init(id: .sfcMenubar,      label: "Menu-bar mini-window"),
            .init(id: .sfcNotification, label: "System notification"),
        ]),
        .init(title: "Settings", items: [
            .init(id: .setAccount,   label: "Account"),
            .init(id: .setVoice,     label: "Voice profile"),
            .init(id: .setChannels,  label: "Channels"),
            .init(id: .setShortcuts, label: "Shortcuts"),
            .init(id: .setPrivacy,   label: "Privacy"),
            .init(id: .setModel,     label: "Model"),
        ]),
        .init(title: "Edge cases", items: [
            .init(id: .errDisconnected, label: "Channel disconnected"),
            .init(id: .errAuth,         label: "Auth expired"),
            .init(id: .errModelUpdate,  label: "Model updating"),
        ]),
    ]

    static let allItems: [ScreenItem] = groups.flatMap(\.items)

    static func item(for id: ScreenID) -> ScreenItem {
        allItems.first { $0.id == id } ?? allItems[0]
    }

    static func index(of id: ScreenID) -> Int {
        allItems.firstIndex(where: { $0.id == id }) ?? 0
    }

    static func next(after id: ScreenID) -> ScreenID {
        let i = index(of: id)
        return allItems[(i + 1) % allItems.count].id
    }

    static func previous(before id: ScreenID) -> ScreenID {
        let i = index(of: id)
        return allItems[(i - 1 + allItems.count) % allItems.count].id
    }
}

/// Purpose + build notes — mirrors SCREEN_META in app-screens.jsx.
enum ScreenMeta {
    static func purpose(for id: ScreenID) -> String {
        switch id {
        case .obWelcome:       "First impression after Download → first open"
        case .obPrivacy:       "Establish on-device trust before any permission prompts"
        case .obPermissions:   "Deep-link to System Settings panes for FDA, a11y, notifications"
        case .obChannels:      "Per-channel connect entry points"
        case .obChannelDetail: "Specifically: Slack OAuth loopback flow"
        case .obVoice:         "Train voice profile before first use"
        case .obTone:          "Set default tone across drafts"
        case .obShortcuts:     "Build muscle memory before first reply"
        case .obDone:          "Hand off to main app"
        case .appInbox:        "Primary UI — unified inbox with three-pane layout"
        case .appInboxEmpty:   "Earned state — inbox zero reinforcement"
        case .appInboxLoading: "First-run sync — can take 60-120s"
        case .appOffline:      "Degraded but-still-functional state"
        case .thrGroup:        "Group chat with multi-person context + @mention awareness"
        case .thrMedia:        "Image + voice memo + translation flow"
        case .thrLong:         "Summarize threads with >100 messages"
        case .cmpTones:        "Default composer — switch between 3 drafts"
        case .cmpCustom:       "Steer a single draft with a natural-language instruction"
        case .cmpLowconf:      "Refuse-to-guess state when context is thin"
        case .cmpNothing:      "Closed-thread state — drive to next thread"
        case .sfcPalette:      "Global search across people, threads, message content"
        case .sfcSnooze:       "Defer a thread with smart defaults"
        case .sfcRules:        "Declarative automation — if-this-then-that"
        case .sfcMenubar:      "At-a-glance checking without opening the main window"
        case .sfcNotification: "Reply directly from system notification"
        case .setAccount:      "Account, device list, plan"
        case .setVoice:        "Transparency about learned style + retrain"
        case .setChannels:     "Manage, reconnect, or remove connected services"
        case .setShortcuts:    "Rebind every keyboard shortcut"
        case .setPrivacy:      "Receipts for on-device trust + wipe buttons"
        case .setModel:        "Swap model size / quantization"
        case .errDisconnected: "Channel went down — surface only when it matters"
        case .errAuth:         "Token expired → re-auth flow"
        case .errModelUpdate:  "Background model downloads, user-informed"
        }
    }
}
