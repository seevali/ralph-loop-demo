#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# Offline smoke — Slice e (FINISH) of issue #1 "The Round Trip":
# `gh pr ready` on all-green (prd.md §3 Idea 1, step 5).
#
# Subject under test: mark_issue_pr_ready() in scripts/ralph-loop.sh — the function
# that, at main()'s completion when the whole sprint is green, graduates the slice-b
# DRAFT PR (URL in docs/prd/issue-N-pr.txt) to ready-for-review via `gh pr ready`
# (ADR-001 invariants I1 default-off / I2 idempotency / I3 no-merge-no-close).
#
# Agent-runnable, deterministic, NO network. The function is extracted from its fenced
# block (together with the RALPH WRITE GUARDS block it calls into for gh_pr_op) and
# sourced standalone into throwaway temp repos, with `gh` replaced by a STATEFUL offline
# stub. The orchestrator's main() is never run and the real repo/remote are never touched.
#
# Proves:
#   1. The fenced block defines mark_issue_pr_ready.
#   2. --write OFF: a dry no-op — the real `gh` is NEVER called, "[dry] gh pr ready …"
#      is logged, and rc=0 (byte-identical to read-only Path A).
#   3. --write ON on a DRAFT PR: exactly ONE `gh pr ready <url>` fires and the PR becomes
#      non-draft (rc=0).
#   4. Idempotency (I2): a re-run when the PR is already ready issues ZERO `gh pr ready`
#      calls (the isDraft read converges → skip, no churn).
#   5. Missing URL file: best-effort skip — rc=0, no `gh pr ready`, no crash.
#   6. 404 PR: `gh pr view` reports the PR missing → best-effort skip — rc=0, no
#      `gh pr ready`.
#   7. No auto-merge / auto-close (I3): across EVERY run the stub asserts `pr merge`,
#      `pr close`, and `issue close` are NEVER invoked.
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

# mark_issue_pr_ready calls gh_pr_op (the slice-1 guarded helper), so both fenced
# blocks are sourced — exactly as the loop has them side by side.
extract_write_guards() {
  awk '
    /# >>> RALPH WRITE GUARDS/ { f = 1 }
    f                          { print }
    /# <<< RALPH WRITE GUARDS/ { f = 0 }
  ' "$LOOP"
}
extract_issue_ready() {
  awk '
    /# >>> RALPH ISSUE READY/ { f = 1 }
    f                         { print }
    /# <<< RALPH ISSUE READY/ { f = 0 }
  ' "$LOOP"
}

# ── Offline, STATEFUL `gh` stub. The PR's draft-state lives in $GH_PR_STATE (a file
# holding "true"|"false"). $GH_VIEW_RC simulates a missing PR (set to 1 → 404 on view).
# EVERY gh invocation is appended to $GH_CALL_LOG so the test can count `pr ready`. The
# FORBIDDEN ops (`pr merge`/`pr close`/`issue close`) are additionally recorded to
# $GH_FORBIDDEN_LOG; the test asserts that log stays empty (ADR-001 I3). No network ever.
GH_BIN="$(mktemp -d)"
cat > "$GH_BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALL_LOG"
sub="${1:-}"; op="${2:-}"
case "$sub $op" in
  "pr view")   # gh pr view <url> --json isDraft -q .isDraft
    [[ "${GH_VIEW_RC:-0}" -ne 0 ]] && exit "${GH_VIEW_RC:-0}"
    cat "$GH_PR_STATE" 2>/dev/null || printf 'true\n'
    exit 0 ;;
  "pr ready")  # gh pr ready <url> → graduate to ready-for-review (no longer a draft)
    printf 'false\n' > "$GH_PR_STATE"
    exit 0 ;;
  "pr merge"|"pr close"|"issue close")  # FORBIDDEN by I3 — must never be reached
    printf 'FORBIDDEN %s\n' "$*" >> "$GH_FORBIDDEN_LOG"
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$GH_BIN/gh"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT" "$GH_BIN"' EXIT

export GH_FORBIDDEN_LOG="$TMPROOT/forbidden.log"; : > "$GH_FORBIDDEN_LOG"

