# System Track

This folder is where the **Ralph Loop is improved using itself**. It's separate from the demo track (everything at the repo root) on purpose — the demo is a frozen showcase of the loop in action; this is where the tool actually evolves.

**If you just cloned this repo to try the demo, you don't need anything in here.** Run [`scripts/ralph-loop.sh`](../scripts/ralph-loop.sh) from the repo root and watch the Exchange Rates Dashboard get built. Come back here only if you're curious how the loop itself was developed.

## What lives here

```
system/
├── README.md                  # this file
├── CLAUDE.md                  # agent guidance specific to system-track loop runs
├── ralph-loop-system.sh       # wrapper that points the canonical loop at a chapter
└── chapters/                  # one folder per improvement effort
    └── YYYY-MM-DD-slug/
        ├── README.md          # the plan (renders on GitHub when folder is opened)
        ├── prd.md             # PRD that drives the loop for this chapter
        ├── epics/             # epic(s) derived from the plan
        ├── stories/           # populated by the loop's SM agent during runs
        └── artifacts/         # optional — diagrams, research, test outputs
```

## How a chapter works

Each chapter is a self-contained improvement to the loop infrastructure. The folder shape mirrors the demo track's root layout (`prd.md`, `epics/`, `stories/`) so the convention is learnable once: anything you understand about the demo applies one level down inside a chapter.

A chapter goes through this lifecycle:

1. **Plan** — drafted (often by a planning agent), reviewed, accepted. The plan is the chapter's `README.md` so it renders on GitHub.
2. **PRD + Epic** — the plan is operationalized into a PRD that the loop can consume and one or more epics with story-level acceptance criteria.
3. **Loop execution** — `./system/ralph-loop-system.sh <chapter>` (or just `./system/ralph-loop-system.sh` for the most recent chapter) drives BMAD agents through the stories.
4. **Stories land** — Dev agent commits each story; Code Reviewer agent gates each pass. Story files in `stories/` are written by the SM agent at run time.
5. **Chapter closes** — when all stories are merged, the chapter's plan status is updated to `complete` in its `README.md`.

## Running a chapter

```bash
# Run the most recent chapter
./system/ralph-loop-system.sh

# Run a specific chapter
./system/ralph-loop-system.sh 2026-05-24-modularize-loop-prompts

# Pass loop flags through (after the chapter name, or after --)
./system/ralph-loop-system.sh 2026-05-24-modularize-loop-prompts -- --stories 1.1 --max-budget-usd 2

# List available chapters
./system/ralph-loop-system.sh --help
```

The wrapper is a thin shim that resolves the chapter's PRD and epic paths and delegates to [`scripts/ralph-loop.sh`](../scripts/ralph-loop.sh) (the canonical loop). The work surface is the whole repo — System Track agents may modify any file *except* the Demo Track artifacts (`docs/`, `src/`) and the safety contract sections of `scripts/ralph-loop.sh` (multi-model routing, retry, budget caps).

See [`CLAUDE.md`](CLAUDE.md) for the agent behavior rules that apply inside System Track loop runs.

## Why this is separate from the demo track

Two reasons:

1. **Independence.** Each track has its own PRD, epics, and stories. Neither track sees the other's work artifacts. Both use the same loop engine — that's a feature, not a coincidence: it makes the recursion (the loop improving itself) part of the demo's value.
2. **Visibility.** Branching the system work off would hide it from the public-facing repo. Keeping it in `system/` on the same branch as the demo means anyone visiting the repo sees both the result (the dashboard at `src/`) and the path that got us here (chapters in `system/chapters/`). The TIMELINE at the repo root narrates both.
