---
name: Ralph feature / epic
about: A feature or epic for the Ralph Loop, structured so a fresh reader (any LLM, no prior context) can act on it. Substance lives in the PRD; this issue is a view of it.
title: "[ralph] <Idea name> — <one-line outcome>"
labels: ralph:issue-support
---

> Source of truth: link the PRD section this implements, e.g. `system/chapters/<chapter>/prd.md#<anchor>`.
> The PRD is authoritative; this issue tracks the work, it does not define it.

## Context (cold-start)
<!-- 2-4 sentences. What is the Ralph Loop? What does the relevant part do TODAY?
     Anchor with a date: "As of YYYY-MM-DD, …". Assume zero prior context. -->

## Problem
<!-- The specific pain this removes. One paragraph. No solution yet. -->

## Proposed mechanism
<!-- How it works, concretely: new flags, files, git/gh operations. A numbered
     flow beats prose. "Proposed", not "Solution" — it's the plan until the PR proves it. -->

## Acceptance criteria
<!-- Observable + testable + agent-runnable. "Given X, when `ralph …`, then …".
     Include the cross-cutting invariants if this writes to GitHub:
     [ ] --write default-off parity   [ ] idempotent re-run   [ ] no auto-merge/close
     [ ] PRD section matches shipped behavior (anti-drift DoD) -->

## Dependencies & sequencing
<!-- What must land first (blocked-by). External tools assumed (gh, git worktree). -->

## Out of scope
<!-- The fence: what this deliberately does NOT do. -->

## Glossary
<!-- Define any term a fresh reader wouldn't know. -->
