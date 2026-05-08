import XCTest
@testable import ReplyAI

/// Pin tests for `MLXDraftService` constants. We don't load the model in
/// CI — that's a 2 GB download — so this file only covers the surface
/// that doesn't require a `ModelContainer`. The streaming behavior is
/// already exercised through `StubLLMService` in `LLMServiceTests`; the
/// MLX path is integration-tested manually per `AGENTS.md`.
final class MLXDraftServiceTests: XCTestCase {

    /// `MLXDraftService.defaultModelID` is the Hugging Face slug that
    /// gets baked into every shipped build's first-draft flow. Drift
    /// here triggers a ~2 GB re-download on every running user's next
    /// launch (model cache lives at `~/Library/Caches/huggingface/hub/`,
    /// keyed by slug). The autopilot also reasons about this value at
    /// `REP-ALERT-260504-1650` (the model-download exit bug). Pin so a
    /// future "swap to Llama-3.2-1B for faster cold-start" lands in code
    /// review, not as a silent OTA storage hit.
    func testDefaultModelIDIsLlama32_3BInstruct4bit() {
        XCTAssertEqual(MLXDraftService.defaultModelID,
                       "mlx-community/Llama-3.2-3B-Instruct-4bit",
                       "defaultModelID drift triggers a ~2 GB Hugging Face re-download for every shipped user on next launch")

        let svc = MLXDraftService()
        XCTAssertEqual(svc.modelID, MLXDraftService.defaultModelID,
                       "no-arg init must route through Self.defaultModelID — otherwise the static constant becomes dead code while the literal slug lives on in the init signature")
    }

    /// The `init(modelID:)` arg is the seam tests and migration code use
    /// to pin a frozen model. Confirm that constructing with an explicit
    /// slug overrides the default — without this, a refactor that
    /// silently dropped the parameter (e.g. switched to a hardcoded
    /// constant inside the body) would bypass every test that's
    /// trying to exercise a different model.
    func testCustomModelIDIsRespected() {
        let svc = MLXDraftService(modelID: "test-org/test-model-7b")
        XCTAssertEqual(svc.modelID, "test-org/test-model-7b",
                       "init(modelID:) must store the passed-in value verbatim — drift here breaks every migration / forced-model test")
    }

    /// Every MLX draft yields its first chunk as `.confidence(defaultDraftConfidence)`
    /// before any model tokens stream. The composer routes drafts below the
    /// low-confidence threshold to the `cmp-lowconf` screen instead of the
    /// normal three-tone composer. 0.85 sits comfortably above the cutoff, so
    /// today every MLX draft renders as a normal draft — but a refactor that
    /// dropped this to e.g. 0.4 (because someone read "MLX is uncertain by
    /// default") would silently flip every MLX-generated draft into the
    /// low-confidence UX, and drift to 1.0 would hide any future real
    /// low-confidence signal once we wire one. Pin the literal so either
    /// drift surfaces in code review.
    func testDefaultDraftConfidenceIsZeroPointEightFive() {
        XCTAssertEqual(MLXDraftService.defaultDraftConfidence, 0.85, accuracy: 1e-9,
                       "MLXDraftService.defaultDraftConfidence drift either flips MLX drafts into the low-confidence composer (too low) or hides future real low-confidence signal (too high)")
    }

    // MARK: - loadProgress copy pins

    /// `preparingMessage` is the very first thing the user sees in the
    /// composer banner when the model isn't cached yet — it owns the
    /// 0%-progress window before any download bytes flow. Drift to a
    /// blank string or the empty literal would make the composer look
    /// frozen during cold-start. Distinct from `warmingMessage` so the
    /// user can see forward progress (preparing → downloading → warm).
    func testPreparingMessageLiteralIsExact() {
        XCTAssertEqual(MLXDraftService.preparingMessage,
                       "Preparing on-device model…",
                       "preparingMessage owns the 0%-progress UX window — drift here is the only signal the user has during cold-start")
    }

    /// `warmingMessage` is yielded with `fraction: 1` after download
    /// completes but before MLX finishes mapping weights into memory
    /// (~3-5s on M1). Drift to "Loading…" or sharing the
    /// preparingMessage literal would erase the user-visible
    /// distinction between the two phases — making the banner look
    /// stuck at "Preparing…" during a long warmup.
    func testWarmingMessageLiteralIsExact() {
        XCTAssertEqual(MLXDraftService.warmingMessage,
                       "Warming weights…",
                       "warmingMessage owns the post-download / pre-token UX window — must read distinctly from preparingMessage so the user sees forward progress")
    }

