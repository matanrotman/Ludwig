# Meeting Transcription Integration

## Goal
Connect the desktop app to my self-hosted transcription server so I can transcribe meetings directly into AppFlowy documents.

## Current state
Not started. No integration exists yet.

## To confirm with me (interview before building)
- My server's API shape: streaming (live partial results over WebSocket) or batch (send audio, wait for a finished transcript)?
- Trigger: live during a call, or upload/process a recording afterward?
- Where transcripts should land: a new document, appended to an open one, a dedicated space?
- Speaker labels or timestamps, if my server provides them?
- UI trigger: toolbar button, command menu, shortcut?
- Error handling: what should happen if the server is unreachable mid-meeting?

## Multi-user readiness (added 2026-07-17 — see CLAUDE.md "Designing for other users")
This one is **inherently personal**: it targets my own self-hosted transcription server. That's fine to build local-only-for-me first, but the design rule still applies — the server endpoint (URL, any auth) must be **user-configurable, never hardcoded**, so a future multi-user version is "point at your own server" rather than a rewrite. The interview above should treat "where does the server address come from" as a first-class question, and the CLAUDE.md privacy rule applies (flag the external-service trade-off, use the user's own config). A general version would also need graceful behavior when no server is configured (the feature simply stays off), not a crash or a broken UI.

## Files / interfaces involved
*Fill in once we've explored the codebase together.*

## Out of scope
*Fill in during the interview.*

## Verification
*How we'll know this is done — fill in during the interview.*

## Session Log
*Empty — the first dated entry gets added here after our first working session on this feature.*