# A throwaway REPO_ROOT carrying only docs/prd/issue-N-pr.txt (the slice-b URL pointer).
# $2 omitted → no URL file (the missing-pointer case). Echoes the repo path.
make_repo() { # $1 = issue number, [$2 = PR url]
  local n="$1" url="${2:-}"
  local work
  work="$(mktemp -d -p "$TMPROOT")"
  mkdir -p "$work/docs/prd"
  [[ -n "$url" ]] && printf '%s\n' "$url" > "$work/docs/prd/issue-${n}-pr.txt"
  printf '%s\n' "$work"
}

# Run mark_issue_pr_ready against $REPO with the gh stub on PATH and log_* shimmed to
# stdout (so [dry]/transition lines are observable). Returns the subshell exit code.
run_ready() { # env: GITHUB_WRITE, ISSUE_NUMBER, REPO, GH_CALL_LOG, GH_PR_STATE, GH_VIEW_RC
  (
    set +e
    PATH="$GH_BIN:$PATH"
    REPO_ROOT="$REPO"
    log_dim()     { printf '%s\n' "$1"; }
    log_info()    { printf '%s\n' "$1"; }
    log_warn()    { printf '%s\n' "$1"; }
    log_success() { printf '%s\n' "$1"; }
    log_error()   { printf 'ERR %s\n' "$1" >&2; }
    # shellcheck disable=SC1090
    source <(extract_write_guards)
    # shellcheck disable=SC1090
    source <(extract_issue_ready)
    mark_issue_pr_ready
  )
}

ready_count() { grep -c '^pr ready '  "$1" 2>/dev/null || true; }
view_count()  { grep -c '^pr view '   "$1" 2>/dev/null || true; }

echo "── Slice e PR-ready (finish) smoke ───────────────────────────"

# ── 1. Sanity: the fenced block defines mark_issue_pr_ready ──
ready_src="$(extract_issue_ready)"
if grep -q 'mark_issue_pr_ready()' <<< "$ready_src"; then
  pass "fenced RALPH ISSUE READY block defines mark_issue_pr_ready"
else
  fail "fenced RALPH ISSUE READY block not found or missing mark_issue_pr_ready"
fi

# ── 2. --write OFF → dry no-op: gh never called, "[dry] gh pr ready …" logged ──
REPO="$(make_repo 7 "https://github.com/seevali/ralph-loop-demo/pull/77")"
export GH_CALL_LOG="$TMPROOT/calls-off.log"; : > "$GH_CALL_LOG"
export GH_PR_STATE="$TMPROOT/state-off"; printf 'true\n' > "$GH_PR_STATE"
unset GH_VIEW_RC 2>/dev/null || true
off_rc=0
off_out="$(GITHUB_WRITE=0 ISSUE_NUMBER=7 REPO="$REPO" run_ready)" || off_rc=$?

if [[ "$off_rc" -eq 0 ]] && [[ ! -s "$GH_CALL_LOG" ]]; then
  pass "--write off: gh never called, rc=0 (read-only Path A unchanged)"
else
  fail "--write off leaked: rc=$off_rc ghcalls=$(wc -l < "$GH_CALL_LOG")"
  sed 's/^/      /' <<< "$off_out"
fi
if grep -q '\[dry\] gh pr ready ralph/issue-7' <<< "$off_out"; then
  pass "--write off: '[dry] gh pr ready …' logged (gated through gh_pr_op)"
else
  fail "--write off: missing the [dry] gh pr ready line"
  sed 's/^/      /' <<< "$off_out"
fi

# ── 3. --write ON on a DRAFT PR → exactly one `gh pr ready`, PR becomes non-draft ──
REPO="$(make_repo 7 "https://github.com/seevali/ralph-loop-demo/pull/77")"
export GH_CALL_LOG="$TMPROOT/calls-on.log"; : > "$GH_CALL_LOG"
export GH_PR_STATE="$TMPROOT/state-on"; printf 'true\n' > "$GH_PR_STATE"
unset GH_VIEW_RC 2>/dev/null || true
on_rc=0
on_out="$(GITHUB_WRITE=1 ISSUE_NUMBER=7 REPO="$REPO" run_ready)" || on_rc=$?

if [[ "$on_rc" -eq 0 ]] \
   && [[ "$(ready_count "$GH_CALL_LOG")" -eq 1 ]] \
   && [[ "$(cat "$GH_PR_STATE")" == "false" ]]; then
  pass "--write on (draft): exactly one 'gh pr ready', PR now ready-for-review (rc=0)"
