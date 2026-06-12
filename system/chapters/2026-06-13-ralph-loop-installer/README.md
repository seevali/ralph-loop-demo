# Plan: Ralph Loop Guided Installer

**Chapter:** `2026-06-13-ralph-loop-installer`
**Date:** 2026-06-13
**Status:** accepted, ready for loop execution
**Author:** Seevali Rathnayake (drafted with Claude in Chat, reconciled against the repo with Claude in Cowork)
**PRD:** [prd.md](prd.md)
**Epic:** [epics/ralph-loop-installer.md](epics/ralph-loop-installer.md)

---

## Cold-start context (read first if you're new here)

- **Ralph Loop** — a build pattern where each step of work (plan a story, implement it, review it, fix it) runs in a *fresh* Claude Code session. This repo's canonical implementation is the bash orchestrator [`scripts/ralph-loop.sh`](../../../scripts/ralph-loop.sh). See the repo [README](../../../README.md).
- **BMAD Method** — role-based AI agents from [bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD), installed via `npx bmad-method install` (creates `_bmad/` and `.claude/skills/`, both gitignored). The loop maps SM = `bmad-create-story`, Dev = `bmad-dev-story`, Review = `bmad-code-review`.
- **Chapter** — a self-contained improvement effort under [`system/chapters/`](../). Run with `./system/ralph-loop-system.sh 2026-06-13-ralph-loop-installer`.
- **Adoption path today** — a user who wants the loop in their own project must clone this repo, copy `scripts/ralph-loop.sh` + `scripts/prompts/` by hand, write a PRD and epic stubs in the strict format, edit prompt files for their stack, install BMAD with the right flags, and read a long README to learn all of that. The README's "Adapting this to your project" section estimates ~1 hour for a focused developer. This chapter replaces that with one command.

## Problem

The loop's value is clear; its setup is not. There is no installer at all — onboarding is "clone and read." The BMAD Method solved the identical adoption problem with `npx bmad-method install`: one command, a short wizard, sensible defaults, non-interactive flags, and a safe update path. No public Ralph implementation offers that (gap analysis in [prd.md §Prior art](prd.md)); a polished installer is a differentiator, not a parity feature.

**Goal:** `npx <package> install` sets up a working Ralph Loop in an empty directory or an existing project in under 5 minutes, teaching the concepts as it goes, with BMAD-installer-level polish.

## Reconciliation: original draft vs. repo reality

This chapter's PRD was first drafted in Claude Chat without repository access ([artifacts/prd-draft-2026-06-12.md](artifacts/prd-draft-2026-06-12.md) — superseded). The draft's §2.1 assumptions were checked against the actual repo; the corrections below are binding on all stories:

| Draft assumption | Reality |
|---|---|
| Loop script maybe `ralph.sh`/`loop.sh`, prompt file `PROMPT.md` | `scripts/ralph-loop.sh` + 3-layer prompt composition in `scripts/prompts/` (`{{CHECKPOINT_CMD}}` placeholder, BMAD personas live-loaded from `.claude/skills/`) |
| Prereqs: Node ≥ 20 + git only | Also **`jq`**, the **`claude` CLI**, and a **bash environment** (macOS/Linux/WSL2 — no native Windows) |
| "Agent CLI selection" wizard step | The loop is **Claude Code only** (`run_claude()` is part of the safety contract). No agent picker in v1 |
| `prd.json` / task-file completion signals | Stories live in a markdown epic; the parser requires `### Story X.Y: Title` headers exactly; completion = all stories pass review |
| `ralph.config.json` captures existing knobs | The loop is **flag-driven with baked defaults**; there is no config file. The installer's manifest records wizard answers for update/doctor purposes, and generated docs show the matching flag invocation |
| BMAD not mentioned | BMAD install is **half the setup** (`npx bmad-method install --modules core,bmm --tools claude-code --output-folder docs ...`). The installer drives it |
| Installer language unconstrained | [`system/CLAUDE.md`](../../CLAUDE.md) mandates Bash + Markdown for System Track work — **Story 1.1 amends the rules** to permit Node strictly inside `installer/` |

