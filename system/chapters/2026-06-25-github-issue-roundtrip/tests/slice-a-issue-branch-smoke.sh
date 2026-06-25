#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# Offline smoke — Slice a of issue #1 "The Round Trip": branch-per-issue.
#
# Subject under test: ensure_issue_branch() in scripts/ralph-loop.sh — the
# function that creates/resumes `ralph/issue-N` BEFORE the dev loop so story
# feat() commits never land on the base branch (issue #1 AC: branch-before-commit).
#
# Agent-runnable, deterministic, NO network. The function is extracted from its
# fenced block and sourced into a THROWAWAY git repo (a temp dir), so the smoke
# never runs the orchestrator's main() and never touches the real repo or remote.
#
# Proves:
#   1. Fresh create: from the base branch, ensure_issue_branch lands HEAD on
#      ralph/issue-N and returns 0.
#   2. Base branch is protected: a commit made on ralph/issue-N never appears on
#      the base branch (the whole point of the slice).
#   3. Idempotent resume: re-running (already on the branch, or back on base)
#      resumes the SAME branch with prior commits intact — never resets it.
#   4. No network: with no git remote configured, every run still succeeds —
#      ensure_issue_branch never pushes (push is slice b, gated by --write).
#   5. Hard-fail: pointed at a non-git directory, it exits non-zero rather than
#      proceeding (the branch-before-commit invariant fails closed).
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# tests/ -> chapter -> chapters -> system -> repo root
REPO_ROOT_REAL="$(cd "$SMOKE_DIR/../../../.." && pwd)"
LOOP="$REPO_ROOT_REAL/scripts/ralph-loop.sh"

PASS=0
FAIL=0
pass() { printf '  \033[0;32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  \033[0;31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

extract_issue_branch() {
  awk '
    /# >>> RALPH ISSUE BRANCH/ { f = 1 }
    f                          { print }
    /# <<< RALPH ISSUE BRANCH/ { f = 0 }
  ' "$LOOP"
}

# Run ensure_issue_branch in an isolated subshell against $2 (REPO_ROOT), with
# log_* shimmed away. Returns the subshell's exit code (the function may `exit`).
run_ensure() { # $1=ISSUE_NUMBER  $2=REPO_ROOT
  (
    REPO_ROOT="$2"
    ISSUE_NUMBER="$1"
    log_info()    { :; }
    log_success() { :; }
    log_warn()    { :; }
    log_error()   { printf 'ERR %s\n' "$1" >&2; }
    # shellcheck disable=SC1090
    source <(extract_issue_branch)
    ensure_issue_branch
  )
}

TMP="$(mktemp -d)"
NOTREPO="$(mktemp -d)"
trap 'rm -rf "$TMP" "$NOTREPO"' EXIT

# Seed a throwaway repo with a base branch `main` (portable across git versions).
git -C "$TMP" init -q
git -C "$TMP" symbolic-ref HEAD refs/heads/main
git -C "$TMP" config user.email "smoke@example.com"
git -C "$TMP" config user.name "Smoke Test"
printf 'seed\n' > "$TMP/seed.txt"
git -C "$TMP" add -A
git -C "$TMP" commit -q -m "seed"
BASE_SHA="$(git -C "$TMP" rev-parse main)"

head_of() { git -C "$TMP" rev-parse --abbrev-ref HEAD; }

echo "── Slice a issue-branch smoke ────────────────────────────────"

# Sanity: the fenced function exists.
if extract_issue_branch | grep -q 'ensure_issue_branch()'; then
  pass "fenced block defines ensure_issue_branch"
else
  fail "fenced ensure_issue_branch block not found"
fi

# ── 1. Fresh create from the base branch ──
rc=0; run_ensure 7 "$TMP" || rc=$?
if [[ "$rc" -eq 0 && "$(head_of)" == "ralph/issue-7" ]]; then
  pass "fresh create: HEAD is ralph/issue-7 (rc=0)"
else
  fail "fresh create: rc=$rc HEAD=$(head_of)"
fi

# Make a story commit on the issue branch, then prove the base never gets it.
printf 'work\n' > "$TMP/work.txt"
git -C "$TMP" add -A
git -C "$TMP" commit -q -m "feat(7.1): work"
STORY_SHA="$(git -C "$TMP" rev-parse ralph/issue-7)"

if [[ "$(git -C "$TMP" rev-parse main)" == "$BASE_SHA" ]]; then
  pass "base branch protected: main still at seed (story commit not on main)"
else
  fail "base branch moved: main=$(git -C "$TMP" rev-parse main) expected $BASE_SHA"
fi

# ── 2. Idempotent re-run while already on the branch ──
rc=0; run_ensure 7 "$TMP" || rc=$?
if [[ "$rc" -eq 0 && "$(head_of)" == "ralph/issue-7" \
      && "$(git -C "$TMP" rev-parse ralph/issue-7)" == "$STORY_SHA" ]]; then
  pass "idempotent (on branch): resumed, story commit preserved (no reset)"
else
  fail "idempotent (on branch): rc=$rc HEAD=$(head_of) sha=$(git -C "$TMP" rev-parse ralph/issue-7)"
fi

# ── 3. Resume from the base branch (back on main, branch already exists) ──
git -C "$TMP" checkout -q main
rc=0; run_ensure 7 "$TMP" || rc=$?
if [[ "$rc" -eq 0 && "$(head_of)" == "ralph/issue-7" \
      && "$(git -C "$TMP" rev-parse ralph/issue-7)" == "$STORY_SHA" ]]; then
  pass "idempotent (from base): switched back, story commit preserved"
else
  fail "idempotent (from base): rc=$rc HEAD=$(head_of) sha=$(git -C "$TMP" rev-parse ralph/issue-7)"
fi

# ── 4. No network: no remote configured, yet every run above succeeded ──
if [[ -z "$(git -C "$TMP" remote)" ]]; then
  pass "no network: no remote configured and runs succeeded (no push attempted)"
else
  fail "unexpected remote configured: $(git -C "$TMP" remote)"
fi

# ── 5. Hard-fail when REPO_ROOT is not a git repository ──
rc=0; run_ensure 7 "$NOTREPO" || rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass "hard-fail: non-git REPO_ROOT exits non-zero (rc=$rc)"
else
  fail "expected non-zero exit for non-git REPO_ROOT, got rc=$rc"
fi

echo "──────────────────────────────────────────────────────────────"
printf 'Result: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
