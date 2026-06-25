#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# Offline smoke — Slice b of issue #1 "The Round Trip": draft PR at intake.
#
# Subject under test: ensure_issue_pr() and _git_push_guarded() in
# scripts/ralph-loop.sh — the functions that, after Phase 0 + ensure_issue_branch,
# push `ralph/issue-N` and open exactly ONE draft PR, persisting its URL to
# docs/prd/issue-N-pr.txt for idempotent re-runs (ADR-001 invariants I1/I2/I3).
#
# Agent-runnable, deterministic, NO network. The functions are extracted from
# their fenced block (together with the RALPH WRITE GUARDS block they call into
# for gh_pr_op) and sourced into a THROWAWAY git repo whose `origin` is a LOCAL
# bare repo, with `gh` replaced by an offline stub. The orchestrator's main() is
# never run and the real repo/remote are never touched.
#
# Proves:
#   1. The fenced block defines ensure_issue_pr + _git_push_guarded.
#   2. --write OFF: every GitHub op is a dry no-op — the branch is NOT pushed to
#      origin, NO PR is created (the gh stub is never called), NO URL file is
#      written, the intake plan is left UNCOMMITTED (local history unchanged), and
#      rc=0. Both the push and the PR log "[dry] …" lines.
#   3. --write ON: the intake plan is committed as the PR's first commit, the branch
#      IS pushed to origin, exactly ONE `gh pr create` runs, and the returned URL is
#      persisted to docs/prd/issue-N-pr.txt.
#   4. Idempotency (I2): a second --write ON run finds the URL file, `gh pr view`
#      resolves it, and NO second PR is created (still exactly one create total).
#   5. 404 re-create (I2): with a recorded URL that `gh pr view` reports missing,
#      a re-run creates a fresh PR (exactly one more create) and rewrites the file.
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

# ensure_issue_pr calls gh_pr_op (the slice-1 guarded helper), so both fenced
# blocks are sourced — exactly as the loop has them side by side.
extract_write_guards() {
  awk '
    /# >>> RALPH WRITE GUARDS/ { f = 1 }
    f                          { print }
    /# <<< RALPH WRITE GUARDS/ { f = 0 }
  ' "$LOOP"
}
extract_issue_pr() {
  awk '
    /# >>> RALPH ISSUE PR/ { f = 1 }
    f                      { print }
    /# <<< RALPH ISSUE PR/ { f = 0 }
  ' "$LOOP"
}

# ── Offline `gh` stub: records every call and stands in for the network ──
# `pr create` echoes a canned URL (the loop captures it); `pr view` exits
# ${GH_VIEW_RC:-0} so the idempotency/404 paths are both reachable offline.
GH_BIN="$(mktemp -d)"
cat > "$GH_BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALL_LOG"
if [[ "${1:-} ${2:-}" == "pr create" ]]; then
  printf '%s\n' "${GH_PR_URL:-https://github.com/seevali/ralph-loop-demo/pull/42}"
  exit 0
elif [[ "${1:-} ${2:-}" == "pr view" ]]; then
  exit "${GH_VIEW_RC:-0}"
fi
exit 0
STUB
chmod +x "$GH_BIN/gh"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT" "$GH_BIN"' EXIT

# Build a fresh work repo whose `main` holds only a seed (NOT the issue plan), then
# branch `ralph/issue-N` off it and drop the intake plan files into the working tree
# UNCOMMITTED — exactly the state run_intake_phase + ensure_issue_branch leave for
# ensure_issue_pr (branch at base SHA, plan staged in the worktree). A LOCAL bare
# `origin` stands in for the remote. Echoes the work-repo path; each test gets its
# own repo so commit/push state never leaks between cases.
make_repo() { # $1 = issue number
  local n="$1"
  local work bare
  work="$(mktemp -d -p "$TMPROOT")"
  bare="$(mktemp -d -p "$TMPROOT")"
  git -C "$bare" init -q --bare
  git -C "$work" init -q
  git -C "$work" symbolic-ref HEAD refs/heads/main
  git -C "$work" config user.email "smoke@example.com"
  git -C "$work" config user.name "Smoke Test"
  git -C "$work" remote add origin "$bare"
  # main has only the seed — the issue plan does NOT exist on the base branch.
  printf 'seed\n' > "$work/seed.txt"
  git -C "$work" add -A
  git -C "$work" commit -q -m "seed"
  # Branch off base, then write the intake plan into the working tree UNCOMMITTED.
  git -C "$work" checkout -q -b "ralph/issue-${n}"
  mkdir -p "$work/docs/prd" "$work/docs/epics"
  printf '# PRD issue %s\n'    "$n" > "$work/docs/prd/issue-${n}.md"
  printf '# Issue %s source\n' "$n" > "$work/docs/prd/issue-${n}-source.md"
  printf '## Epic %s\n'        "$n" > "$work/docs/epics/issue-${n}.md"
  printf '%s\n' "$work"
}

