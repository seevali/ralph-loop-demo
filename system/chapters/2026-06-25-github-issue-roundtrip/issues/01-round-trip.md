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
- [ ] With `--write` **on**, running `--issue N --write` creates branch `ralph/issue-N`, opens exactly one draft PR, and posts exactly one issue comment linking it.
- [ ] **Idempotency:** re-running the same issue does not create a second PR or a second comment, and does not churn labels (PR found via `docs/prd/issue-N-pr.txt`; comment edited in place; labels via single add/remove calls).
- [x] **Branch-before-commit invariant:** assert `git rev-parse --abbrev-ref HEAD == ralph/issue-N` before the dev loop; hard-fail otherwise (so story commits never land on `main`). *(Slice a: `ensure_issue_branch()` runs in the Phase 0 gate immediately before `main()`; creates/resumes `ralph/issue-N` (local, no push) and `exit 1`s if HEAD isn't the issue branch. `tests/slice-a-issue-branch-smoke.sh` proves create, base-branch protection, idempotent resume, no-push, and the hard-fail path.)*
- [ ] **Blast-radius answer (ADR I4):** the issue documents the undo path and cost of a wrong `--write` action on a watched repo. *(Resolve before merge.)*
- [ ] No auto-merge, no auto-close (ADR I3).
- [ ] `prd.md` §3 Idea 1 matches shipped behavior (anti-drift DoD).

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
- **Slice b — draft PR at intake, idempotent via `docs/prd/issue-N-pr.txt`.** *(pending)*
- **Slice c — self-updating issue comment via fail-closed HTML-comment fences.** *(pending)*
- **Slice d — verdict-gated labels off the `REVIEW_PASSED`/`REVIEW_FAILED` contract.** *(pending)*
- **Blast-radius answer (ADR I4)** is written when the first real write path activates (Slice b), before those write paths are considered done.
