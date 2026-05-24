#!/bin/bash
set -euo pipefail

# Verifies that the layered prompt system (stories 1.1-1.3) captures all
# significant content from the pre-refactor build_system_prompts() output.
# Run from the repo root. Exit 0 = all roles pass, 1 = one or more fail.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

TMP_DIR=""

cleanup() {
  [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# ----------------------------------------------------------------------
# capture_baseline: runs build_system_prompts() from ralph-loop.sh
# and writes baseline_{sm,dev,review}.txt to the given output directory.
# We extract the function with awk and run it in a minimal environment
# to avoid executing ralph-loop.sh's main loop.
# ----------------------------------------------------------------------
capture_baseline() {
  local outdir="$1"
  local extractor="${outdir}/run_build.sh"

  # Part 1: dynamic header — REPO_ROOT injected from the current environment
  cat > "$extractor" << HEADER
#!/bin/bash
set -euo pipefail
REPO_ROOT="$REPO_ROOT"
HEADER

  # Part 2: static body — persona loading mirrors ralph-loop.sh lines 332-358
  cat >> "$extractor" << 'BODY'
CHECKPOINT_CMD="cd src && npm run build && npm test --if-present"
LOG_FILE="/dev/null"
BMAD_ROOT="$REPO_ROOT/.claude/skills"

log_info() { :; }
log_dim()  { :; }
log_warn() { :; }

AGENT_SM_PERSONA=""
AGENT_DEV_PERSONA=""
AGENT_REVIEW_PERSONA=""

if [[ -f "$BMAD_ROOT/bmad-create-story/SKILL.md" ]]; then
  AGENT_SM_PERSONA=$(cat "$BMAD_ROOT/bmad-create-story/SKILL.md")
fi
if [[ -f "$BMAD_ROOT/bmad-dev-story/SKILL.md" ]]; then
  AGENT_DEV_PERSONA=$(cat "$BMAD_ROOT/bmad-dev-story/SKILL.md")
fi
if [[ -f "$BMAD_ROOT/bmad-code-review/SKILL.md" ]]; then
  AGENT_REVIEW_PERSONA=$(cat "$BMAD_ROOT/bmad-code-review/SKILL.md")
  shopt -s nullglob
  for _step in "$BMAD_ROOT/bmad-code-review/steps/"*.md; do
    AGENT_REVIEW_PERSONA+=$'\n\n'"$(cat "$_step")"
  done
  shopt -u nullglob
fi

SYSTEM_PROMPT_SM=""
SYSTEM_PROMPT_DEV=""
SYSTEM_PROMPT_REVIEW=""
BODY

  # Part 3: extract build_system_prompts() function definition from ralph-loop.sh.
  # Stops at the first top-level closing brace (the only one at column 0).
  awk '/^build_system_prompts\(\)/{found=1} found{print} found && /^\}$/{exit}' \
    "$REPO_ROOT/scripts/ralph-loop.sh" >> "$extractor"

  # Part 4: call the function and write each role's prompt to a file
  cat >> "$extractor" << 'FOOTER'

build_system_prompts

printf '%s\n' "$SYSTEM_PROMPT_SM"     > "${OUTDIR}/baseline_sm.txt"
printf '%s\n' "$SYSTEM_PROMPT_DEV"    > "${OUTDIR}/baseline_dev.txt"
printf '%s\n' "$SYSTEM_PROMPT_REVIEW" > "${OUTDIR}/baseline_review.txt"
FOOTER

  OUTDIR="$outdir" bash "$extractor" 2>/dev/null
}

# ----------------------------------------------------------------------
# capture_layered: runs --dry-run-prompts and parses its delimited output
# into layered_{sm,dev,review}.txt in the given output directory.
# ----------------------------------------------------------------------
capture_layered() {
  local outdir="$1"
  local raw_output
  raw_output=$(cd "$REPO_ROOT" && ./scripts/ralph-loop.sh --dry-run-prompts 2>/dev/null)

  # Extract each section between its === ROLE === header and the next one.
  # Log lines (starting with ANSI codes) never match ^=== so they are ignored.
  awk '/^=== SM ===$/{f=1;next} /^=== [A-Z]/{if(f)exit} f{print}' \
    <<< "$raw_output" > "${outdir}/layered_sm.txt"

  awk '/^=== DEV ===$/{f=1;next} /^=== [A-Z]/{if(f)exit} f{print}' \
    <<< "$raw_output" > "${outdir}/layered_dev.txt"

  # REVIEW is the last section — it extends to end of output
  awk '/^=== REVIEW ===$/{f=1;next} f{print}' \
    <<< "$raw_output" > "${outdir}/layered_review.txt"
}

# ----------------------------------------------------------------------
# is_significant: returns 0 (true) if a line should be checked,
# 1 (false) if it should be skipped.
# Skipped: empty/whitespace-only, ## section headers, --- separators,
# the "# Agent Persona" stub heading, and the REVIEW-specific wrapper
# sentence that build_system_prompts adds before the review persona but
# that is intentionally absent in the new layered architecture (the
# SKILL.md provides its own equivalent role description).
# ----------------------------------------------------------------------
is_significant() {
  local line="$1"
  [[ "$line" =~ ^[[:space:]]*$ ]]                        && return 1
  [[ "$line" =~ ^##[[:space:]] ]]                        && return 1
  [[ "$line" =~ ^---[[:space:]]*$ ]]                     && return 1
  [[ "$line" =~ ^#[[:space:]]+Agent[[:space:]]+Persona ]] && return 1
  # build_system_prompts adds this sentence as a wrapper intro for the review
  # persona; the new architecture drops it in favour of the SKILL.md's own
  # self-description. Filter it so the known structural difference doesn't fail.
  [[ "$line" == "You are the BMAD Code Review agent. Apply the adversarial review approach (Blind Hunter + Edge Case Hunter + Acceptance Auditor) and triage methodology. The full BMAD review workflow is provided below." ]] && return 1
  return 0
}

# ----------------------------------------------------------------------
# compare_role: verifies every significant baseline line is a substring
# of the layered output. Prints a pass/fail summary line plus any missing
# lines. Returns 0 on pass, 1 on fail.
# ----------------------------------------------------------------------
compare_role() {
  local role="$1"
  local baseline_file="$2"
  local layered_file="$3"

  local checked=0
  local missing=()

  while IFS= read -r line; do
    is_significant "$line" || continue
    checked=$((checked + 1))
    if ! grep -qF -- "$line" "$layered_file"; then
      missing+=("$line")
    fi
  done < "$baseline_file"

  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "${role}: PASS (${checked} significant lines checked)"
    return 0
  else
    echo "${role}: FAIL (${checked} significant lines checked, ${#missing[@]} missing)"
    for m in "${missing[@]}"; do
      echo "  - ${m}"
    done
    return 1
  fi
}

# ----------------------------------------------------------------------
# main
# ----------------------------------------------------------------------
main() {
  TMP_DIR="$(mktemp -d /tmp/verify-semantic-XXXXXX)"

  cd "$REPO_ROOT"

  [[ -f "./scripts/ralph-loop.sh" ]] || {
    echo "ERROR: scripts/ralph-loop.sh not found — run from repo root" >&2
    exit 1
  }
  [[ -d "./scripts/prompts" ]] || {
    echo "ERROR: scripts/prompts/ not found — story 1.1 not applied" >&2
    exit 1
  }

  echo "Capturing baseline via build_system_prompts()..."
  capture_baseline "$TMP_DIR" || {
    echo "ERROR: baseline capture failed" >&2
    exit 1
  }

  echo "Capturing layered output via --dry-run-prompts..."
  capture_layered "$TMP_DIR" || {
    echo "ERROR: layered capture failed" >&2
    exit 1
  }

  echo ""

  local sm_rc=0 dev_rc=0 review_rc=0
  local sm_result dev_result review_result

  sm_result=$(compare_role     "SM"     "${TMP_DIR}/baseline_sm.txt"     "${TMP_DIR}/layered_sm.txt")     || sm_rc=1
  dev_result=$(compare_role    "DEV"    "${TMP_DIR}/baseline_dev.txt"    "${TMP_DIR}/layered_dev.txt")    || dev_rc=1
  review_result=$(compare_role "REVIEW" "${TMP_DIR}/baseline_review.txt" "${TMP_DIR}/layered_review.txt") || review_rc=1

  if [[ $sm_rc -eq 0 && $dev_rc -eq 0 && $review_rc -eq 0 ]]; then
    echo "PASS: semantic equivalence check"
    echo ""
    echo "$sm_result"
    echo "$dev_result"
    echo "$review_result"
    exit 0
  else
    {
      echo "FAIL: semantic equivalence check"
      echo ""
      echo "$sm_result"
      echo "$dev_result"
      echo "$review_result"
      echo ""
      echo "Exit code: 1"
    } >&2
    exit 1
  fi
}

main "$@"