plan_committed() { git -C "$1" log --oneline 2>/dev/null | grep -q "docs(issue-${2}): intake plan"; }
plan_dirty()     { [[ -n "$(git -C "$1" status --porcelain -- "docs/prd/issue-${2}.md")" ]]; }

# Run ensure_issue_pr against $REPO with the given $GITHUB_WRITE, the gh stub on
# PATH, and log_* shimmed to stdout (so the dry/real lines are observable).
# Returns the subshell exit code.
run_pr() { # env: GITHUB_WRITE, REPO, ISSUE_NUMBER, GH_CALL_LOG, GH_VIEW_RC, GH_PR_URL
  (
    set +e
    PATH="$GH_BIN:$PATH"
    REPO_ROOT="$REPO"
    ISSUE_TITLE="Round trip"
    log_dim()     { printf '%s\n' "$1"; }
    log_info()    { printf '%s\n' "$1"; }
    log_warn()    { printf '%s\n' "$1"; }
    log_success() { printf '%s\n' "$1"; }
    log_error()   { printf 'ERR %s\n' "$1" >&2; }
    # shellcheck disable=SC1090
    source <(extract_write_guards)
    # shellcheck disable=SC1090
    source <(extract_issue_pr)
    ensure_issue_pr
  )
}

remote_has_branch() { git -C "$1" show-ref --verify --quiet "refs/heads/ralph/issue-${2}"; }
origin_of() { git -C "$1" remote get-url origin; }   # work repo -> bare path

echo "── Slice b draft-PR smoke ────────────────────────────────────"

# ── 0. Sanity: the fenced block defines both functions ──
issue_pr_src="$(extract_issue_pr)"
if grep -q 'ensure_issue_pr()' <<< "$issue_pr_src" \
   && grep -q '_git_push_guarded()' <<< "$issue_pr_src"; then
  pass "fenced block defines ensure_issue_pr + _git_push_guarded"
else
  fail "fenced RALPH ISSUE PR block not found or missing a function"
fi

# ── 2. --write OFF → dry no-op: no push, no PR, no URL file ──
REPO="$(make_repo 7)"; BARE="$(origin_of "$REPO")"
export GH_CALL_LOG="$TMPROOT/calls-off.log"; : > "$GH_CALL_LOG"
export GH_VIEW_RC=0 GH_PR_URL="https://example/pull/1"
off_rc=0
off_out="$(GITHUB_WRITE=0 ISSUE_NUMBER=7 REPO="$REPO" run_pr)" || off_rc=$?

if [[ "$off_rc" -eq 0 ]] \
   && ! remote_has_branch "$BARE" 7 \
   && [[ ! -f "$REPO/docs/prd/issue-7-pr.txt" ]] \
   && [[ ! -s "$GH_CALL_LOG" ]]; then
  pass "--write off: no push, no PR, no URL file, gh never called (rc=0)"
else
  fail "--write off leaked: rc=$off_rc remote_branch=$(remote_has_branch "$BARE" 7 && echo yes || echo no) urlfile=$([[ -f $REPO/docs/prd/issue-7-pr.txt ]] && echo yes || echo no) ghcalls=$(wc -l < "$GH_CALL_LOG")"
fi

if grep -q '\[dry\] git push -u origin ralph/issue-7' <<< "$off_out" \
   && grep -q '\[dry\] gh pr create --draft --base main --head ralph/issue-7' <<< "$off_out"; then
  pass "--write off: push and PR both logged '[dry] …' (gated)"
else
  fail "--write off: missing a [dry] line"
  sed 's/^/      /' <<< "$off_out"
fi

# Local history must be untouched with --write off: no intake-plan commit, and the
# plan files are still uncommitted (swept into the first story commit later, as today).
if ! plan_committed "$REPO" 7 && plan_dirty "$REPO" 7; then
  pass "--write off: intake plan left uncommitted (local history unchanged)"