## Decisions (made at planning time)

1. **Node.js installer, confined to `installer/`.** The npx UX is the whole point (BMAD parity). Story 1.1 amends `system/CLAUDE.md` and the root `CLAUDE.md` to carve out `installer/` as the only Node-permitted System Track surface. The loop itself stays bash, untouched.
2. **Full lifecycle scope in v1:** install, update, uninstall, doctor, full non-interactive mode. (The original "trim to MVP" option was rejected by the author.)
3. **The installer drives BMAD installation** as a wizard step, not just instructions.
4. **CLI stack:** `@clack/prompts` (wizard) + Commander (flags/subcommands) + `picocolors`. Ink rejected (bundle/cold-start cost), Inquirer rejected (legacy). Node ≥ 20, distributed via npm/npx.
5. **npm package name:** `ralph-loop` and `create-ralph-loop` are **already taken** on npm (verified 2026-06-13, both by third parties). Candidates: `@seevali/ralph-loop` (scoped, guaranteed) or `ralph-loop-installer` (unscoped, free as of the check). Final pick in Story 4.3.

## Design

### Package layout (new top-level directory `installer/`)

```
installer/
├── package.json              # bin, engines.node >= 20, files whitelist
├── bin/ralph.js              # entry → Commander
├── src/                      # commands: install, update, uninstall, doctor
│   ├── preflight.js          # node/git/jq/claude/bash-env checks
│   ├── classify.js           # empty | existing-project | existing-install
│   ├── wizard.js             # @clack/prompts flow → InstallPlan object
│   ├── writer.js             # template render, conflict detection, manifest
│   └── bmad.js               # drives npx bmad-method install
├── templates/
│   ├── loop/                 # SYNCED copies of scripts/ralph-loop.sh + scripts/prompts/**
│   └── project/              # authored here: CLAUDE.md, prd stub, epic stub,
│                             #   GETTING-STARTED.md, .gitignore fragment
├── scripts/sync-templates.sh # bash; copies canonical loop files in; --check mode
└── test/                     # node:test units + bash-driven E2E fixtures
```

**Template sync is the integrity mechanism.** The canonical loop files stay where they are (`scripts/`); `sync-templates.sh` copies them into `templates/loop/` and `--check` fails on drift. The review gate runs the check, so the published package can never ship a stale loop.

### Installed footprint (in the user's target project)

Mirrors the demo's layout so every doc in this repo applies verbatim to an installed project:

```
target/
├── scripts/ralph-loop.sh         # installer-owned
├── scripts/prompts/**            # installer-owned, except project-conventions.md
├── docs/prd.md                   # user-owned stub with teaching comments
├── docs/epics/<name>.md          # user-owned story stubs, strict `### Story X.Y:` headers
├── CLAUDE.md                     # user-owned (only written if absent)
├── GETTING-STARTED.md            # regenerated each install/update
└── .ralph/manifest.json          # version, file checksums, wizard answers
```

The manifest's installer-owned vs user-owned classification powers the update flow: updates replace installer-owned files, never user-owned ones; a locally modified installer-owned file triggers keep / take-new / backup-and-take-new.

### Wizard flow (interactive path)

1. Intro + one-paragraph explainer of the loop (educates novices, skimmable by experts)
2. Preflight checklist (Node ≥ 20, git, jq, claude CLI, bash environment; native Windows without bash → honest stop with WSL2 guidance)
3. Target directory confirmation + classification summary (empty → offer `git init` + skeleton; existing project → detected signals, additive-only changes; existing install → switch to update mode)
4. Project facts: app directory, checkpoint command, one-line stack description (rendered into `project-conventions.md`)
5. Loop knobs: max iterations, budget caps (all defaulted — Enter-Enter-Enter must produce a working install)
6. Task source: scaffold commented PRD/epic stubs, or point at existing files
7. BMAD: confirm + run `npx bmad-method install` non-interactively under a spinner (skippable; failure prints the exact manual command)
8. Summary of every write → confirm → write under spinner → outro with numbered next steps

No file is written before the final confirmation; Ctrl-C anywhere exits with "nothing was changed."

### Non-interactive mode

Every wizard question has a flag; `--yes` accepts defaults; `--list-options` prints the surface; conflicts without `--force` fail fast non-zero; non-TTY output degrades to plain lines (no spinners/ANSI, `NO_COLOR` respected).

## Constraints

- **Demo Track frozen.** Nothing under `docs/` or `src/` changes. `scripts/ralph-loop.sh` and `scripts/prompts/` are read-only inputs to the sync script.
- **Loop safety contract untouched** (multi-model routing, retry, budget caps, `run_claude()` signature).
- **Self-contained repo.** The installer references nothing outside the repo; the npm package is built solely from `installer/`.
- **Node only inside `installer/`** (after Story 1.1's rule amendment). Sync script and E2E drivers are bash.
- **Minimal deps:** `@clack/prompts`, `commander`, `picocolors`. Unit tests use `node:test` (no test-framework dependency). Package target < 1 MB unpacked.
- **No telemetry, no network calls** beyond npm itself and the BMAD install step the user confirms.

## Test plan

- **Unit (node:test):** preflight (PATH stubbing), classifier (fixture dirs), template rendering, conflict detection, manifest read/write. Runs via `cd installer && npm test`.
- **E2E (bash fixtures):** non-interactive install into (a) empty dir, (b) existing-project fixture; then `doctor` passes; then re-run install → update mode → zero user-owned files changed; then uninstall → installer-owned files gone, user-owned listed and preserved.
- **Sync gate:** `installer/scripts/sync-templates.sh --check` byte-compares `templates/loop/` against `scripts/`.
- **Script syntax gate (existing):** `bash -n ./scripts/ralph-loop.sh && bash -n ./system/ralph-loop-system.sh`, extended with `bash -n installer/scripts/sync-templates.sh`.
- **Smoke (manual, pre-release):** `npm pack` + `npx` the tarball on a clean machine; install into a toy project; run one loop story end-to-end.

## Risks

- **Story sizing.** Wizard (2.2), write engine (2.3), and update flow (3.2) exceed the System Track ~150-line story guideline. The SM agent must split them at run time; the epic flags each.
- **Reviewer gates need extending.** `system/CLAUDE.md`'s hard blocks don't yet cover Node. Story 1.1 adds: hard-block on `cd installer && npm test` failure and on sync-check failure.
- **`npx bmad-method install` interface drift.** The BMAD step shells out with today's flags; if BMAD changes them, the step fails. Mitigation: failure is non-fatal — print the manual command and continue; flags isolated in `bmad.js`.
- **Name squatting.** Both preferred npm names are taken by third-party Ralph projects. Mitigation: decided candidates in hand (Decision 5); confusion risk with the existing `create-ralph-loop` package is noted for the README.
- **Windows.** Installer (Node) runs anywhere, but the loop needs bash. Preflight detects native Windows without bash and stops honestly. PowerShell runner deferred (out of scope).

## Out of scope (explicitly)

- Changing the loop's runtime behavior — the loop installs as-is.
- Multi-agent support (Claude Code only, matching the loop).
- Global `ralph` command, GUI/web installer, Docker provisioning, release channels (`latest` only in v1), telemetry, PowerShell loop runner.
- The Demo Track: `docs/`, `src/` untouched.
- Actually publishing to npm inside a loop run — Story 4.3 prepares everything; the human pushes the button.

## Glossary

- **InstallPlan** — the in-memory object the wizard builds; the writer executes it only after final confirmation.
- **Installer-owned / user-owned** — file classes in `.ralph/manifest.json`. Installer-owned files are replaceable on update; user-owned files are never touched after creation.
- **Template sync** — the build-time copy of canonical loop files into the npm package, gated by `--check`.
- **Preflight** — the environment checks (Node, git, jq, claude CLI, bash) run before the wizard.
