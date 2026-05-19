# Security Policy

ReplyAI runs on your Mac and handles your personal messages. We take security and privacy seriously and want to make it easy for researchers, beta testers, and contributors to report issues responsibly.

## Reporting a vulnerability

**Do not open a public issue for security reports.** Email the maintainer directly at `security@replyai.co` (or, until that mailbox is live, `workblock100@gmail.com`) with:

- A clear description of the issue and the affected component (Sources/ReplyAI*, scripts/, the bundled .app, etc.)
- Steps to reproduce, ideally on a debug build (`./scripts/build.sh debug`)
- The macOS version, Mac model, and ReplyAI commit hash you tested against
- Optionally: a suggested fix or mitigation

You should receive an acknowledgement within **5 business days**. We'll triage the report and let you know whether we consider it in-scope, the expected remediation timeline, and whether a CVE is appropriate.

## In scope

- Unauthorized access to local message data (`~/Library/Messages/chat.db`, Slack tokens in Keychain, draft text on disk)
- Credential leakage (Slack OAuth tokens, Apple ID app-specific passwords, MLX model weights)
- Code execution paths reachable from a malicious message body, attachment, or AppleScript event
- Permission-escalation bugs in the FDA / Automation / Notifications flows
- Anything that could exfiltrate message content off the device against the user's intent (the on-device-only privacy promise in `WelcomeGate.Strings.heroSubtitle`)

## Out of scope

- Bugs that require physical access to an already-unlocked Mac
- Issues that require the user to disable macOS Gatekeeper or run a modified bundle
- Denial-of-service on the user's own machine that can't be triggered remotely
- Vulnerabilities in upstream dependencies (`mlx-swift`, `swift-huggingface`, `swift-transformers`) — report those upstream first; we'll coordinate.

## Disclosure

We follow a coordinated-disclosure model:

1. You report the issue privately.
2. We acknowledge, investigate, and prepare a fix.
3. We coordinate a release date with you. Default window: 90 days after acknowledgement, or sooner if a fix lands.
4. We publish a security advisory on the release date crediting you (unless you prefer to stay anonymous).

If a vulnerability is being actively exploited in the wild, we'll move faster — please flag the urgency in your report.

## Bug bounty

There is no formal bug bounty program at this stage. We will credit serious reports in the release advisory and the `CONTRIBUTING.md` thanks list once that exists.