    func testPreparingAndWarmingMessagesAreDistinct() {
        // The two messages must remain visually distinct so a user
        // staring at the banner can see the load progress through its
        // phases. A future refactor that DRY'd both into one constant
        // would hide phase progression.
        XCTAssertNotEqual(MLXDraftService.preparingMessage,
                          MLXDraftService.warmingMessage,
                          "preparing and warming messages must remain distinct or the user sees a stuck banner during the warmup phase")
    }

    /// Format pin: the byte-aware download message must produce the
    /// `Downloading model · X of Y` shape. The autopilot's incident
    /// for `REP-ALERT-260504-1650` references a 1.8 GB download, so
    /// the GB-rendering path is the dominant case for the running
    /// product — pin both render branches (small + large) so a future
    /// "let's reformat" lands once.
    func testDownloadingMessageRendersBytesInGigabytesWhenLarge() {
        // 1.8 GB ≈ 1,932,735,283 bytes (the value seen in the incident).
        let msg = MLXDraftService.downloadingMessage(
            completedBytes: 905_625_472, // ~864 MB
            totalBytes:    1_932_735_283 // ~1.8 GB
        )
        XCTAssertEqual(msg, "Downloading model · 864 MB of 1.8 GB",
                       "byte-aware download copy must read MB on the small side and GB on the large side — drift here changes how every shipped user perceives a 1.8 GB download")
    }

    func testDownloadingMessageFormatsBothBytesInMegabytesWhenBothSmall() {
        // 50 MB / 200 MB scenario — neither side crosses the 1024 MiB
        // threshold so the format must use MB for both halves.
        let msg = MLXDraftService.downloadingMessage(
            completedBytes:  52_428_800,  // 50 MB
            totalBytes:     209_715_200   // 200 MB
        )
        XCTAssertEqual(msg, "Downloading model · 50 MB of 200 MB",
                       "MB threshold must apply per-argument — small/small download reads MB/MB")
    }

    /// Format pin: when the server doesn't advertise a `Content-Length`
    /// (or `totalUnitCount == 0`), the banner falls back to a
    /// percentage. The percentage is derived from `Progress.fractionCompleted`
    /// — drift in either the format template or the multiplication
    /// would silently render "0%" forever.
    func testDownloadingMessageFractionRendersPercentageWithoutDecimal() {
        XCTAssertEqual(MLXDraftService.downloadingMessage(fraction: 0.47),
                       "Downloading model · 47%",
                       "fraction-form download copy renders integer percentage — `\\(Int(fraction * 100))%` — drift here makes the banner stale during pre-Content-Length window")
        XCTAssertEqual(MLXDraftService.downloadingMessage(fraction: 0),
                       "Downloading model · 0%",
                       "0% boundary case must render as `0%` not `0.0%`")
        XCTAssertEqual(MLXDraftService.downloadingMessage(fraction: 1),
                       "Downloading model · 100%",
                       "100% boundary case must round-trip to `100%`")
    }

    /// Format pin: the byte formatter is the policy `downloadingMessage`
    /// uses for both `completedBytes` and `totalBytes`. The 1024 MiB
    /// crossover is the rule the inline closure used to apply — pinning
    /// the threshold + precisions so a future "let's switch to powers
    /// of 1000" or "let's use 2 decimals for GB" surfaces in review.
    func testFormatBytesRendersMegabytesBelowOneGibibyte() {
        XCTAssertEqual(MLXDraftService.formatBytes(0), "0 MB",
                       "zero bytes still renders MB form — drift here would make a never-started download read as `0 GB`")
        XCTAssertEqual(MLXDraftService.formatBytes(50 * 1024 * 1024), "50 MB",
                       "exact 50 MiB rounds to `50 MB` (no decimal)")
        // 1023 MiB — just under threshold.
        XCTAssertEqual(MLXDraftService.formatBytes(1023 * 1024 * 1024), "1023 MB",
                       "just-below-threshold renders MB; drift would prematurely hop to GB form")
    }

