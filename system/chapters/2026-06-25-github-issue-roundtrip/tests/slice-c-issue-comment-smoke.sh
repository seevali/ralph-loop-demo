#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# Offline smoke — Slice c of issue #1 "The Round Trip": self-updating issue comment.
#
# Subject under test: render_issue_comment_block(), splice_managed_block(), and
# upsert_issue_comment() in scripts/ralph-loop.sh — the functions that maintain ONE
# issue comment, edited in place across the run via fail-closed HTML-comment fences,
# rendered from LOCAL state (ADR-001 invariants I1/I2/I3).
#
# Agent-runnable, deterministic, NO network. The functions are extracted from their
# fenced block (together with the RALPH WRITE GUARDS block they call into for
# gh_comment_op) and sourced into a subshell with log_* shimmed and `gh` replaced by
# an offline, stateful stub (a JSON file standing in for the issue's comment list).
# The orchestrator's main() is never run and the real repo/GitHub are never touched.
#
# Proves:
#   1. The fenced block defines render/splice/upsert.
#   2. Render is DETERMINISTIC — same inputs yield a byte-identical fenced block with
#      exactly one BEGIN and one END marker (so re-runs converge, I2).
#   3. Splice FAILS CLOSED — zero / duplicated / unbalanced fences abort with NO
#      output (return 1); a well-formed body splices in place, preserving every byte
#      OUTSIDE the fences.
#   4. --write OFF: a dry no-op — no comments read, no create, no edit; the gh stub
#      is never called and a "[dry] gh …" line is logged.
#   5. --write ON, create-once then edit-in-place: the first upsert creates exactly
#      ONE comment; a second upsert edits THAT comment (never a 2nd create).
#   6. --write ON fail-closed: an existing comment with malformed fences aborts the
#      edit (no PATCH) and lets the build continue (rc=0).
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

# upsert_issue_comment calls gh_comment_op (the slice-1 guarded helper), so both
# fenced blocks are sourced — exactly as the loop has them.
extract_write_guards() {
  awk '
    /# >>> RALPH WRITE GUARDS/ { f = 1 }
    f                          { print }
    /# <<< RALPH WRITE GUARDS/ { f = 0 }
  ' "$LOOP"
}
extract_issue_comment() {
  awk '
    /# >>> RALPH ISSUE COMMENT/ { f = 1 }
    f                           { print }
    /# <<< RALPH ISSUE COMMENT/ { f = 0 }
  ' "$LOOP"
}

# ── Offline, STATEFUL `gh` stub: a JSON file ($GH_STATE) is the issue's comment
# list. `issue view` reads it; `issue comment` (create) appends a comment with a
# synthesized #issuecomment-<id> url; `api PATCH …` (edit) rewrites the targeted
# comment's body. Every call is logged to $GH_CALL_LOG so the test can count
# creates vs edits. No network is ever touched.
GH_BIN="$(mktemp -d)"
cat > "$GH_BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALL_LOG"
case "${1:-}" in
  repo)
    printf '%s\n' "${GH_SLUG:-seevali/ralph-loop-demo}"; exit 0 ;;
  issue)
    case "${2:-}" in
      view) cat "$GH_STATE"; exit 0 ;;
      comment)
        bf=""
        while [[ $# -gt 0 ]]; do
          [[ "$1" == "--body-file" ]] && bf="${2:-}"
          shift
        done
        body="$(cat "$bf")"
        n="$(jq '.comments | length' "$GH_STATE")"
        cid=$((1000 + n + 1))
        url="https://github.com/${GH_SLUG:-o/r}/issues/${GH_ISSUE:-7}#issuecomment-${cid}"
        tmp="$(mktemp)"
        jq --arg b "$body" --arg u "$url" '.comments += [{"body":$b,"url":$u}]' "$GH_STATE" > "$tmp" && mv "$tmp" "$GH_STATE"
        printf '%s\n' "$url"; exit 0 ;;
    esac ;;
  api)
    path=""; bf=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        */issues/comments/*) path="$1" ;;
        -F|--field) [[ "${2:-}" == body=@* ]] && bf="${2#body=@}" ;;
      esac
      shift
    done
    cid="${path##*/}"
    body="$(cat "$bf")"
    tmp="$(mktemp)"
    jq --arg c "$cid" --arg b "$body" '(.comments[] | select(.url | test("issuecomment-" + $c + "$")) | .body) |= $b' "$GH_STATE" > "$tmp" && mv "$tmp" "$GH_STATE"
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$GH_BIN/gh"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT" "$GH_BIN"' EXIT

