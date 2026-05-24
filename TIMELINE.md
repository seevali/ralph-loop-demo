# Timeline

A chronological log of how this repo has evolved. Most-recent first.

Entries are tagged **`[Demo]`** (Demo Track — the frozen showcase) or **`[System]`** (System Track — loop-improvement work under [`system/`](system/)). See the [README's Two Tracks section](README.md#two-tracks) for the architecture.

For forward-looking design documents, browse [`system/chapters/`](system/chapters/) — one folder per improvement effort.

---

## 2026-05-24 — `[System]` Two-track restructure: introduced `system/` + chapter convention

Reshaped the repo into two tracks on the same branch:

- **Demo Track** stays at the root, untouched in shape — `docs/`, `src/`, `scripts/ralph-loop.sh`. Frozen showcase that cloners experience.
- **System Track** lives under [`system/`](system/) — its own README, CLAUDE.md, [`ralph-loop-system.sh`](system/ralph-loop-system.sh) wrapper, and a [`chapters/`](system/chapters/) folder where each loop-improvement effort is a self-contained dated folder with plan, PRD, epic, and stories.

The choice (single branch, two folders) over the alternative (two branches) was deliberate: keeping the System Track visible on the same branch as the demo means the public can see *both* the result and the path that got us there. The recursion (loop improving itself) becomes part of the demo's value, not a hidden development concern.

The migration also moved the prompt-modularization plan from `docs/plans/` into its new home as the first chapter — [`system/chapters/2026-05-24-modularize-loop-prompts/`](system/chapters/2026-05-24-modularize-loop-prompts/) — and replaced the `docs/plans/` convention with the chapter convention under `system/`.

**What landed (in commit order):**

- **`9cf23d4`** — scaffold `system/` skeleton + wrapper. Adds [`system/README.md`](system/README.md), [`system/CLAUDE.md`](system/CLAUDE.md) (system-track agent rules), [`system/ralph-loop-system.sh`](system/ralph-loop-system.sh) (thin wrapper that resolves a chapter and delegates to the canonical loop), and an empty `system/chapters/`.
- **`6652282`** — first chapter: `2026-05-24-modularize-loop-prompts`. Migrated the prompt-modularization plan from `docs/plans/` (now deleted) into [the chapter folder](system/chapters/2026-05-24-modularize-loop-prompts/), and operationalized it into a [PRD](system/chapters/2026-05-24-modularize-loop-prompts/prd.md) + [epic with 6 stories](system/chapters/2026-05-24-modularize-loop-prompts/epics/modularize-loop-prompts.md) that the System Track loop can execute.
- This commit — root [README](README.md), [CLAUDE.md](CLAUDE.md), and this TIMELINE updated for two-track awareness.

**Status:** ready to run `./system/ralph-loop-system.sh` against the first chapter.

---

## 2026-05-24 — `[System]` Plan: Modularize loop prompts & live-load BMAD personas

Drafted a refactor plan to extract the ~110 lines of hardcoded agent personas from `scripts/ralph-loop.sh` into a layered `scripts/prompts/` tree, and to live-load BMAD persona files at runtime so future BMAD updates flow in without touching the loop script. Recommended a 3-layer hybrid (repo-local execution-context override + live BMAD persona + repo-local stack rules) to satisfy both portability and update-resilience.

After the two-track restructure (above), the plan now lives as the README of its chapter folder:

Plan: [`system/chapters/2026-05-24-modularize-loop-prompts/`](system/chapters/2026-05-24-modularize-loop-prompts/)

**Status:** accepted, ready for loop execution.

---

## 2026-05-24 — `[Demo]` Phase 0: Scaffolding the demo

Initial scaffolding day. Brought the repo from empty to "ready to run the Ralph Loop overnight."

**What landed (in commit order):**

1. **[`752e46b`](https://github.com/seevali/ralph-loop-demo/commit/752e46b)** — Initial scaffold: `README.md`, `LICENSE` (MIT), `.gitignore`, empty `docs/`, `scripts/`, `src/`.
2. **[`e20d9d3`](https://github.com/seevali/ralph-loop-demo/commit/e20d9d3)** — `CLAUDE.md` with per-agent behavior rules + stack guardrails. Picked up automatically by every fresh Claude Code session inside the Ralph Loop.
3. **[`e80f1b7`](https://github.com/seevali/ralph-loop-demo/commit/e80f1b7)** — BMAD Method installed (`core` + `bmm` only) via `npx bmad-method install`. Both `_bmad/` and `.claude/skills/` are install products → gitignored. Decision: latest BMAD is v6.7+, which has no `bmad-agent-sm` — roles remapped to `bmad-create-story` (SM), `bmad-dev-story` (Dev), `bmad-code-review` (Reviewer).
4. **[`3296a08`](https://github.com/seevali/ralph-loop-demo/commit/3296a08)** — Vite + React + TypeScript app scaffolded in `src/`. Vitest + React Testing Library wired up. TS strict mode on.
5. **[`75ee4e1`](https://github.com/seevali/ralph-loop-demo/commit/75ee4e1)** — `scripts/ralph-loop.sh` copied verbatim from the upstream `ralph-affiant-v2.sh` (unmodified at this step, so the diff in the next commit is clean).
6. **[`0a14fd6`](https://github.com/seevali/ralph-loop-demo/commit/0a14fd6)** — PRD for the Exchange Rates monitoring dashboard generated by the BMAD PM agent. Decision: API = Frankfurter (`api.frankfurter.dev/v1`, keyless) instead of the keyed exchangerate.host originally suggested in the prompt — keyless is friendlier for a demo someone might clone and run on a whim.
7. **[`006f6d6`](https://github.com/seevali/ralph-loop-demo/commit/006f6d6)** — One epic + six small stories for the dashboard, generated by BMAD's epic/story workflow. Sized small intentionally so the overnight loop run lands in the tens-of-dollars range, not hundreds.
8. **[`998b283`](https://github.com/seevali/ralph-loop-demo/commit/998b283)** — Ralph loop script adapted to React/Vite/TS: stripped Affiant .NET specifics, replaced cached system prompts with React/TS conventions, baked in defaults so a bare `./scripts/ralph-loop.sh` invocation works. Loop semantics, model routing, retry, and budget caps left untouched.
9. **[`cf47cc5`](https://github.com/seevali/ralph-loop-demo/commit/cf47cc5)** — Setup marked complete in `todo.md` with a handoff summary.

**Status:** ready for first loop run. The Demo Track is now frozen — no further development planned here.

---
