---
name: finalize-change
description: 'Use at the end of a coding task in the MusicDatabaseApp repo to decide whether anything from this session is worth persisting for future AI agents, and if so, fold it into AGENTS.md or docs/agent-notes/ in place; also keeps the repo''s indexes (docs/menu-map.md, docs/index.md, topic-note index) in sync and drafts a ready-to-use commit message for the user to review and commit themselves (the skill never runs git add/commit/push). Trigger this when the user says things like "finalize this change", "wrap this up", "podsumuj zmiany", "zamknij temat", "udokumentuj to dla przyszłych agentów", "update the guidelines", or invokes /finalize-change directly at the close of a task. Do not trigger it mid-task, for routine code review, or for every small commit — only when the user is closing out work and wants durable lessons captured, not a changelog of everything that happened.'
---

# Finalize Change

Adapted from the skill of the same name in `../MusicDatabase`. Differences: this repo has no
`docs/systems/` or `tools/`, but it has `docs/menu-map.md` (the ID of every menu element), which
must track the code; and Flutter verification (`flutter analyze`/`flutter test`) is checked first.

## Why this exists

The sibling MusicDatabase repo used to accumulate a new root-level markdown report every time an
AI session finished non-trivial work (`OPTIMIZATION_SUMMARY.md`, `REFACTORING_NOTES.md`, …): five
unlinked files about the same effort, several contradicting the code by the time anyone read them.
This repo starts with the rule that prevented that: keep a small, fixed set of places up to date,
and only touch them when there's something durable to say. Most changes don't clear that bar, and
the right output of running this skill is often touching nothing at all.

## The places persistent knowledge can live

1. **`AGENTS.md`** (repo root) — the curated, always-read source of truth. Short, skimmable,
   edited in place. It describes how things currently are, never what happened when. Its
   "Current state", "Project layout" and "Coding conventions" sections go stale fastest.
2. **`docs/agent-notes/<topic>.md`** — one file per subsystem (currently `theming.md`,
   `ui-sizing.md`), for deeper rationale/tradeoffs that matter when working in that area but would
   be dead weight in every agent's default context. Indexed twice: one line under "Topic notes" in
   `AGENTS.md` and one line in `docs/agent-notes/README.md`.
3. **`docs/architecture.md`** — how the app is structured right now ("Current state") and where
   it's heading. Update it when the structure changes, not for features that fit the existing shape.

None of these ever gets a second file for the same subject or a dated entry appended at the bottom
— if you catch yourself about to add "## Update 2026-10-10" anywhere, stop and find the existing
section this belongs to instead.

## Step 1 — Gather what actually happened

1. Run `git status`, `git diff` **and** `git diff --cached` — the user often stages work in their
   IDE (VS Code / Android Studio) mid-session, so a plain `git diff` can miss half of it. Use
   `git log` for anything already committed this session. Don't rely on memory of the conversation
   for *what* changed — diffs don't lie about that.
2. Rely on the conversation for *why*: dead ends, constraints discovered the hard way, decisions
   made with the user (e.g. "no screen-size scaling", "theme isn't persisted yet"). That reasoning
   only exists in your context and is exactly what's worth capturing.
3. If the session changed Dart code, run `flutter analyze` and `flutter test` (both read-only)
   unless they already passed after the last code edit this session. Report failures in Step 4
   and don't present the change as finished — but don't start fixing code inside this skill
   unless the user asks.

## Step 2 — Decide if anything clears the bar

"Nothing to persist" is a healthy, common outcome. For each candidate fact ask: *would a future
agent get this right anyway from the diff, the code, or the commit message?* If yes, skip it.

Worth persisting, roughly in order of how likely they are to matter:

- A **hidden constraint or gotcha** that would silently break if unknown (e.g. system Back in
  `AppShell` pops nested routes directly, so sub-screens can't return results through `pop`).
- A change to **setup, entry points, or how to run/verify** something (build commands, device
  quirks, memory limits for Gradle).
- A **cross-cutting convention** now used across screens (e.g. colours only via `context.palette`,
  font sizes only via `AppFontSize`, no dummy elements — a feature is built or left out).
- A **decision made with the user** that a future agent might otherwise reverse.
- Deeper **subsystem-specific rationale** — why an approach was chosen, what was rejected, how a
  value was measured. That's `docs/agent-notes/` territory, not `AGENTS.md`.

Not worth persisting: ordinary bug fixes, small refactors, new menu items that follow the
existing pattern, anything self-explanatory from the diff. If the whole session was one of these,
say so plainly and stop — don't manufacture a note.

## Step 3 — Revise in place, don't append

For anything that clears the bar:

1. Pick the home: top-level convention/gotcha → `AGENTS.md`; deep subsystem detail →
   `docs/agent-notes/<topic>.md`; structural change → `docs/architecture.md`.
2. **Search that file first** for the same subject. If it's there, edit it — fix what's wrong,
   extend what's incomplete. Only add a new bullet/subsection when the subject isn't covered.
3. Before creating a new topic file, check the existing ones — amend the closest reasonable home
   rather than spinning up a narrower file. If you do create one, add its line to both indexes
   (`AGENTS.md` "Topic notes" and `docs/agent-notes/README.md`).
4. Running this skill twice on the same change should converge, never duplicate.
5. **Keep the indexes honest, mechanically.** Not "is this worth persisting" but "did the session
   change the *shape* of something that's indexed elsewhere":
   - **`docs/menu-map.md`** — any screen, menu, sheet or element added, removed, renamed or moved,
     or any element's behaviour changed (mark it implemented and describe what it does). Check by
     grepping the IDs and labels from the diff (`idPrefix:`, `_id = `, `MenuSheetEntry(`) against
     the file. This is the file the user uses to refer to UI elements, so a stale
     entry is a real bug.
   - **`docs/index.md`** — a top-level doc added, removed or renamed.
   - **`AGENTS.md` "Current state" / "Project layout"** — a new top-level directory or file role
     under `lib/src/`, or a statement there that the session made false (e.g. "no state
     management").
   - **`docs/decisions/`** — a choice that's expensive to reverse or affects the whole app (the
     MusicDatabase transport, a state-management or storage package, a navigation rewrite) may
     deserve an ADR, indexed from `docs/index.md`. `AGENTS.md` requires one before wiring up any
     backend transport. When in doubt, ask the user rather than guessing.
   - **`.claude/skills/`** — if a skill was added or changed and another skill refers to its steps
     (e.g. share-build-tailscale reuses run-on-physical-phone's build steps), make sure those
     cross-references still point at the right step names.
   If nothing changed shape, there's nothing to touch here.

## Step 4 — Report back

This skill writes directly (no draft-and-confirm step; the user reviews via `git diff`). Give a
short, concrete summary in Polish: which file(s) you touched and, in a sentence each, what changed.
Include the `flutter analyze`/`flutter test` result from Step 1. If you decided nothing was worth
persisting, say so explicitly and why (e.g. "zwykła poprawka, w pełni wyjaśniona przez diff") — a
skill that silently does nothing is indistinguishable from one that forgot to run.

## Step 5 — Draft a commit message (text only — never commit it yourself)

Draft a ready-to-use commit message covering the session's actual changes (the whole diff from
Step 1, not just this skill's edits) and put it in a fenced code block in your reply.

**Never run `git add`, `git commit`, `git push` or any other git write** — `AGENTS.md` → Git policy
says not to commit unless explicitly asked, and the user pushes from their own IDE. This step
produces text only.

Match this repo's commit style — check `git log --format="%s%n%b%n---" -10` first. As of this
writing: a single terse subject line, English, clauses joined by `" - "` (e.g. `QA tool skill -
run-on-physical-phone`), no body, no Conventional Commits prefix, no trailer. Follow the user's own
recent commits if they visibly drift from that.

Keep it under 400 characters. If everything won't fit, lead with the most significant behavioral
change and drop the rest — don't compress into cryptic abbreviations.

Leave documentation-only edits out of the description entirely (no "update AGENTS.md",
"document X in menu-map.md" clauses) — describe only the code change. The exception is a session
whose *only* change was documentation; then say so plainly.

If the working tree contains changes this session didn't make (the user often works in parallel,
or earlier sessions left uncommitted work), **don't describe them as this session's work.** Scope
the message to this session's changes when they're cleanly separable by file; otherwise say in
your chat reply (not in the message) that unrelated changes are mixed in and should be split
before committing.