# Render a fenced block in a subshell with the block sourced (pure — no gh needed).
render_once() { # args -> render_issue_comment_block
  (
    set +e
    log_dim() { :; }; log_info() { :; }; log_warn() { :; }
    log_success() { :; }; log_error() { :; }
    # shellcheck disable=SC1090
    source <(extract_issue_comment)
    render_issue_comment_block "$@"
  )
}

# Splice in a subshell; emits the spliced body, returns the splice rc.
splice_once() { # $1 existing-file  $2 block-file
  (
    set +e
    log_dim() { :; }; log_info() { :; }; log_warn() { :; }
    log_success() { :; }; log_error() { :; }
    # shellcheck disable=SC1090
    source <(extract_issue_comment)
    splice_managed_block "$1" "$2"
  )
}

# Run upsert_issue_comment against a temp REPO_ROOT with the gh stub on PATH and
# log_* shimmed to stdout (so the dry/real lines are observable).
run_upsert() { # env: GITHUB_WRITE, ISSUE_NUMBER, REPO_SLUG, REPO, GH_STATE, GH_CALL_LOG, PHASE, STORIES_COMPLETED, TOTAL_STORIES
  (
    set +e
    PATH="$GH_BIN:$PATH"
    REPO_ROOT="$REPO"
    STORY_LIST=()
    CURRENT_STORY_IDX=-1
    STORIES_COMPLETED="${STORIES_COMPLETED:-0}"
    TOTAL_STORIES="${TOTAL_STORIES:-3}"
    log_dim()     { printf '%s\n' "$1"; }
    log_info()    { printf '%s\n' "$1"; }
    log_warn()    { printf '%s\n' "$1"; }
    log_success() { printf '%s\n' "$1"; }
    log_error()   { printf 'ERR %s\n' "$1" >&2; }
    # shellcheck disable=SC1090
    source <(extract_write_guards)
    # shellcheck disable=SC1090
    source <(extract_issue_comment)
    upsert_issue_comment "${PHASE:-planning}"
  )
}

new_repo()  { mktemp -d -p "$TMPROOT"; }                       # plain dir (no git needed)
fresh_state() { printf '{"comments":[]}\n' > "$1"; }           # empty comment list
marker_count() { grep -c "^$2\$" "$1" 2>/dev/null || true; }   # $1 file $2 whole-line marker

echo "── Slice c issue-comment smoke ───────────────────────────────"

# ── 0. Sanity: the fenced block defines all three functions ──
ic_src="$(extract_issue_comment)"
if grep -q 'render_issue_comment_block()' <<< "$ic_src" \
   && grep -q 'splice_managed_block()' <<< "$ic_src" \
   && grep -q 'upsert_issue_comment()' <<< "$ic_src"; then
  pass "fenced block defines render_issue_comment_block + splice_managed_block + upsert_issue_comment"
else
  fail "fenced RALPH ISSUE COMMENT block not found or missing a function"
fi

# ── 1. Render determinism: same inputs -> byte-identical, one BEGIN + one END ──
r1="$(render_once building 7 1 3 1.2 'https://github.com/seevali/ralph-loop-demo/pull/77')"
r2="$(render_once building 7 1 3 1.2 'https://github.com/seevali/ralph-loop-demo/pull/77')"
begin_n="$(grep -c '^<!-- RALPH:BEGIN -->$' <<< "$r1" || true)"
end_n="$(grep -c '^<!-- RALPH:END -->$' <<< "$r1" || true)"
if [[ "$r1" == "$r2" && -n "$r1" && "$begin_n" -eq 1 && "$end_n" -eq 1 ]] \
   && grep -q '🟡 building — story 1.2 (1/3 done)' <<< "$r1" \
   && grep -q 'PR: https://github.com/seevali/ralph-loop-demo/pull/77' <<< "$r1"; then
  pass "render deterministic: same inputs → identical block (1 BEGIN, 1 END, 🟡 status, PR link)"
