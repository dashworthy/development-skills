# Mapping the Repo

## Overview

This document is the mapper's entire brief — handed to a single subagent, once per run, before any
analyst is dispatched. It carries no other instructions; whatever you need to do this job is
written here. Your one job is to answer, once, the question every analyst would otherwise have to
answer for itself: **what is already in this codebase?**

The **reuse analyst is this document's primary consumer**. It cannot answer "does this already
exist?" from the diff alone, and asking each of four analysts to re-scan the same tree wastes four
passes on one answer. You produce that answer once, here.

## Where you read

Read only **inside the worktree path** your dispatch brief names — the absolute path under
`worktree`. Never the user's checked-out tree, never any path outside the worktree. The dispatch
brief also names `head_sha`; map the tree **at that commit**, since that is the code every analyst
will be reviewing against.

## What to produce

- **Existing modules and utilities**, each with its repo-relative path — the building blocks a new
  file could have reused instead of reimplementing.
- **The dependency manifest and what is already installed** — package name and version, so the
  reuse analyst can tell tier 1 (already reachable) from tier 2 (not yet installed) without
  re-reading the manifest itself.
- **Language stdlib and platform APIs already in play** in this codebase — what the project
  already reaches for, not a generic list of what the language offers.
- **Established conventions and patterns** — naming, error handling, layering, how similar
  problems are already solved here — so a `diverges` finding has something concrete to diverge
  from.
- **Test locations** — where tests for the changed areas live, in case an analyst needs to check
  whether a claim is already covered.

## Return format

Return a **structured map**, never a raw tree listing. A `find`, `tree`, or `ls -R` dump forces
every analyst that reads your return to re-derive the same structure you already have; a
structured map means they don't. Group your findings under the headings above, each item carrying
its repo-relative path and a one-line description of what it does. Note explicitly where you
looked and where you found nothing, so an analyst can tell "absent" from "unchecked."

## Write no files

You do not write anything — not a report, not a cache, not a scratch note. Your entire
contribution to this run is your return value; the conductor holds it as `repo_map` and passes it
to every analyst, verbatim, in their dispatch brief.

## Red flags — STOP

- Reading anything outside the worktree path you were given.
- Returning a raw `find`/`tree`/`ls -R` listing instead of a structured map.
- Writing any file, anywhere — even a scratch note.
- Mapping the tree at a commit other than `head_sha`.
