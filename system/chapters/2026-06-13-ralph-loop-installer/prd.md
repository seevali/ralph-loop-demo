# PRD: Ralph Loop Guided Installer

**Chapter:** [2026-06-13-ralph-loop-installer](README.md)
**Date:** 2026-06-13
**Status:** accepted, ready for loop execution
**Supersedes:** [artifacts/prd-draft-2026-06-12.md](artifacts/prd-draft-2026-06-12.md) (drafted without repo access; reconciled in the [chapter plan](README.md))

---

## Background

Installing the Ralph Loop into a new project is currently manual: clone this repo, hand-copy `scripts/ralph-loop.sh` and `scripts/prompts/`, write a PRD and epic stubs in the strict `### Story X.Y: Title` format, customize prompt files for the target stack, install BMAD with the correct non-interactive flags, and add `.gitignore` entries — about an hour of careful README-following. The BMAD Method solved this exact problem with `npx bmad-method install`; no public Ralph implementation has an equivalent (prior-art summary below). This chapter builds one.

## Goal

A developer runs `npx <package> install` in an empty directory or an existing project and has a working, customized Ralph Loop — including BMAD — in under 5 minutes, with the wizard teaching the concepts as it goes. Re-running the command updates an existing install without touching user files. A fully non-interactive mode serves scripts and CI.

## Users

- **P1 — Early AI adopter (primary).** Has used Claude Code, never run an agent loop. Needs defaults, explanations, safety. Success: loop running on a starter task in ≤ 5 min without reading the README.
- **P2 — Experienced agentic developer.** Wants speed: Enter through defaults or skip the wizard with flags. Success: installed and customized in under a minute.
- **P3 — Automation user.** Needs one deterministic non-interactive command, exit code 0, no prompts.

## Approach

A Node.js CLI (`@clack/prompts` + Commander + `picocolors`, Node ≥ 20, < 1 MB unpacked) living in a new top-level `installer/` directory and published to npm. Canonical loop files (`scripts/ralph-loop.sh`, `scripts/prompts/**`) are copied into the package by a bash sync script with a `--check` drift gate — the loop itself is never modified. The installed footprint mirrors this repo's layout, so all existing documentation applies to installed projects. Full design in the [chapter plan](README.md#design).

## Functional requirements

**FR-1 Entry points.** `npx <package> install` (alias `init`) handles first install and update. `uninstall` and `doctor` subcommands. `--version` / `--help` exit cleanly.

**FR-2 Preflight.** Check Node ≥ 20 (hard fail with guidance), git (warn + confirm), `jq` (warn + per-OS install command), `claude` CLI (warn, never block), bash environment (native Windows without bash → honest stop with WSL2 guidance). Results shown as a compact checklist.

**FR-3 Target intelligence.** Default target = cwd; `--directory` overrides. Classify as empty (offer `git init` + skeleton), existing project (summarize detected signals; additive changes only, each confirmed), or existing Ralph install (switch to update mode). Never overwrite any file without per-file confirmation or `--force`; default-deny.

**FR-4 Wizard.** clack-styled flow: intro explainer → preflight → target confirmation → project facts (app dir, checkpoint command, stack description rendered into `project-conventions.md`) → loop knobs (all defaulted) → task source (scaffold commented PRD/epic stubs or point at existing) → BMAD step → summary → confirm → write → outro. Every prompt has a default (Enter-Enter-Enter works); Ctrl-C anywhere exits with zero writes.

**FR-5 BMAD orchestration.** Run `npx bmad-method install --modules core,bmm --tools claude-code --output-folder docs ...` non-interactively under a spinner. Skippable; on failure, print the exact manual command and continue (non-fatal).

**FR-6 Installed footprint.** `scripts/ralph-loop.sh` + `scripts/prompts/` (installer-owned), `docs/prd.md` + `docs/epics/` stubs with teaching comments (user-owned), `CLAUDE.md` (only if absent), `GETTING-STARTED.md`, `.gitignore` entries (`_bmad/`, `.claude/skills/`, `scripts/logs/`), and `.ralph/manifest.json` recording version, per-file checksums, ownership class, and wizard answers.