else
  fail "render not deterministic / malformed (begin=$begin_n end=$end_n identical=$([[ $r1 == $r2 ]] && echo yes || echo no))"
  sed 's/^/      /' <<< "$r1"
fi

# A done render with no PR url omits the PR line but stays well-formed.
rd="$(render_once done 7 3 3 '' '')"
if grep -q '🟢 done — 3/3 stories' <<< "$rd" && ! grep -q '^PR:' <<< "$rd" \
   && [[ "$(grep -c '^<!-- RALPH:BEGIN -->$' <<< "$rd" || true)" -eq 1 ]]; then
  pass "render done: 🟢 status, no PR line when url absent, still one fenced block"
else
  fail "render done malformed"
  sed 's/^/      /' <<< "$rd"
fi

# ── 2. Splice fail-closed: malformed managed regions abort with no output ──
block_file="$TMPROOT/block.md"
render_once planning 7 0 3 '' '' > "$block_file"

mk() { printf '%b' "$1" > "$2"; }   # write literal (with \n) to a file

# (a) zero fences
zero_f="$TMPROOT/zero.md";  mk 'just human text\nno fences here\n' "$zero_f"
# (b) duplicated BEGIN
dup_f="$TMPROOT/dup.md";    mk '<!-- RALPH:BEGIN -->\nx\n<!-- RALPH:BEGIN -->\ny\n<!-- RALPH:END -->\n' "$dup_f"
# (c) unbalanced: END before BEGIN
unb_f="$TMPROOT/unb.md";    mk '<!-- RALPH:END -->\nx\n<!-- RALPH:BEGIN -->\n' "$unb_f"

fc_ok=true
for bad in "$zero_f" "$dup_f" "$unb_f"; do
  out=""; rc=0
  out="$(splice_once "$bad" "$block_file")" || rc=$?
  if [[ "$rc" -eq 0 || -n "$out" ]]; then fc_ok=false; fi
done
if $fc_ok; then
  pass "splice fail-closed: zero / duplicated / unbalanced fences → return 1, NO output"
else
  fail "splice did NOT fail closed on a malformed managed region"
fi

# ── 3. Splice success: replace the fenced region, preserve bytes outside ──
good_f="$TMPROOT/good.md"
mk 'Reported by a human.\n\n<!-- RALPH:BEGIN -->\nstale status\n<!-- RALPH:END -->\n\nTrailing human note.\n' "$good_f"
spliced=""; src=0
spliced="$(splice_once "$good_f" "$block_file")" || src=$?
if [[ "$src" -eq 0 ]] \
   && grep -q '^Reported by a human.$' <<< "$spliced" \
   && grep -q '^Trailing human note.$' <<< "$spliced" \
   && grep -q '🔵 planning — 0/3 stories' <<< "$spliced" \
   && ! grep -q 'stale status' <<< "$spliced" \
   && [[ "$(grep -c '^<!-- RALPH:BEGIN -->$' <<< "$spliced" || true)" -eq 1 ]]; then
  pass "splice success: fenced region replaced, human bytes outside the fences preserved"
else
  fail "splice did not preserve/replace correctly (rc=$src)"
  sed 's/^/      /' <<< "$spliced"
fi

# ── 4. --write OFF: dry no-op — gh never called, a [dry] line logged ──
REPO="$(new_repo)"
export GH_STATE="$TMPROOT/state-off.json"; fresh_state "$GH_STATE"
export GH_CALL_LOG="$TMPROOT/calls-off.log"; : > "$GH_CALL_LOG"
off_rc=0
off_out="$(GITHUB_WRITE=0 ISSUE_NUMBER=7 REPO_SLUG="seevali/ralph-loop-demo" REPO="$REPO" PHASE=planning run_upsert)" || off_rc=$?
if [[ "$off_rc" -eq 0 && ! -s "$GH_CALL_LOG" ]] \
   && grep -q '\[dry\] gh issue comment 7 --body-file' <<< "$off_out"; then
  pass "--write off: no read/create/edit (gh never called), '[dry] gh issue comment …' logged (rc=0)"
else
  fail "--write off leaked: rc=$off_rc ghcalls=$(wc -l < "$GH_CALL_LOG")"
  sed 's/^/      /' <<< "$off_out"
fi

