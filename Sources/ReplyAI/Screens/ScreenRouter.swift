import SwiftUI

/// Renders one of the 28 screens by ID. Mirrors `ScreenRouter` + `SCREEN_MAP`
/// in app-screens.jsx.
struct ScreenRouter: View {
    let screen: ScreenID

    var body: some View {
        switch screen {
        // Onboarding
        case .obWelcome:       ObWelcomeView()
        case .obPrivacy:       ObPrivacyView()
        case .obPermissions:   ObPermissionsView()
        case .obChannels:      ObChannelsView()
        case .obChannelDetail: ObChannelDetailView()
        case .obVoice:         ObVoiceView()
        case .obTone:          ObToneView()
        case .obShortcuts:     ObShortcutsView()
        case .obDone:          ObDoneView()

        // Main app
        case .appInbox:        InboxScreen()
        case .appInboxEmpty:   AppInboxEmptyView()
        case .appInboxLoading: AppInboxLoadingView()
        case .appOffline:      AppOfflineView()

        // Threads
        case .thrGroup:        ThrGroupView()
        case .thrMedia:        ThrMediaView()
        case .thrLong:         ThrLongView()

        // Composer variants
        case .cmpTones:        InboxScreen()   // same as app-inbox per JSX
        case .cmpCustom:       CmpCustomView()
        case .cmpLowconf:      CmpLowConfView()
        case .cmpNothing:      CmpNothingView()

        // Surfaces
        case .sfcPalette:      SfcPaletteView()
        case .sfcSnooze:       SfcSnoozeView()
        case .sfcRules:        SfcRulesView()
        case .sfcMenubar:      SfcMenubarView()
        case .sfcNotification: SfcNotificationView()

        // Settings
        case .setAccount:      SetAccountView()
        case .setVoice:        SetVoiceView()
        case .setChannels:     SetChannelsView()
        case .setShortcuts:    SetShortcutsView()
        case .setPrivacy:      SetPrivacyView()
        case .setModel:        SetModelView()

        // Errors
        case .errDisconnected: ErrDisconnectedView()
        case .errAuth:         ErrAuthView()
        case .errModelUpdate:  ErrModelUpdateView()
        }
    }
}