    func testFormatBytesRendersGigabytesAboveOneGibibyte() {
        // 1.8 GiB ≈ 1,932,735,283 bytes — the value seen in
        // REP-ALERT-260504-1650.
        XCTAssertEqual(MLXDraftService.formatBytes(1_932_735_283), "1.8 GB",
                       "1.8 GiB rounds to `1.8 GB` (one decimal) — pinned by the autopilot incident reference")
        XCTAssertEqual(MLXDraftService.formatBytes(2 * 1024 * 1024 * 1024), "2.0 GB",
                       "exact 2 GiB renders `2.0 GB` (one decimal) — drift to `2 GB` would expose a precision change at the boundary")
    }

    /// Pin the 1024-MiB threshold boundary (the `mib > 1024` cutoff
    /// inside `formatBytes`). A value of *exactly* 1024 MiB is below
    /// the strict-greater-than threshold and renders as `"1024 MB"`,
    /// not `"1.0 GB"`. The first byte over (1024 MiB + 1 byte) flips
    /// to GB form. Both sides matter — the strict inequality means a
    /// future swap to `>=` would silently flip 1 GiB-exactly downloads
    /// from "1024 MB" to "1.0 GB" mid-fire of an in-progress download
    /// banner. Pin so the boundary direction can't drift.
    func testFormatBytesAtExactly1024MibStaysInMegabytes() {
        XCTAssertEqual(MLXDraftService.formatBytes(1024 * 1024 * 1024), "1024 MB",
                       "exactly 1024 MiB (== 1 GiB) renders as MB (1024) — `mib > 1024` is strict-greater-than; drift to `>=` would flip this case to `1.0 GB`")
        XCTAssertEqual(MLXDraftService.formatBytes(1024 * 1024 * 1024 + 1), "1.0 GB",
                       "1024 MiB + 1 byte must flip to GB form — pin the first-byte-over boundary so a future precision tweak surfaces here, not in user-visible banner copy")
    }

    /// Pin the byte-form download separator characters. The current
    /// banner reads `"Downloading model · 864 MB of 1.8 GB"` — that's
    /// space + U+00B7 MIDDLE DOT + space between `model` and the byte
    /// count, and the literal " of " between completed and total. Both
    /// shapes match Apple's Storage settings convention. Drift toward
    /// U+2022 BULLET, an en/em dash, or "/" between completed and total
    /// would silently change visual rhythm for every shipped user
    /// staring at a 30-90s download banner. Pin so a future "let's use
    /// `/` for terseness" lands in code review, not as a kerning shift.
    func testDownloadingMessageBytesFormUsesMiddleDotAndOfSeparators() {
        let msg = MLXDraftService.downloadingMessage(
            completedBytes: 100 * 1024 * 1024,
            totalBytes:     200 * 1024 * 1024
        )
        XCTAssertEqual(msg, "Downloading model · 100 MB of 200 MB",
                       "byte-form separator shape (space + U+00B7 + space, then ` of `) is the user-visible byte rhythm; drift would silently change it for every download banner")
        XCTAssertTrue(msg.contains(" \u{00B7} "),
                      "separator between `model` and the byte count must be space + U+00B7 MIDDLE DOT + space — drift to U+2022 BULLET (`•`) or em-dash would change visual weight without changing source text obviously")
        XCTAssertTrue(msg.contains(" of "),
                      "between completed and total must be ` of ` literal — drift to `/` or `→` lands silently in source review unless pinned")
        XCTAssertFalse(msg.contains(" \u{2022} "),
                       "byte-form must NOT use U+2022 BULLET — that's the visually-similar but heavier glyph; pinning rules out an autocorrect-style drift")
    }

    /// Pin the same separator shape for the fraction-form fallback
    /// banner — the path that fires when `Progress.totalUnitCount`
    /// briefly reports 0 before the first chunk lands. Drift here would
    /// produce a banner where the byte form and the fraction form read
    /// inconsistently within the same download (server stops sending
    /// Content-Length mid-stream → fallback → look changes). Pin so
    /// both forms keep the same separator family.
    func testDownloadingMessageFractionFormUsesMiddleDotSeparator() {
        let msg = MLXDraftService.downloadingMessage(fraction: 0.42)
        XCTAssertEqual(msg, "Downloading model · 42%",
                       "fraction-form must read `Downloading model · NN%` with the same MIDDLE DOT separator as the byte form; drift here would let the two render shapes diverge mid-download")
        XCTAssertTrue(msg.contains(" \u{00B7} "),
                      "fraction-form separator must match byte-form's space + U+00B7 MIDDLE DOT + space")
        XCTAssertFalse(msg.contains(" of "),
                       "fraction-form must NOT include the byte-form ` of ` separator — drift toward a hybrid rendering would clutter the banner")
    }

