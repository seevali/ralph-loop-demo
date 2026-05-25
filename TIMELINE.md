# Timeline

A chronological log of how this repo has evolved. Most-recent first.

Entries are tagged **`[Demo]`** (Demo Track — the frozen showcase) or **`[System]`** (System Track — loop-improvement work under [`system/`](system/)). See the [README's Two Tracks section](README.md#two-tracks) for the architecture.

For forward-looking design documents, browse [`system/chapters/`](system/chapters/) — one folder per improvement effort.

---

## 2026-05-25 — `[System]` Chapter 1 closed: prompts modularized, BMAD personas live-loaded

The first System Track chapter — [`2026-05-24-modularize-loop-prompts`](system/chapters/2026-05-24-modularize-loop-prompts/) — closed with tag [`system-ch1-complete`](https://github.com/seevali/ralph-loop-demo/releases/tag/system-ch1-complete). The chapter delivered exactly what its [plan](system/chapters/2026-05-24-modularize-loop-prompts/README.md) promised: ~110 lines of hardcoded persona/execution-context heredocs are gone from `scripts/ralph-loop.sh`. A new `load_prompt_layers(role)` helper assembles each cached system prompt from three concatenated layers — an execution-context override from [`scripts/prompts/common/execution-context.md`](scripts/prompts/common/execution-context.md) (layer 1), the live BMAD persona from `.claude/skills/<role>/SKILL.md` (layer 2), and project-specific rules from [`scripts/prompts/common/project-conventions.md`](scripts/prompts/common/project-conventions.md) + a role overlay (layer 3). Future BMAD releases now flow into the loop automatically; the only place the demo's stack rules live is the `scripts/prompts/` directory, which cloners can edit when forking for a different stack.

A re-runnable [semantic equivalence script](system/chapters/2026-05-24-modularize-loop-prompts/artifacts/verify-semantic-equivalence.sh) confirms that every significant content line from the original heredoc assembly is still present in the new layered output (SM 366 lines, Dev 396 lines, Review 276 lines, all accounted for).

**The honest narrative.** The chapter ran in two passes. The first pass exposed three infrastructure bugs in the Ralph Loop itself that any future System Track chapter would also have hit — and that the first chapter wouldn't have surfaced as cleanly without using the loop on itself. Each fix landed as its own `fix(system):` commit so the bugs and their corrections are publicly readable in the git log:

- **`ad19753 fix(system): unblock first chapter run`** — surfaced when story 1.1 couldn't even start. `STORIES_DIR` was hardcoded to the Demo Track's `docs/stories/`, and the loop's epic parser required a specific `### Story X.Y:` header format my hand-written epic didn't match. The fix made `STORIES_DIR` honor an env-var override (the wrapper sets it to the chapter's own stories folder) and rewrote the epic headers.
- **`b93ed36 fix(system): make review verdict parser robust to title lines`** — surfaced when story 1.1's Code Review agent wrote a perfectly correct `REVIEW_PASSED` verdict but on line 3 of the file (after a `# Story 1.1 Code Review` markdown title), and the loop's parser was reading only line 1 with `head -1`. Three retry cycles burned before the loop gave up on a passing review. The fix introduced `is_review_passed()` — a lenient parser that finds `^REVIEW_PASSED` anywhere in the file — and replaced all seven call sites. Also strengthened the agent's prompt instructions to be more explicit about the literal-first-line requirement.
- **`fc26418 fix(system): EXTRA_STAGE_PATHS env-var override for auto-commit staging`** — the most subtle. Stories 1.2 and 1.3 *appeared* to land cleanly (the loop committed `feat(1.2)` and `feat(1.3)`), but those commits contained **only the story docs** — the actual `load_prompt_layers()` function and `--dry-run-prompts` flag the agents wrote were orphaned in the working tree. The loop's auto-commit step had a hardcoded narrow staging list (`src/` + `docs/stories/`) that was Demo-Track-correct but System-Track-blind. Discovered when story 1.4's Dev agent inherited the uncommitted code and burned $4 of budget trying to do its own work on top. The fix added an `EXTRA_STAGE_PATHS` env var (same shape as `STORIES_DIR`) that the wrapper sets to `scripts/ system/ README.md CLAUDE.md TIMELINE.md`. Then a separate `f1e9cf9 fix(1.2,1.3)` commit rescued the orphaned code from the working tree without rewriting history — chosen over a `rebase -i` because the messy-but-truthful trail is more valuable than a clean-but-misleading one.

Story 1.4 also surfaced a chapter-plan flaw: the original spec asked for a **byte-identical** diff between pre- and post-refactor prompt assemblies, but the chapter plan also specified a new layer ordering (Layer 1 Execution Context first, vs. the old structure with persona first). These two requirements are architecturally incompatible. Story 1.4's acceptance criterion was rewritten ([`4f42599 chore(1.4)`](https://github.com/seevali/ralph-loop-demo/commit/4f42599)) to a semantic equivalence check — same primitive (verify no content was dropped), achievable target. The 1.4 Dev agent then built the semantic verification script and it passed first try.

**What landed (15 commits, in chronological order):**

1. **[`9cf23d4`](https://github.com/seevali/ralph-loop-demo/commit/9cf23d4)** — scaffold the `system/` folder skeleton + wrapper
2. **[`6652282`](https://github.com/seevali/ralph-loop-demo/commit/6652282)** — first chapter directory + migrate plan into chapter
3. **[`9d3c573`](https://github.com/seevali/ralph-loop-demo/commit/9d3c573)** — root docs (README/CLAUDE.md/TIMELINE) made two-track aware
4. **[`ad19753`](https://github.com/seevali/ralph-loop-demo/commit/ad19753)** — `fix(system)` #1: unblock first chapter run (`STORIES_DIR` + epic headers)
5. **[`28eabe7`](https://github.com/seevali/ralph-loop-demo/commit/28eabe7)** — `feat(1.1)`: extract repo-local prompt files (manually accepted after parser misread the passing review)
6. **[`b93ed36`](https://github.com/seevali/ralph-loop-demo/commit/b93ed36)** — `fix(system)` #2: lenient `REVIEW_PASSED` parser
7. **[`5817069`](https://github.com/seevali/ralph-loop-demo/commit/5817069)** — `feat(1.2)`: docs only (loop staging bug, fixed below)
8. **[`2874bda`](https://github.com/seevali/ralph-loop-demo/commit/2874bda)** — `feat(1.3)`: docs only (same staging bug)
9. **[`f1e9cf9`](https://github.com/seevali/ralph-loop-demo/commit/f1e9cf9)** — `fix(1.2,1.3)`: rescue orphaned `load_prompt_layers()` and `--dry-run-prompts` code from working tree
10. **[`fc26418`](https://github.com/seevali/ralph-loop-demo/commit/fc26418)** — `fix(system)` #3: `EXTRA_STAGE_PATHS` env-var override; prevents this class of bug recurring
11. **[`4f42599`](https://github.com/seevali/ralph-loop-demo/commit/4f42599)** — `chore(1.4)`: rewrite story 1.4 from byte-diff to semantic equivalence
12. **[`330bdd9`](https://github.com/seevali/ralph-loop-demo/commit/330bdd9)** — `feat(1.4)`: semantic equivalence verification script
13. **[`5209248`](https://github.com/seevali/ralph-loop-demo/commit/5209248)** — `feat(1.5)` (code): rewire `build_system_prompts()` to call `load_prompt_layers()`; delete heredocs
14. **[`ef3a081`](https://github.com/seevali/ralph-loop-demo/commit/ef3a081)** — `feat(1.5)` (docs): story spec + done + review for 1.5
15. **[`137a8be`](https://github.com/seevali/ralph-loop-demo/commit/137a8be)** — `feat(1.6)`: root README + CLAUDE.md mention `scripts/prompts/`; chapter plan flipped to `Status: complete`

**Status:** chapter 1 closed and tagged. Chapter 2 (if/when) will inherit a much better-instrumented loop — three infrastructure fixes ahead of where the first chapter started. The recursion the demo set out to show is now public-record visible: a tool that used itself to forge itself, with every misstep traceable.

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
