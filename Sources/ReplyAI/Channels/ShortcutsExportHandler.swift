import Foundation

/// Errors thrown by `ShortcutsExportHandler.parse(url:)`.
enum ShortcutsExportError: Error, Equatable {
    /// The URL had no `data` query parameter, the parameter was empty, or
    /// the percent-decoded payload wasn't valid JSON matching the export
    /// schema.
    case malformedPayload
}

/// Receives manual iMessage exports from a user-triggered Shortcuts.app
/// shortcut via the `replyai://import-messages` URL scheme.
///
/// Why this exists (2026-04-23 pivot): Full Disk Access reads of
/// `chat.db` are unreliable. Shortcuts.app can iterate a chat's recent
/// messages and post them back to ReplyAI through a URL callback —
/// requires only the user's tap, no FDA prompt. The user authors the
/// shortcut once; subsequent runs feed thread snapshots into the inbox.
///
/// Schema: the URL's `data` query parameter is a percent-encoded JSON
/// array of thread objects:
/// ```
/// [
///   {
///     "id": "iMessage;-;+15555550100",
///     "displayName": "Maya Lee",
///     "preview": "see you at 3?",
///     "channel": "imessage",
///     "messages": [
///       { "from": "them", "text": "see you at 3?", "time": "2:14 PM" }
///     ]
///   }
/// ]
/// ```
///
/// Production wiring lives in `ReplyAIApp` (`onOpenURL` → `parse(url:)`
/// → `InboxViewModel.injectThreads`). The parser is pure so the unit
/// tests can exercise the whole thing without an `NSApplication`.
struct ShortcutsExportHandler: Sendable {
    /// Parsed thread + its embedded messages, ready to hand to the
    /// inbox. Keeping messages alongside the thread preserves the
    /// per-thread snapshot semantics — a Shortcut export is one
    /// transactional read, not a stream of incremental updates.
    struct Export: Sendable, Equatable {
        let thread: MessageThread
        let messages: [Message]
    }

    /// Wire-format query parameter name carrying the JSON payload. The
    /// user-authored Shortcut emits `replyai://import-messages?data=<encoded>`;
    /// the parser looks for the same `data` key. Drift between Shortcut
    /// and parser is invisible to the user — every export silently
    /// throws `malformedPayload` and the inbox simply doesn't update.
    /// Hoisted from the inline literal so the contract is greppable and
    /// pinned. Pinned by
    /// `ShortcutsExportHandlerTests.testQueryParameterNameIsFrozen`.
    static let payloadQueryParameterName = "data"

    /// Default channel applied when a payload omits the `channel` field
    /// or supplies a value that doesn't decode as a `Channel.rawValue`.
    /// The user-authored Shortcut may legitimately omit the field for
    /// backward compatibility — defaulting to iMessage matches the
    /// behaviour of every Shortcut shipped before the multi-channel
    /// refactor. Hoisted so the default is greppable + pinned, and so
    /// a future "default to .sms for SMS-relay payloads" decision lands
    /// once. Pinned by
    /// `ShortcutsExportHandlerTests.testDefaultChannelIsImessage`.
    static let defaultChannel: Channel = .imessage

    /// Outgoing-message marker in the wire format. The Shortcut emits
    /// `{"from": "me", ...}` for messages the user sent and any other
    /// value (typically `"them"` or the sender's name) for incoming
    /// messages. Drift would silently flip authorship for every
    /// outgoing message in every imported thread. The same `me` literal
    /// is also `PromptBuilder.Template.speakerSelf` and
    /// `SearchIndex.outgoingSenderLabel` — three modules sharing one
    /// convention. Pinned by
    /// `ShortcutsExportHandlerTests.testOutgoingMarkerIsMe`.
    static let outgoingMessageMarker = "me"

    /// Parse `[Export]` out of a `replyai://import-messages?data=…` URL.
    /// Throws `.malformedPayload` for any structural failure (missing
    /// `data` param, malformed JSON, missing required fields).
    static func parse(url: URL) throws -> [Export] {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems,
              let raw = items.first(where: { $0.name == Self.payloadQueryParameterName })?.value,
              !raw.isEmpty,
              let data = raw.data(using: .utf8)
        else { throw ShortcutsExportError.malformedPayload }

        let decoder = JSONDecoder()
        let payload: [DTO]
        do {
            payload = try decoder.decode([DTO].self, from: data)
        } catch {
            throw ShortcutsExportError.malformedPayload
        }
        return payload.map { $0.toExport() }
    }

    // MARK: - DTO

    /// Wire format. Decoded directly from the JSON payload, then mapped
    /// to the strongly-typed `MessageThread` + `Message` pair the inbox
    /// expects. Keeping the DTO private isolates the wire format from
    /// the rest of the app — schema changes only touch this file.
    private struct DTO: Decodable {
        let id: String
        let displayName: String
        let preview: String?
        let channel: String?
        let messages: [MessageDTO]?

        struct MessageDTO: Decodable {
            let from: String
            let text: String
            let time: String?
        }

        func toExport() -> Export {
            let resolvedChannel = Channel(rawValue: (channel ?? ShortcutsExportHandler.defaultChannel.rawValue).lowercased()) ?? ShortcutsExportHandler.defaultChannel
            let preview = preview ?? messages?.last?.text ?? ""
            let thread = MessageThread(
                id: id,
                channel: resolvedChannel,
                name: displayName,
                avatar: String(displayName.prefix(1)),
                preview: preview,
                time: messages?.last?.time ?? "",
                chatGUID: id
            )
            let mapped: [Message] = (messages ?? []).map { dto in
                Message(
                    from: dto.from.lowercased() == ShortcutsExportHandler.outgoingMessageMarker ? .me : .them,
                    text: dto.text,
                    time: dto.time ?? ""
                )
            }
            return Export(thread: thread, messages: mapped)
        }
    }
}
