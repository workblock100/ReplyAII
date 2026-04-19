import SwiftUI

/// Temporary placeholder for screens that haven't been translated yet.
/// Each unfinished screen type is a zero-arg `View` that renders this.
/// As each screen gets a real implementation, delete its struct from this
/// file and add a real file in the appropriate Screens/ subdir.
struct ComingSoonView: View {
    var screen: ScreenID

    var body: some View {
        VStack(spacing: 12) {
            Text("Coming soon")
                .font(Theme.Font.serifItalic(42))
                .foregroundStyle(Theme.Color.fgDim)
            Text(screen.rawValue)
                .font(Theme.Font.mono(12))
                .foregroundStyle(Theme.Color.fgMute)
            Text(ScreenMeta.purpose(for: screen))
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Color.fgMute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg1)
    }
}

// MARK: - Remaining screens — stubs forward to ComingSoonView

struct ThrMediaView:      View { var body: some View { ComingSoonView(screen: .thrMedia) } }
struct ThrLongView:       View { var body: some View { ComingSoonView(screen: .thrLong)  } }

struct SfcPaletteView:      View { var body: some View { ComingSoonView(screen: .sfcPalette)      } }
struct SfcSnoozeView:       View { var body: some View { ComingSoonView(screen: .sfcSnooze)       } }
struct SfcRulesView:        View { var body: some View { ComingSoonView(screen: .sfcRules)        } }
struct SfcMenubarView:      View { var body: some View { ComingSoonView(screen: .sfcMenubar)      } }
struct SfcNotificationView: View { var body: some View { ComingSoonView(screen: .sfcNotification) } }

struct ObWelcomeView:       View { var body: some View { ComingSoonView(screen: .obWelcome)       } }
struct ObPrivacyView:       View { var body: some View { ComingSoonView(screen: .obPrivacy)       } }
struct ObPermissionsView:   View { var body: some View { ComingSoonView(screen: .obPermissions)   } }
struct ObChannelsView:      View { var body: some View { ComingSoonView(screen: .obChannels)      } }
struct ObChannelDetailView: View { var body: some View { ComingSoonView(screen: .obChannelDetail) } }
struct ObVoiceView:         View { var body: some View { ComingSoonView(screen: .obVoice)         } }
struct ObToneView:          View { var body: some View { ComingSoonView(screen: .obTone)          } }
struct ObShortcutsView:     View { var body: some View { ComingSoonView(screen: .obShortcuts)     } }
struct ObDoneView:          View { var body: some View { ComingSoonView(screen: .obDone)          } }
