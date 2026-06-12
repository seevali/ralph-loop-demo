# Epics: Ralph Loop Guided Installer

**Chapter:** [2026-06-13-ralph-loop-installer](../README.md)
**PRD:** [../prd.md](../prd.md)
**Status:** ready for loop execution

Story stubs only — the loop's SM agent expands each into a detailed spec at run time. Headers follow the loop parser's strict `### Story X.Y: Title` format. Stories marked **[SM: split if needed]** likely exceed the System Track ~150-line guideline; the SM agent should split them rather than expand them whole.

---

## Epic 1: Foundation

### Story 1.1: Amend stack rules and repo docs for the installer directory

- `system/CLAUDE.md`: permit Node.js strictly inside `installer/`; extend reviewer hard blocks with `cd installer && npm test` and `installer/scripts/sync-templates.sh --check` (once those exist); everything outside `installer/` remains Bash + Markdown.
- Root `CLAUDE.md` and `README.md`: add `installer/` to the repo layout; record the top-level-directory exception as required by this story.
- AC: both files render the new rules; no other rules weakened; `bash -n` gates unchanged.

### Story 1.2: Scaffold the installer npm package

- `installer/package.json` (placeholder name, `engines.node >= 20`, `bin`, `files` whitelist), Commander skeleton with `install`, `update`, `uninstall`, `doctor` stubs, `--version`/`--help`.
- `npm test` wired to `node:test` with one passing placeholder test.
- AC: `node installer/bin/ralph.js --help` lists all subcommands and exits 0; `cd installer && npm test` passes.

### Story 1.3: Template sync script with drift gate

- `installer/scripts/sync-templates.sh` (bash, `set -euo pipefail`): copies `scripts/ralph-loop.sh` + `scripts/prompts/**` into `installer/templates/loop/`; `--check` mode byte-compares and exits non-zero on drift.
- AC: sync then `--check` passes; touching a synced copy makes `--check` fail; `bash -n` passes on the script.

### Story 1.4: Preflight checks module

- `installer/src/preflight.js`: Node ≥ 20 (hard fail), git (warn + confirm), jq (warn + per-OS install hint), `claude` CLI (warn only), bash-environment detection (native Windows without bash → stop with WSL2 guidance). Compact checklist output, plain in non-TTY.
- AC: unit tests cover each check via PATH stubbing; checklist renders with and without TTY.

## Epic 2: Interactive install

### Story 2.1: Target-directory classifier

- `installer/src/classify.js`: classify target as `empty` | `existing-project` (signals: `.git`, `package.json`, `pyproject.toml`, `*.sln`, etc.) | `existing-install` (`.ralph/manifest.json` present).
- AC: unit tests with fixture directories for all three classes plus an ambiguous case.

### Story 2.2: Wizard flow building the InstallPlan

- **[SM: split if needed]**
- `installer/src/wizard.js` with `@clack/prompts`: intro explainer → target confirmation → project facts (app dir, checkpoint command, stack description) → loop knobs (defaulted) → task source → extras (`.gitignore`, npm script) → summary. Output is an in-memory InstallPlan; **no writes**. Ctrl-C anywhere → "nothing was changed" exit.
- AC: Enter-only run yields a complete InstallPlan with documented defaults; cancellation test confirms zero filesystem effects.

### Story 2.3: Write engine, conflict handling, and manifest

- **[SM: split if needed]**
- `installer/src/writer.js`: render templates (substitute checkpoint command and stack description into `project-conventions.md` and stubs), detect conflicts (default-deny, per-file confirm, `--force` override), execute the InstallPlan only after confirmation, write `.ralph/manifest.json` (version, checksums, ownership class per FR-6, wizard answers).
- AC: unit tests for rendering, conflict default-deny, and manifest contents; installed epic stub parses under `### Story X.Y: Title` rules.

### Story 2.4: BMAD install step

- `installer/src/bmad.js`: run `npx bmad-method install --modules core,bmm --tools claude-code --output-folder docs` (+ artifact path flags) non-interactively under a spinner; skippable; on failure print the exact manual command and continue non-fatally.
- AC: unit test with a stubbed `npx` verifies the exact argv; failure path prints the manual command and exits 0 for the step.

### Story 2.5: Post-install outro, GETTING-STARTED, and doctor

- Generate `GETTING-STARTED.md` (start/stop/watch the loop, where memory lives, how to update); outro with numbered next steps; `doctor` subcommand validating files, manifest checksums, jq/claude presence, and epic-header parseability (FR-10).
- AC: `doctor` exits 0 on a fresh install fixture and non-zero with a named failure when a required file is deleted.

## Epic 3: Automation and lifecycle

### Story 3.1: Non-interactive mode

- `--yes`, a flag per wizard question, `--list-options`, `--force`; conflicts without `--force` fail fast non-zero; non-TTY output plain (no spinners/ANSI); `NO_COLOR` respected.
- AC: E2E fixture run via `--yes` into an empty dir passes `doctor`; piped output contains no ANSI escapes; conflict-without-`--force` exits non-zero without prompting.

### Story 3.2: Update flow

- **[SM: split if needed]**
- Manifest detection → "installed vX → available vY" → replace installer-owned files only; locally modified installer-owned file → keep / take new / backup-and-take; user-owned files never touched (FR-8).
- AC: PRD success criterion 3 reproduced as an automated E2E: user-modified `docs/prd.md` and `project-conventions.md` survive an update byte-identically.

### Story 3.3: Uninstall

- Remove installer-owned files per manifest, list user-owned files left behind, confirm before removing those too; `--yes`/`--force` semantics consistent with install.
- AC: E2E shows installer-owned files gone, user-owned preserved, and an empty `.ralph/` removed.

## Epic 4: Polish and release

### Story 4.1: E2E suite

- Bash-driven fixtures (empty dir, existing project) running install → doctor → update → uninstall through the non-interactive mode, wired into `cd installer && npm test`.
- AC: suite passes locally; each PRD success criterion 1–5 maps to at least one assertion.

### Story 4.2: Documentation rewrite

- Repo `README.md`: BMAD-shaped quick start (prerequisites, one command, link to deeper docs); "Adapting this to your project" updated to lead with the installer; `TIMELINE.md` `[System]` entry for the chapter.
- AC: README quick start contains the single install command; old manual steps preserved under a "manual install" fallback section.

### Story 4.3: Release preparation

- Resolve the package name (`@seevali/ralph-loop` vs `ralph-loop-installer` — both verified candidates; recheck availability), finalize `package.json` metadata, `npm pack` dry-run < 1 MB unpacked, cold-start checklist for the manual publish.
- AC: `npm pack` succeeds within the size budget; a PUBLISHING.md checklist exists; no `npm publish` is executed by the loop.
