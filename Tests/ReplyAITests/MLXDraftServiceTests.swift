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
}