    /// Pin the `Int()` truncation policy in `downloadingMessage(fraction:)`.
    /// `0.999 * 100 = 99.9`, and `Int(99.9) = 99` — so a banner reading
    /// 99.9% complete renders as `"99%"`, not `"100%"`. This is the
    /// "surprising-but-safe" shape: the banner never prematurely flips
    /// to 100% before the last chunk actually lands. A future refactor
    /// to `Int(fraction.rounded() * 100)` or `Int((fraction * 100).rounded())`
    /// would silently flip many in-flight downloads to 100% earlier and
    /// erode the "still working" signal during the warmup window.
    func testDownloadingMessageFractionTruncatesAtBoundary() {
        XCTAssertEqual(MLXDraftService.downloadingMessage(fraction: 0.999),
                       "Downloading model · 99%",
                       "0.999 fraction must truncate to 99% (not round to 100%) — drift here would prematurely show 100% before the last byte lands and erode the still-working signal")
        XCTAssertEqual(MLXDraftService.downloadingMessage(fraction: 0.005),
                       "Downloading model · 0%",
                       "0.005 fraction floors to 0% (Int truncation toward zero) — drift to ceiling/round would show 1% before any meaningful progress")
        XCTAssertEqual(MLXDraftService.downloadingMessage(fraction: 0.5),
                       "Downloading model · 50%",
                       "exactly 50% rounds-trips through truncation cleanly (no decimal noise)")
    }

    /// Pin the no-clamp behavior of `downloadingMessage(fraction:)`.
    /// `Foundation.Progress.fractionCompleted` is documented to fall in
    /// 0...1, but in practice we've seen MLX/HuggingFace fire callbacks
    /// where total is briefly underestimated and the fraction crosses
    /// 1.0 — `Int(1.5 * 100) = 150` produces `"Downloading model · 150%"`.
    /// Surprising-but-safe: the banner reveals the upstream miscount
    /// rather than masking it. Pin so a future "let's clamp to 100%
    /// for cosmetic safety" lands as a deliberate change — clamping
    /// would hide an upstream bug from triage.
    func testDownloadingMessageFractionDoesNotClampAboveOneHundred() {
        XCTAssertEqual(MLXDraftService.downloadingMessage(fraction: 1.5),
                       "Downloading model · 150%",
                       "fraction > 1.0 renders verbatim (no clamp) — drift toward `min(1.0, fraction)` would mask a real upstream Progress miscount under a cosmetic 100% ceiling")
        XCTAssertEqual(MLXDraftService.downloadingMessage(fraction: 2.0),
                       "Downloading model · 200%",
                       "fraction == 2.0 renders 200% — pins the no-clamp policy across both `> 1` and integer multiples")
    }

    /// Pin the U+2026 HORIZONTAL ELLIPSIS character on `preparingMessage`
    /// and `warmingMessage`. The literal-equality pins above already lock
    /// the byte sequence, but a future "normalize ellipses to three
    /// ASCII dots for grep-friendliness" refactor that ran across the
    /// repo would change `…` (1 char) to `...` (3 chars) and slip past
    /// any code review that didn't look character-by-character. Pin the
    /// trailing character explicitly so the swap surfaces here, not as
    /// a silent kerning change in the composer banner — Apple Mac
    /// applications conventionally use U+2026 for tighter kerning vs
    /// three-dot composition.
    func testPreparingMessageEndsWithSingleEllipsisCharacter() {
        XCTAssertEqual(MLXDraftService.preparingMessage.last, "\u{2026}",
                       "preparingMessage must end with U+2026 HORIZONTAL ELLIPSIS, not three U+002E FULL STOPs — `last` of three dots would be `.`, exposing the swap")
        XCTAssertFalse(MLXDraftService.preparingMessage.hasSuffix("..."),
                       "must not end in three ASCII dots — pinning the negative case so a normalize-ellipses refactor lands deliberately")
    }

    func testWarmingMessageEndsWithSingleEllipsisCharacter() {
        XCTAssertEqual(MLXDraftService.warmingMessage.last, "\u{2026}",
                       "warmingMessage must end with U+2026 HORIZONTAL ELLIPSIS — drift to `...` (three dots) changes kerning vs Apple convention")
        XCTAssertFalse(MLXDraftService.warmingMessage.hasSuffix("..."),
                       "must not end in three ASCII dots")
    }
}
