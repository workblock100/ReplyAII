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
}