# ── 5. --write ON: create once, then edit in place (never a 2nd comment) ──
REPO="$(new_repo)"
export GH_STATE="$TMPROOT/state-on.json"; fresh_state "$GH_STATE"
export GH_CALL_LOG="$TMPROOT/calls-on.log"; : > "$GH_CALL_LOG"

c1_rc=0
c1_out="$(GITHUB_WRITE=1 ISSUE_NUMBER=7 REPO_SLUG="seevali/ralph-loop-demo" REPO="$REPO" PHASE=planning STORIES_COMPLETED=0 TOTAL_STORIES=3 run_upsert)" || c1_rc=$?
creates="$(grep -c '^issue comment ' "$GH_CALL_LOG" || true)"
edits="$(grep -c '^api --method PATCH' "$GH_CALL_LOG" || true)"
state_n="$(jq '.comments | length' "$GH_STATE")"
if [[ "$c1_rc" -eq 0 && "$creates" -eq 1 && "$edits" -eq 0 && "$state_n" -eq 1 ]]; then
  pass "--write on (1st call): created exactly one comment (no edit), comment list has 1 entry"
else
  fail "--write on create failed: rc=$c1_rc creates=$creates edits=$edits comments=$state_n"
  sed 's/^/      /' <<< "$c1_out"
fi

c2_rc=0
c2_out="$(GITHUB_WRITE=1 ISSUE_NUMBER=7 REPO_SLUG="seevali/ralph-loop-demo" REPO="$REPO" PHASE=done STORIES_COMPLETED=3 TOTAL_STORIES=3 run_upsert)" || c2_rc=$?
creates_after="$(grep -c '^issue comment ' "$GH_CALL_LOG" || true)"
edits_after="$(grep -c '^api --method PATCH' "$GH_CALL_LOG" || true)"
state_n_after="$(jq '.comments | length' "$GH_STATE")"
state_body="$(jq -r '.comments[0].body' "$GH_STATE")"
if [[ "$c2_rc" -eq 0 && "$creates_after" -eq 1 && "$edits_after" -eq 1 && "$state_n_after" -eq 1 ]] \
   && grep -q '🟢 done — 3/3 stories' <<< "$state_body"; then
  pass "--write on (2nd call): edited the SAME comment in place (still 1 create, 1 edit, 1 comment, now 🟢)"
else
  fail "idempotent upsert broke: rc=$c2_rc creates=$creates_after edits=$edits_after comments=$state_n_after"
  sed 's/^/      /' <<< "$c2_out"
fi

# ── 6. --write ON fail-closed: a malformed existing comment aborts the edit ──
REPO="$(new_repo)"
export GH_STATE="$TMPROOT/state-bad.json"
# Seed the comment list with a comment whose managed region has TWO BEGIN markers.
jq -n '{comments:[{body:"<!-- RALPH:BEGIN -->\nx\n<!-- RALPH:BEGIN -->\ny\n<!-- RALPH:END -->", url:"https://github.com/seevali/ralph-loop-demo/issues/7#issuecomment-1001"}]}' > "$GH_STATE"
export GH_CALL_LOG="$TMPROOT/calls-bad.log"; : > "$GH_CALL_LOG"
fc_rc=0
fc_out="$(GITHUB_WRITE=1 ISSUE_NUMBER=7 REPO_SLUG="seevali/ralph-loop-demo" REPO="$REPO" PHASE=building STORIES_COMPLETED=1 TOTAL_STORIES=3 run_upsert)" || fc_rc=$?
bad_creates="$(grep -c '^issue comment ' "$GH_CALL_LOG" || true)"
bad_edits="$(grep -c '^api --method PATCH' "$GH_CALL_LOG" || true)"
if [[ "$fc_rc" -eq 0 && "$bad_creates" -eq 0 && "$bad_edits" -eq 0 ]] \
   && grep -q 'aborting edit (fail-closed)' <<< "$fc_out"; then
  pass "--write on: malformed existing fences → edit aborted (no create, no PATCH), build continues (rc=0)"
else
  fail "--write on fail-closed broke: rc=$fc_rc creates=$bad_creates edits=$bad_edits"
  sed 's/^/      /' <<< "$fc_out"
fi

echo "──────────────────────────────────────────────────────────────"
printf 'Result: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