**FR-7 Non-interactive mode.** `--yes` accepts defaults; every wizard question has a flag; `--list-options` prints them; conflicts without `--force` fail fast non-zero; non-TTY output is plain lines (no spinners/ANSI); `NO_COLOR` respected.

**FR-8 Update.** Re-run detects manifest, shows installed → available version, replaces installer-owned files only. Locally modified installer-owned file → keep mine / take new / back up mine and take new. User-owned files are never touched.

**FR-9 Uninstall.** Removes installer-owned files, lists user-owned files left behind, asks before removing those too.

**FR-10 Doctor.** Validates an install: expected files present, manifest checksums consistent, agent CLI and jq found, epic story headers parseable. Pass/fail checklist, non-zero exit on failure.

## Non-functional requirements

- **Performance:** wizard visible < 3 s on warm npx cache; default install (excluding the BMAD download) < 60 s.
- **Safety/idempotency:** no writes before final confirmation; install twice is safe; cancellation leaves nothing behind.
- **Error quality:** every failure states what, why, and one next step; stack traces only behind `--debug`.
- **Testability:** core logic separated from the prompt layer; `node:test` units + bash E2E fixtures; non-interactive mode doubles as the E2E harness.
- **No telemetry.** No network calls beyond npm and the user-confirmed BMAD step.

## Constraints

- Node.js is permitted **only** inside `installer/` (rule amendment in Story 1.1); everything else stays Bash + Markdown.
- Demo Track (`docs/`, `src/`) and the loop's safety contract are untouched. Canonical loop files are read-only inputs to the sync script.
- Self-contained repo: no references outside it; the npm package builds solely from `installer/`.
- Dependencies limited to `@clack/prompts`, `commander`, `picocolors`.
- The loop supports **Claude Code only** — no agent-selection step.
- Dogfooding: this chapter is executed by the loop itself, so every story must be independently verifiable.

## Prior art (summary)

`PageAI-Pro/ralph-loop` (command-based install, Docker-reliant, no wizard); `snarktank/ralph` (manual file copy, no installer); `frankbria/ralph-claude-code` (global command, no per-project scaffold); `syuya2036/ralph-loop` (agent-agnostic shell script, manual). The npm names `ralph-loop` and `create-ralph-loop` are taken by third parties (verified 2026-06-13); naming candidates are `@seevali/ralph-loop` and `ralph-loop-installer`, decided in Story 4.3. Benchmark UX: `npx bmad-method install`, `npm create astro@latest`.

## Out of scope

Loop runtime changes; multi-agent support; global `ralph` command; GUI/web installer; Docker provisioning; release channels beyond `latest`; PowerShell loop runner; telemetry; the actual `npm publish` (prepared in Story 4.3, executed by a human).

## Success criteria

1. **Empty-dir E2E:** non-interactive install into an empty dir, then `doctor`, exits 0; the installed project contains every FR-6 file and the epic stub parses under the loop's strict story-header rules.
2. **Enter-only path:** the interactive wizard completed with only Enter presses produces a working install (verified by `doctor`).
3. **Update safety:** modify the user's `docs/prd.md` and `scripts/prompts/common/project-conventions.md`, re-run install → update completes and a checksum sweep shows zero user-owned files changed.
4. **Sync gate:** `installer/scripts/sync-templates.sh --check` passes at every story's review; mutating `scripts/ralph-loop.sh` in a sandbox makes it fail.
5. **Non-TTY:** piping install output to a file yields no ANSI codes; a conflicting install without `--force` exits non-zero without hanging.
6. **Cold start:** `npm pack` tarball is < 1 MB unpacked and `npx` against it on a clean machine reaches the wizard in < 3 s (manual pre-release check).
