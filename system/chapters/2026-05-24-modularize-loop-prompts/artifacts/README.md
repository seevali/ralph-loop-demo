# Semantic Equivalence Verification Script

Verifies that the refactored prompt system (stories 1.1–1.3) preserves all content from the original hardcoded prompts in `build_system_prompts()`.

## Purpose

Confirms that every significant content line from the pre-refactor baseline is present in the post-refactor layered output. Ordering, formatting, and separator differences are expected and allowed.

## Usage

```bash
bash system/chapters/2026-05-24-modularize-loop-prompts/artifacts/verify-semantic-equivalence.sh
```

Exit code: **0** = all roles pass, **1** = one or more roles have missing lines.

## When to Run

- **Story 1.4** (now): confirm the layered prompts capture all hardcoded content.
- **Story 1.5** (after wiring the loader and deleting inline strings): re-confirm nothing was lost.
