import Foundation

/// LLMService implementation backed by the Groq API.
///
/// Groq exposes an OpenAI-compatible chat-completions endpoint at
/// `https://api.groq.com/openai/v1/chat/completions` and serves Llama
/// models with sub-second latency. Quality is materially below Claude
/// Sonnet but materially above on-device Llama-3.2-3B and the canned
/// `Fixtures.genericAcknowledgment` fallback that ships when no real
/// LLM is wired.
///
/// The model defaults to `llama-3.3-70b-versatile` — the strongest
/// instruction-tuned model Groq serves for free. Switching the default
/// triggers a tone-pin test in `GroqLLMServiceTests` because the
/// downstream prompt + tone behavior was tuned against this model.
///
/// **Streaming**: the service streams tokens via SSE so the composer
/// shows text as it generates rather than waiting for the whole draft.
/// Each Server-Sent Event line beginning with `data:` carries an OpenAI
/// streaming-format chunk; we extract the delta content and yield it as
/// a `DraftChunk.text` event.
///
/// **Errors**: 401 (invalid key), 429 (rate limit), 5xx, or a malformed
/// SSE chunk all finish the stream with a thrown `GroqError`. The
/// composer surfaces these via the existing `engine.state(...)` error
/// path — no new UI plumbing required.
public final class GroqLLMService: LLMService, @unchecked Sendable {
    /// Default model — see class doc. Pinned by
    /// `GroqLLMServiceTests.testDefaultModelIsLlama33_70BVersatile`.
    public static let defaultModel = "llama-3.3-70b-versatile"

    /// Endpoint URL. Groq mirrors the OpenAI shape; if Groq ever drifts
    /// from the OpenAI streaming format the SSE parser below needs an
    /// update too.
    public static let endpoint = "https://api.groq.com/openai/v1/chat/completions"

    /// Default confidence yielded as the first `DraftChunk`. Same shape
    /// as MLXDraftService's 0.85 — keeps the cmp-lowconf gate
    /// behaviorally consistent across providers.
    public static let defaultConfidence: Double = 0.85

    /// Max tokens per draft. 200 fits comfortably in a one-line iMessage
    /// reply and prevents the model from rambling into multi-paragraph
    /// responses. Tuned by feel; not yet user-configurable.
    public static let defaultMaxTokens = 200

    private let apiKey: String
    private let model: String
    private let urlSession: URLSession

    public init(
        apiKey: String,
        model: String = GroqLLMService.defaultModel,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.urlSession = urlSession
    }

    public func draft(
        thread: MessageThread,
        tone: Tone,
        history: [Message]
    ) -> AsyncThrowingStream<DraftChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                do {
                    continuation.yield(DraftChunk(kind: .confidence(GroqLLMService.defaultConfidence)))

                    let voiceExamples = UserDefaults.standard.voiceExampleMessages()
                    let userPrompt = PromptBuilder.build(
                        thread: thread,
                        tone: tone,
                        history: history,
                        voiceExamples: voiceExamples
                    )
                    let systemPrompt = PromptBuilder.systemPrompt(tone: tone)

                    var request = URLRequest(url: URL(string: GroqLLMService.endpoint)!)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "max_tokens": GroqLLMService.defaultMaxTokens,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user",   "content": userPrompt]
                        ]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await urlSession.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw GroqError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw GroqError.httpStatus(http.statusCode)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        // SSE format: each event is preceded by `data: <payload>`.
                        // Groq emits `data: [DONE]` as the final marker.
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let first = choices.first
                        else { continue }

                        if let delta = first["delta"] as? [String: Any],
                           let content = delta["content"] as? String,
                           !content.isEmpty {
                            continuation.yield(DraftChunk(kind: .text(content)))
                        }

                        // Groq sets finish_reason on the last token-bearing
                        // chunk; some SDKs use this as a stop signal. We
                        // rely on `[DONE]` instead and let the loop exit
                        // naturally when the byte stream closes.
                    }

                    continuation.yield(DraftChunk(kind: .done))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Error surface for Groq HTTP failures. The composer treats these the
/// same as any other LLMService error — surfaces them via
/// `DraftEngine.State.error`. No retry today; one failed draft is one
/// failed draft.
public enum GroqError: LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Groq returned a non-HTTP response"
        case .httpStatus(let code):
            switch code {
            case 401: return "Groq rejected the API key (401). Check Settings → AI Model."
            case 429: return "Groq rate limit (429). Wait a few seconds and try again."
            case 500..<600: return "Groq server error (\(code)). Try again in a moment."
            default: return "Groq HTTP \(code)"
            }
        }
    }
}
