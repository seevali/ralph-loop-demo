# PRD: Modularize the Ralph Loop's Prompt System

**Chapter:** [2026-05-24-modularize-loop-prompts](README.md)
**Date:** 2026-05-24
**Status:** accepted, ready for loop execution

---

## Background

The Ralph Loop is a Bash orchestrator at `scripts/ralph-loop.sh` that drives BMAD agents (Scrum Master, Developer, Code Reviewer) through a SM → Dev → Review → Fix cycle for each story. Each step is a fresh Claude Code session that reads the loop's `--append-system-prompt` injection.

Today, the system prompts injected into each agent are hardcoded as heredocs inside the bash script — approximately 110 lines of persona, execution-context, and review-standard text baked into the orchestrator. This has two costs:

1. **Maintenance burden.** Changes to persona behavior require editing a 1200-line shell script.
2. **Stale personas.** BMAD ships its own persona files (under `.claude/skills/<skill-name>/`); the loop ignores them. When BMAD updates a persona, the loop doesn't pick up the change.

## Goal

Refactor the loop's prompt system so:

1. Repo-local prompt content lives in external `.md` files, not heredocs.
2. BMAD's persona files are loaded fresh from the filesystem on every run, so future BMAD updates flow into the loop with no script changes.
3. The change preserves prompt-cache hits, loop semantics, multi-model routing, retry logic, and budget caps — all untouched.

## Approach

Three-layer composition for each cached system prompt:

```
[Layer 1: Execution Context Override]   ← repo-local, stable
[Layer 2: BMAD Persona]                 ← live from .claude/skills/
[Layer 3: Demo-Specific Rules]          ← repo-local stack / review rules
```

Layer 1 first ensures the loop's non-interactive contract wins over any "HALT and wait" instructions in BMAD personas. Layer 2 lets BMAD updates flow in automatically. Layer 3 last ensures stack-specific rules (React/TS conventions, review standards) are the most-recent instruction the model sees.

Full design rationale, file layout, loading mechanism pseudocode, migration sequence, and test plan are in [the chapter plan (README.md)](README.md).

## Constraints

- **Bash only.** No language switches.
- **No changes to loop semantics.** Multi-model routing, retry, smart-salvage, upstream-fix detection, budget caps, `run_claude()` signature are all read-only.
- **Prompt-cache preservation.** Every change must pass the byte-diff gate (resolved system prompt is byte-identical pre- and post-refactor).
- **Self-contained repo.** No references to anything outside this repo.

## Out of scope

- The six user-prompt heredocs in the loop (same externalization pattern, flagged as a follow-up chapter).
- BMAD config / `customize.toml` / `_bmad/` itself.
- The Demo Track. Nothing under `docs/` or `src/` is touched.

## Success criteria

1. Resolved system prompts before and after the refactor are byte-identical (verified via `--dry-run-prompts`).
2. Editing `.claude/skills/bmad-dev-story/SKILL.md` causes the Dev agent's prompt to reflect the change without modifying `scripts/ralph-loop.sh`.
3. A single-story smoke run completes with `cache_read > 0` on the Dev-after-SM call (Layer 1+3 overlap → cache hits).
4. All existing demo-track stories (1.1–1.6) can still be executed by the loop with no observable behavior change.
