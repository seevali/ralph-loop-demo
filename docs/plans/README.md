# Plans

Forward-looking work products for this repo. Each plan is a self-contained design document — readable by anyone (or any LLM) landing on the file with no prior context.

## Convention

- **Filename:** `YYYY-MM-DD-short-slug.md` (date-prefixed for chronological sortability).
- **Status:** every plan declares one of `proposed | accepted | in-progress | complete | superseded` in its header.
- **Portability:** plans must satisfy the cold-start test — a fresh reader (different LLM, no project memory) can act on the plan from the file alone. Define project-specific terms inline or link to definitions in this repo.
- **Lifecycle:** once a plan is complete or superseded, leave it in place — don't delete. The historical record matters more than tidiness.

## Index

- [2026-05-24-modularize-loop-prompts.md](2026-05-24-modularize-loop-prompts.md) — extract hardcoded system prompts from `scripts/ralph-loop.sh` and live-load BMAD personas so future BMAD updates don't require touching the loop. **Status:** proposed.
