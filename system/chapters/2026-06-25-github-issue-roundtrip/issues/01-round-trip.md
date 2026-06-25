> **Idea 1 / 5 · the spine** · epic: GitHub Issue Round-Trip & Autonomy
> Source of truth: [`prd.md` §3 Idea 1](https://github.com/seevali/ralph-loop-demo/blob/main/system/chapters/2026-06-25-github-issue-roundtrip/prd.md) · invariants: [`adr-001`](https://github.com/seevali/ralph-loop-demo/blob/main/system/chapters/2026-06-25-github-issue-roundtrip/adr-001-github-as-shared-mutable-state.md)

## Context (cold-start)

As of 2026-06-25, the Ralph Loop's `--issue N` mode (Path A) reads a GitHub issue via the `gh` CLI, plans it (PRD + epic), and builds it — but is **read-only against GitHub**. The work lands as local `feat(<id>):` commits; the issue author sees nothing. `gh` is currently called at four read-only sites in `scripts/ralph-loop.sh` (auth check, repo view, issue view).

## Problem

The loop abandons the human at the finish line. There is no reviewable result where the human lives — no branch, no pull request, no status on the issue. To act on the loop's output, a human must excavate the local `git log`.

## Proposed mechanism

Add GitHub **write-back**, `gh`-only (no octokit/REST), behind a `--write` flag (default off):

1. **Central guard first.** Add `GITHUB_WRITE` (default `0`) and three helpers — `gh_comment_op`, `gh_label_op`, `gh_pr_op` — that execute `gh` only when `GITHUB_WRITE=1`, else log `[dry] gh …` and return 0.
2. **Branch + draft PR at intake.** After `run_intake_phase()` writes `docs/epics/issue-N.md`: create branch `ralph/issue-N`, push, `gh pr create --draft --base main --head ralph/issue-N --title … --body-file docs/prd/issue-N.md`; capture the URL → persist to `docs/prd/issue-N-pr.txt`.
3. **Self-updating issue comment.** One comment, edited in place via HTML-comment fences (`<!-- RALPH:BEGIN -->` … `<!-- RALPH:END -->`), regenerated from local git state each update (🔵 planning → 🟡 building story X/Y → 🟢 done, PR link). Fail closed on malformed fences.
4. **Verdict-gated labels.** Drive labels off the existing review contract (first line `REVIEW_PASSED` / `REVIEW_FAILED`): build start `ralph:building`; per story `ralph:needs-fix` ↔ `ralph:in-review`; all green → `ralph:done`. Each transition is a single `gh issue edit --add-label NEW --remove-label OLD` call.
5. **Finish.** On all stories green: `gh pr ready`, and a final issue comment linking the PR.

**Files touched:** `scripts/ralph-loop.sh` (intake, per-story commit, completion blocks); new artifacts `docs/prd/issue-N-pr.txt`.

## Acceptance criteria

- [x] With `--write` **off**, externally observable behavior is byte-identical to today's read-only Path A (verified by `--dry-run-prompts` + an error-path smoke; network never touched). *(Slice 1: central gate `GITHUB_WRITE` + `gh_comment_op`/`gh_label_op`/`gh_pr_op` land no-op-by-default; `tests/slice1-write-guard-smoke.sh` proves the `--dry-run-prompts` byte-diff is zero vs `tests/dry-run-prompts.golden` and that all three helpers log `[dry] gh …`, return 0, and never invoke `gh` with `--write` off. Re-confirm once call sites are wired in later slices.)*
- [ ] With `--write` **on**, running `--issue N --write` creates branch `ralph/issue-N`, opens exactly one draft PR, and posts exactly one issue comment linking it. *(Slices a + b deliver the branch, its push, and exactly one draft PR via `ensure_issue_pr`; the linking issue **comment** is slice c — leave unticked until then.)*
- [ ] **Idempotency:** re-running the same issue does not create a second PR or a second comment, and does not churn labels (PR found via `docs/prd/issue-N-pr.txt`; comment edited in place; labels via single add/remove calls). *(Slice b delivers the **PR** half: `ensure_issue_pr` persists the URL to `docs/prd/issue-N-pr.txt` and reuses it via `gh pr view` (re-creating only on a genuine 404), so re-runs converge to one PR — proven by `tests/slice-b-draft-pr-smoke.sh`. Comment/label idempotency are slices c/d.)*
- [x] **Branch-before-commit invariant:** assert `git rev-parse --abbrev-ref HEAD == ralph/issue-N` before the dev loop; hard-fail otherwise (so story commits never land on `main`). *(Slice a: `ensure_issue_branch()` runs in the Phase 0 gate immediately before `main()`; creates/resumes `ralph/issue-N` (local, no push) and `exit 1`s if HEAD isn't the issue branch. `tests/slice-a-issue-branch-smoke.sh` proves create, base-branch protection, idempotent resume, no-push, and the hard-fail path.)*
- [x] **Blast-radius answer (ADR I4):** the issue documents the undo path and cost of a wrong `--write` action on a watched repo. *(Slice b: see [§ Blast-radius answer (ADR-001 I4)](#blast-radius-answer-adr-001-i4) below — undo paths for a wrong push/PR, the irreversible cost (notifications + public record), and why the damage ceiling is "noise," never merged code.)*
- [x] No auto-merge, no auto-close (ADR I3). *(Slice b opens the PR as `--draft` and no code path readies, merges, or closes it; `gh pr ready` is reserved for the finish step. The later comment/label slices add no merge/close path either.)*
- [ ] `prd.md` §3 Idea 1 matches shipped behavior (anti-drift DoD).

## Blast-radius answer (ADR-001 I4)

ADR-001 invariant **I4** requires this issue to price the blast radius *before* any `--write` path is considered done: when `--write` is on and the loop opens a wrong draft PR or pushes a wrong branch to a **watched** repo (one other people are subscribed to), what is the undo path, and what does the misfire cost? Slice b is the first slice with live write paths (`ensure_issue_pr` — a branch push plus one draft PR), so the answer lands here.

### What a misfire looks like

With `--write` on, two GitHub mutations fire at intake:

1. **Branch push** — `git push -u origin ralph/issue-N` publishes a local branch to the remote. A new branch ref appears; any CI/automation keyed to branch-creation may run.
2. **Draft PR** — `gh pr create --draft --base main --head ralph/issue-N` opens a pull request against `main`. Opening a PR (even a draft) notifies repo watchers and PR subscribers, can auto-request reviewers via CODEOWNERS, and makes the synthesized title/body publicly visible.

### Undo path

| Misfire | Undo command | What stays |
|---------|--------------|------------|
| Wrong / duplicate draft PR | `gh pr close <url>` (optionally delete the branch too) | The closed-PR **record** persists — GitHub PRs are closeable, never deletable — and any notification already sent is unrecallable. |
| Wrong pushed branch | `git push origin --delete ralph/issue-N` | Any CI run the push triggered already consumed compute and may have posted commit statuses. |
| Stale local URL pointer | delete `docs/prd/issue-N-pr.txt` | Nothing remote — this is local state; deleting it lets a corrected re-run open a fresh PR. |

### Cost, and why the ceiling is low

The **reversible** parts are the git/PR objects (branch deletable, PR closeable). The **irreversible** parts are the *notification* and the *public record*: a wrong draft PR emails real subscribers and leaves a closed-PR entry in history; a wrong push may burn CI minutes. None of this merges code or closes anyone's issue, so the damage **ceiling** is "noise + notifications + maybe a CI run" — never "merged bad code" or "a human's issue closed out from under them."

Three guardrails keep the actual risk well under that ceiling:

- **I1 — `--write` defaults OFF.** Every mutation is dark until a human deliberately passes `--write`; an accidental run has zero external blast radius.
- **I2 — idempotency.** The most likely real misfire is *re-running the loop*. The URL file + `gh pr view` reuse means a re-run converges to the **same one** PR instead of spamming duplicates.
- **I3 — draft only, no auto-merge/close.** The PR opens as a draft and no code path readies, merges, or closes it, so a misfire can never escalate past "a draft PR someone has to glance at and close."

## Dependencies & sequencing

- **Blocks:** Confessing PR, Worktree-per-Issue, Triage, Swarm — all of them. This is the spine.
- **Blocked by:** nothing. Build **first, by hand** (do not dogfood the spine — see `prd.md` §6).
- **External deps:** `gh` CLI authenticated with **write** scope (comment/label/PR) on the target repo; `git` ≥ branch/push.

## Out of scope

Worktree isolation (separate issue), the synthesized PR body (Confessing PR issue), triage gating (Triage issue), any concurrency, auto-merge/auto-close.

## Glossary

**Verdict-gated label** — a label driven by the review step's first-line contract (`REVIEW_PASSED`/`REVIEW_FAILED`). **`--write`** — the master flag gating all GitHub mutations, default off. **The Rubicon** — see ADR-001: write-back makes GitHub shared mutable state.

## Implementation progress (hand-built, slice by slice)

This issue is built **by hand** (not by the loop) because the loop cannot safely edit the script it is executing (ADR-002). Each slice is a separate human checkpoint.

- **Slice 1 — central gate + guarded helpers (done).** `scripts/ralph-loop.sh` gains `GITHUB_WRITE` (default `0`), the `--write` flag that sets it to `1`, and the three guarded helpers `gh_comment_op` / `gh_label_op` / `gh_pr_op` (a shared `_gh_write_guarded` core between the `RALPH WRITE GUARDS` sentinels). No call sites yet — this is the foundation every later slice routes through (ADR-001 I1). Change is purely additive (40 insertions, 0 deletions): the safety-contract sections (`run_claude()`, multi-model routing, retry/escalation, smart-salvage, upstream-fix cascade, budget caps) are untouched byte-for-byte, and `--dry-run-prompts` is byte-identical to the pre-change golden. Evidence: `tests/slice1-write-guard-smoke.sh` (offline, deterministic, 6/6).
- **Slice a — branch-per-issue (`ralph/issue-N`) created before any story commit (done).** `ensure_issue_branch()` (between the `RALPH ISSUE BRANCH` sentinels) runs in the Path A Phase 0 gate, right before `main()`. It creates the branch off the base on a fresh run and resumes it (plain `checkout`, never `-B`/reset) on a re-run, so prior `feat(N.k)` commits survive; then it hard-fails (`exit 1`) unless `HEAD == ralph/issue-N`. The branch is **local only** — no push (deferred to slice b, gated by `--write`) — so the invariant holds even with `--write` off. Purely additive (49 insertions, 0 deletions); safety-contract sections unchanged; `--dry-run-prompts` still byte-identical to the golden. Evidence: `tests/slice-a-issue-branch-smoke.sh` (offline, deterministic, 7/7).
- **Slice b — draft PR at intake, idempotent via `docs/prd/issue-N-pr.txt` (done).** `commit_issue_plan()`, `_git_push_guarded()`, and `ensure_issue_pr()` (between the `RALPH ISSUE PR` sentinels) run in the Path A Phase 0 gate, right after `ensure_issue_branch()` and before `main()`. With `--write` on they (1) commit the intake plan (PRD/source/epic, and architecture if present) onto `ralph/issue-N` as the PR's first commit, (2) push `ralph/issue-N` to `origin`, and (3) open exactly one draft PR (`gh pr create --draft --base main --head ralph/issue-N --body-file docs/prd/issue-N.md`, funnelled through the slice-1 `gh_pr_op` helper), then persist the PR URL to `docs/prd/issue-N-pr.txt`. The network mutations are gated by `--write`: the push via `_git_push_guarded` (same gate, but `git` is not a `gh` command), the PR via `gh_pr_op`. The plan commit is a LOCAL git op, so it is gated at the call site (`if GITHUB_WRITE=1`) and skipped with `--write` off — there the plan stays uncommitted and is swept into the first story commit exactly as read-only Path A does today, so `--write`-off local history is unchanged. With `--write` off every GitHub op logs `[dry] …` and touches nothing, so externally observable behavior stays byte-identical to read-only Path A. Idempotent (ADR-001 I2): on re-run the recorded URL is reused via `gh pr view` (re-created only on a genuine 404), and the plan commit is a no-op when nothing is staged — so two runs yield one PR and one plan commit. No auto-merge/auto-close (I3): the PR stays a draft. Purely additive (125 insertions, 0 deletions vs slice a); safety-contract sections unchanged; `--dry-run-prompts` still byte-identical to the golden. Evidence: `tests/slice-b-draft-pr-smoke.sh` (offline, deterministic, 8/8 — covers `--write`-off no-op + plan-uncommitted, `--write`-on push + plan-committed + URL persisted, idempotent reuse, and 404 re-create) plus the unchanged slice-1 byte-diff.
- **Slice c — self-updating issue comment via fail-closed HTML-comment fences.** *(pending)*
- **Slice d — verdict-gated labels off the `REVIEW_PASSED`/`REVIEW_FAILED` contract.** *(pending)*
- **Blast-radius answer (ADR I4) — answered (slice b).** See [§ Blast-radius answer (ADR-001 I4)](#blast-radius-answer-adr-001-i4): the undo path for a wrong push/PR, the irreversible cost (notifications + public record), and why the damage ceiling is "noise + notifications," never merged code. Activated alongside slice b's first real write paths, as required.

> **Empty-branch-at-intake — resolved in slice b (option a).** `ralph/issue-N` is created off the base with the plan files (`docs/prd/issue-N.md`, `docs/epics/issue-N.md`) written into the working tree but uncommitted (the loop otherwise commits them per-story inside `main()`), so at `ensure_issue_pr` time the branch has **no commits ahead of `main`** and a *real* `--write`-on `gh pr create` would fail with `No commits between main and ralph/issue-N`. (The offline smoke cannot catch this — it stubs `gh`.) **Fix:** `commit_issue_plan()` commits the plan as the PR's first commit before push, gated to `--write` so `--write`-off history is unchanged. Verified offline by `tests/slice-b-draft-pr-smoke.sh` (plan committed with `--write` on, left uncommitted with `--write` off). The alternatives — (b) defer PR creation until after the first story commit, (c) handle in the finish slice — were considered and rejected in favor of (a), which keeps the PR's first commit a clean, reviewable "the plan" snapshot.