else
  fail "--write off: plan unexpectedly committed (committed=$(plan_committed "$REPO" 7 && echo yes || echo no) dirty=$(plan_dirty "$REPO" 7 && echo yes || echo no))"
fi

# ── 3. --write ON → branch pushed, one PR created, URL persisted ──
REPO="$(make_repo 7)"; BARE="$(origin_of "$REPO")"
export GH_CALL_LOG="$TMPROOT/calls-on.log"; : > "$GH_CALL_LOG"
export GH_VIEW_RC=0 GH_PR_URL="https://github.com/seevali/ralph-loop-demo/pull/77"
on_rc=0
on_out="$(GITHUB_WRITE=1 ISSUE_NUMBER=7 REPO="$REPO" run_pr)" || on_rc=$?
create_count="$(grep -c '^pr create ' "$GH_CALL_LOG" || true)"
url_file="$REPO/docs/prd/issue-7-pr.txt"

if [[ "$on_rc" -eq 0 ]] \
   && remote_has_branch "$BARE" 7 \
   && [[ "$create_count" -eq 1 ]] \
   && [[ -f "$url_file" ]] \
   && [[ "$(cat "$url_file")" == "https://github.com/seevali/ralph-loop-demo/pull/77" ]]; then
  pass "--write on: branch pushed, exactly one PR, URL persisted to issue-7-pr.txt"
else
  fail "--write on: rc=$on_rc pushed=$(remote_has_branch "$BARE" 7 && echo yes || echo no) creates=$create_count url=$([[ -f $url_file ]] && cat "$url_file" || echo MISSING)"
  sed 's/^/      /' <<< "$on_out"
fi

# The plan must be committed as the PR's first commit (branch now ahead of base),
# and the worktree clean of those files — so a real `gh pr create` is non-empty.
if plan_committed "$REPO" 7 && ! plan_dirty "$REPO" 7; then
  pass "--write on: intake plan committed as PR first commit (branch ahead of base)"
else
  fail "--write on: intake plan not committed (committed=$(plan_committed "$REPO" 7 && echo yes || echo no) dirty=$(plan_dirty "$REPO" 7 && echo yes || echo no))"
  git -C "$REPO" log --oneline 2>/dev/null | sed 's/^/      /'
fi

# ── 4. Idempotency: re-run finds the URL, gh pr view resolves it, no 2nd PR ──
GH_VIEW_RC=0
idem_rc=0
idem_out="$(GITHUB_WRITE=1 ISSUE_NUMBER=7 REPO="$REPO" run_pr)" || idem_rc=$?
create_count_after="$(grep -c '^pr create ' "$GH_CALL_LOG" || true)"
view_count="$(grep -c '^pr view ' "$GH_CALL_LOG" || true)"

if [[ "$idem_rc" -eq 0 ]] \
   && [[ "$create_count_after" -eq 1 ]] \
   && [[ "$view_count" -ge 1 ]] \
   && [[ "$(cat "$url_file")" == "https://github.com/seevali/ralph-loop-demo/pull/77" ]]; then
  pass "idempotent: re-run reused existing PR (still 1 create), URL file unchanged"
else
  fail "idempotency broke: rc=$idem_rc creates=$create_count_after views=$view_count url=$(cat "$url_file")"
  sed 's/^/      /' <<< "$idem_out"
fi

# ── 5. 404 re-create: stale URL that gh pr view reports missing → fresh PR ──
GH_VIEW_RC=1 GH_PR_URL="https://github.com/seevali/ralph-loop-demo/pull/78"
recreate_rc=0
recreate_out="$(GITHUB_WRITE=1 ISSUE_NUMBER=7 REPO="$REPO" run_pr)" || recreate_rc=$?
create_count_recreate="$(grep -c '^pr create ' "$GH_CALL_LOG" || true)"

if [[ "$recreate_rc" -eq 0 ]] \
   && [[ "$create_count_recreate" -eq 2 ]] \
   && [[ "$(cat "$url_file")" == "https://github.com/seevali/ralph-loop-demo/pull/78" ]]; then
  pass "404 re-create: missing PR triggered exactly one fresh create, URL rewritten"
else
  fail "404 re-create failed: rc=$recreate_rc creates=$create_count_recreate url=$(cat "$url_file")"
  sed 's/^/      /' <<< "$recreate_out"
fi

echo "──────────────────────────────────────────────────────────────"
printf 'Result: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
