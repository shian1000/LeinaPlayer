# Architecture

## Current state

Bootstrap only. `lib/main.dart` builds a `MaterialApp` with one static screen ("Hello World").
There is no layering yet — this document describes the intended shape as features get added, not
what exists today.

## Intended shape (not yet implemented)

- **`lib/main.dart`** — app entry point and top-level `MaterialApp` setup only.
- **`lib/src/screens/`** — one widget tree per screen.
- **`lib/src/widgets/`** — shared widgets reused across screens.
- **`lib/src/data/`** — the client for talking to MusicDatabase, and the models it returns.
  Nothing here yet — introduce it only once a screen actually needs real data, and record how the
  app talks to the backend as an ADR in [`decisions/`](decisions/) before wiring it up.

## Boundary with MusicDatabase

This app must not reimplement business logic (matching, enrichment, database schema
assumptions) that belongs in [`MusicDatabase`](../../MusicDatabase). It consumes what that
backend exposes. If a screen seems to need logic that isn't available from the backend yet, that's
a sign the backend needs a new endpoint/capability — not that this app should grow one locally.
