# 0001 - Project setup: Flutter, Android-first

## Status

Accepted (2026-09-24). The "thin client, no business logic" part is superseded by
[ADR 0003](0003-app-supports-musicdatabase.md).

## Context

MusicDatabaseApp needed a starting stack for a mobile frontend to the existing MusicDatabase
backend. The primary target is Android; iOS support may be added later.

## Decision

- Use Flutter/Dart for the client, generated via `flutter create` with `android` and `ios`
  platforms enabled, so an iOS build stays possible without a re-scaffold later.
- Keep this as a separate git repository from `MusicDatabase`, with no shared history.
- No state-management package, no networking layer, and no business logic in this app at
  bootstrap. The first commit is intentionally a static "Hello World" screen.
- How this app will talk to MusicDatabase (API shape, transport) is explicitly deferred to a
  future ADR, once there is a concrete feature that needs it.

## Consequences

- Adding real features will require deciding on a data-fetching approach and likely a
  state-management approach at that point — not decided yet, deliberately.
- Business logic changes belong in `MusicDatabase`; this app should stay a thin client.
