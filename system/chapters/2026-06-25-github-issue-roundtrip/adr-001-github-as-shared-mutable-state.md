# ADR-001 — GitHub becomes shared mutable state

**Status:** Accepted (2026-06-25). Governs the `2026-06-25-github-issue-roundtrip` chapter.
**Context owner:** System Track (the Ralph Loop improving itself).
**Companion:** `prd.md` (same folder) holds *what & why* for the features; this ADR pins *the one irreversible decision and its invariants*. Read this before implementing any write-back path.

> **Cold-start note.** "The loop" is `scripts/ralph-loop.sh`, a Bash orchestrator that builds software one story per fresh `claude -p` process. "Path A" is its `--issue N` mode, which today *reads* a GitHub issue (via the `gh` CLI) and plans+builds it, but never writes back. This ADR records the decision to let the loop *write* to GitHub, and what that costs.

---

## Decision

The loop will write to GitHub (comments, labels, branches, draft PRs) as part of the "Round Trip" feature. We accept the consequence: **the source of truth for an in-flight issue moves from "local git, single writer" to "GitHub, shared mutable state with multiple writers" (the loop, humans, and other bots).**

This is the **Rubicon**. Before it, the loop is a pure read-over-GitHub function with zero external blast radius — a misfire wastes local tokens. After it, the loop has a blast radius on a repo other people watch — a misfire posts wrong comments, flips wrong labels, or opens duplicate PRs, with real notifications to real people. The decision is reversible in code (remove the write calls) but not in consequence (a wrong public comment is already sent).

## Why accept it

The read-only loop abandons the human at the finish line: results live only in the operator's local terminal. The entire value of "issue → reviewable result → merge" requires writing the result back to where the human lives. There is no way to deliver the core job (see `prd.md` §2) without crossing the Rubicon. We cross it deliberately, with the invariants below as guardrails.

## Invariants (mandatory acceptance criteria on every write-touching story)

### I1 — `--write` is default-off and centrally gated
- A single flag (`--write`, backed by `GITHUB_WRITE`, default `0`) gates **every** GitHub mutation.
- All writes funnel through three guarded helpers — `gh_comment_op`, `gh_label_op`, `gh_pr_op` — each of which, when `GITHUB_WRITE=0`, logs `[dry] gh …` and returns `0` without touching the network.
- **Acceptance test:** with `--write` off, the loop's externally observable behavior is byte-identical to today's read-only Path A. Every `--dry-run-prompts` smoke and every CI run executes with the flag off, so the network is never touched in tests. *Build the three helpers before any feature that calls them.*

### I2 — Idempotency is mandatory
Re-running any phase must **converge** to the same GitHub state, never duplicate it. "Running phase N twice produces the same GitHub state as running it once."
- **Self-updating comment:** one comment, found-by-marker and edited in place. Delimit the loop-managed region with HTML-comment fences (`<!-- RALPH:BEGIN -->` … `<!-- RALPH:END -->`); regenerate the fenced block from local git state on each call so re-runs converge. **Fail closed:** if the fences are missing, duplicated, or unbalanced, abort the edit, log, and continue the build — never write a body you cannot round-trip, never clobber human-written content outside the fences.
- **Draft PR:** persist the PR URL to `docs/prd/issue-N-pr.txt` at creation; on re-run, `gh pr view` that URL instead of re-creating. Re-create only on a genuine 404.
- **Labels:** every transition is a single `gh issue edit --add-label NEW --remove-label OLD` call (the command accepts both flags at once), so a crash mid-transition lands the same terminal state regardless of where it died. Never split add/remove across two invocations.

### I3 — No auto-merge, no auto-close
The loop never merges or closes its own PR/issue. The human's thumb stays on the merge button. Rationale: the day the tool resolves its own issues unwatched is the day the human stops reading what it does — and an autonomous agent nobody reads is a liability wearing a feature's clothes.

### I4 — Blast radius is priced before Round Trip ships
Before the Round Trip feature is accepted, answer in its issue: *when `--write` is on and the loop opens a wrong PR / posts a wrong comment on a watched repo, what is the undo path, and what does the misfire cost?* That answer is the first acceptance criterion of Idea 1, not a footnote.

## The graduation tripwire (deferred decision, recorded so a future session doesn't re-litigate it)

The loop is ~2256 lines of Bash today. Idempotency logic, `gh` error handling, multi-writer reconciliation, and (eventually) concurrent worktree state are exactly the class of problem where Bash stops paying rent and a typed runtime (a small Node orchestrator, or a library like `mattpocock/sandcastle`) starts. **We are NOT committing to that migration now.** We record the tripwire so it's an observation, not an argument:

> **Revisit the Bash-vs-typed-runtime decision when any two of these hold:** (a) idempotency/reconciliation logic exceeds ~300 lines of Bash; (b) `gh` error-handling branches outnumber feature branches in a function; (c) true concurrency (Idea 5 v2) requires coordinating shared state across worktrees that Bash cannot express without race-prone temp files.

Until a tripwire trips, Bash remains the orchestrator — "boring technology for stability," and the demo's filesystem-as-state ethos still holds.

## Consequences

- **Positive:** the loop delivers reviewable results where humans live; the round trip closes; trust becomes measurable (merge-as-is rate).
- **Negative / accepted:** mandatory idempotency complexity in Bash; a real external blast radius requiring the `--write` default-off guardrail; a new dependency on `gh` *write* scopes (the token must be authorized to comment/label/open PRs).
- **Watch:** the dogfooding-recursion risk (the loop scanning the very issues that describe how it should write) — mitigated by the scan-excluded `roadmap` label until Triage (Idea 4) exists. See `prd.md` §6.