else
  fail "--write on (draft): rc=$on_rc ready=$(ready_count "$GH_CALL_LOG") state=$(cat "$GH_PR_STATE")"
  sed 's/^/      /' <<< "$on_out"
fi
if grep -q 'ready-for-review' <<< "$on_out"; then
  pass "--write on (draft): success line announces ready-for-review"
else
  fail "--write on (draft): missing the ready-for-review success line"
  sed 's/^/      /' <<< "$on_out"
fi

# ── 4. Idempotency (I2): re-run when already ready → ZERO new `gh pr ready` ──
idem_rc=0
idem_out="$(GITHUB_WRITE=1 ISSUE_NUMBER=7 REPO="$REPO" run_ready)" || idem_rc=$?
if [[ "$idem_rc" -eq 0 ]] \
   && [[ "$(ready_count "$GH_CALL_LOG")" -eq 1 ]] \
   && [[ "$(view_count "$GH_CALL_LOG")" -ge 2 ]]; then
  pass "idempotent: re-run on a ready PR added ZERO 'gh pr ready' (read → skip, no churn)"
else
  fail "idempotency broke: rc=$idem_rc ready=$(ready_count "$GH_CALL_LOG") views=$(view_count "$GH_CALL_LOG")"
  sed 's/^/      /' <<< "$idem_out"
fi

# ── 5. Missing URL file (--write on) → best-effort skip, rc=0, no `gh pr ready` ──
REPO="$(make_repo 9)"   # no URL file written
export GH_CALL_LOG="$TMPROOT/calls-nourl.log"; : > "$GH_CALL_LOG"
export GH_PR_STATE="$TMPROOT/state-nourl"; printf 'true\n' > "$GH_PR_STATE"
nourl_rc=0
nourl_out="$(GITHUB_WRITE=1 ISSUE_NUMBER=9 REPO="$REPO" run_ready)" || nourl_rc=$?
if [[ "$nourl_rc" -eq 0 ]] && [[ "$(ready_count "$GH_CALL_LOG")" -eq 0 ]]; then
  pass "missing URL file: best-effort skip — rc=0, no 'gh pr ready', no crash"
else
  fail "missing URL file: rc=$nourl_rc ready=$(ready_count "$GH_CALL_LOG")"
  sed 's/^/      /' <<< "$nourl_out"
fi

# ── 6. 404 PR (--write on): `gh pr view` reports it gone → best-effort skip ──
REPO="$(make_repo 9 "https://github.com/seevali/ralph-loop-demo/pull/404")"
export GH_CALL_LOG="$TMPROOT/calls-404.log"; : > "$GH_CALL_LOG"
export GH_PR_STATE="$TMPROOT/state-404"; printf 'true\n' > "$GH_PR_STATE"
export GH_VIEW_RC=1
v404_rc=0
v404_out="$(GITHUB_WRITE=1 ISSUE_NUMBER=9 REPO="$REPO" run_ready)" || v404_rc=$?
if [[ "$v404_rc" -eq 0 ]] \
   && [[ "$(view_count "$GH_CALL_LOG")" -eq 1 ]] \
   && [[ "$(ready_count "$GH_CALL_LOG")" -eq 0 ]]; then
  pass "404 PR: view reports missing → best-effort skip — rc=0, no 'gh pr ready'"
else
  fail "404 PR: rc=$v404_rc views=$(view_count "$GH_CALL_LOG") ready=$(ready_count "$GH_CALL_LOG")"
  sed 's/^/      /' <<< "$v404_out"
fi
unset GH_VIEW_RC 2>/dev/null || true

# ── 7. No auto-merge / auto-close (I3): never invoked across EVERY run above ──
if [[ ! -s "$GH_FORBIDDEN_LOG" ]]; then
  pass "I3: 'gh pr merge' / 'gh pr close' / 'gh issue close' NEVER invoked (no merge/close)"
else
  fail "I3 VIOLATED: a forbidden op was invoked:"
  sed 's/^/      /' "$GH_FORBIDDEN_LOG"
fi

echo "──────────────────────────────────────────────────────────────"
printf 'Result: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
