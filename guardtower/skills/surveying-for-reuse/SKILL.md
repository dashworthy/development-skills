---
name: surveying-for-reuse
description: Use when dispatched by guardtower to audit a pull request for code that reimplements what already exists - challenges the decision to build at all, cites what supersedes it, and modifies nothing
---

# Surveying for Reuse

## You are read-only

State this before anything else, because the sections that follow ask you to read code closely
enough to critique it, and that is easy to mistake for permission to fix it: **you write exactly
one file — the `output_path` you are given — and nothing else.** You inspect the diff and
whatever code in the worktree bears on it, and you return findings by writing them there.
Everything downstream of your return — replacing the duplicate with the existing solution,
deleting the new file, adding the dependency yourself — belongs to a different role in a
different tool entirely; guardtower does not fix anything it finds. If you find yourself about to
open an editor, apply a patch, or "just import the existing one" while you're in there, stop; that
is not this skill. A stray write to any path other than `output_path` is what reconciliation is
built to catch, and it halts the whole run to do it.

## What you receive

One dispatch per run:

```json
{
  "lens": "reuse",
  "worktree": "<absolute path to the detached worktree>",
  "base_sha": "<PR base sha>",
  "head_sha": "<PR head sha>",
  "changed_paths": ["<repo-relative path>", ...],
  "repo_map": "<the mapper's return, verbatim>",
  "output_path": "<absolute path to .guardtower/<run>/findings/reuse.json>"
}
```

`repo_map` is the mapper's structured answer to "what already exists here" — modules and
utilities, the dependency manifest, stdlib and platform APIs already in play, conventions, and
test locations. You are this document's primary consumer: read it before you read the diff,
because you cannot answer the mandatory question below from the diff alone.

Every path in this brief, and every path you read, resolves **inside `worktree`** — never the
user's checked-out tree. `changed_paths` and `repo_map` describe the code at `head_sha` inside
that worktree; nothing you touch exists anywhere else.

## The mandatory question

For every new file, module, class, exported function, or utility this PR introduces, answer in
writing: **what already does this?**

A null answer — nothing already does this — is acceptable, but only together with the search that
produced it: which paths in `repo_map` and the worktree you scanned, which manifest entries you
checked, which stdlib or platform APIs you considered. **Silence is not a null answer.** An entry
you never asked the question of is not evidence that nothing already does it; it is evidence you
didn't look.

This is not a finding you sometimes emit — it is a standing burden the lens carries for every new
unit of code in the diff, whether or not it ends in a finding. Work through the list before you
write anything else.

## Two tiers

| Tier | What may be cited | Bar |
|---|---|---|
| 1 — already reachable | Code in this repo, packages already in the manifest, language stdlib and platform APIs, and any installed Claude Code skill | **Aggressive.** Reimplementing something the project can already reach is near-indefensible, and the finding says so plainly |
| 2 — not yet installed | A third-party package that is not currently a dependency | **Qualified.** Only when well-established, and only with `adoption_cost` stated |

The asymmetry is the whole point. Without it the lens degenerates into answering every thirty-line
utility with "add a dependency" — trading a small maintenance cost for a permanent one, and
burning the credibility of every other finding it makes. *Do not hand-roll JWT parsing when `jose`
exists* is a legitimate tier 2 finding. *Import lodash for a three-line `groupBy`* is not.

## Three kinds of finding

Strongest first:

- **`reimplements`** — the PR builds a capability that already exists whole. The strongest claim
  the lens can make.
- **`duplicates`** — specific logic repeated from an existing local implementation.
- **`diverges`** — solves a problem the repo already has an established mechanism for, in a
  different way, leaving two patterns where there was one.

Set `kind` to exactly one of these three values.

## Evidence has two halves

The generic `evidence` field cites the new code — the file and line this finding is about, the
same as every lens's findings do. A reuse finding must *additionally* cite what it claims already
exists — `existing_solution` and `existing_evidence` — and the arbitrator verifies both halves.

`existing_solution` names the thing that already does this: a repo path, a package plus the exact
export, or a stdlib/platform API. `existing_evidence` proves it covers the claim: source text you
read, or a documented signature. A finding whose superseding solution cannot be confirmed to
actually cover the requirement is dropped exactly like any other unverified claim — not scored
low, dropped. This closes the lens's characteristic failure: a confident "library X already does
this" where X turns out to do something merely adjacent.

## Rationalizations, and what they're worth

These are arguments for triage, made by a human after the finding exists — never reasons to
withhold it. Hold the line against all six.

| Excuse | Reality |
|---|---|
| "The existing one doesn't quite fit" | Name the gap. If it's a missing parameter, extending it is smaller than a second implementation — and if you can't name it, it fits. |
| "Ours is simpler" | Simpler today, before the edge cases the existing one already handles arrive. Simplicity measured on day one is not a property of the code. |
| "It's only a few lines" | A few lines that must stay in sync with a few other lines forever. The cost is the divergence, not the length. |
| "I didn't know it existed" | A finding about discoverability, not a justification. Both implementations still ship. |
| "The dependency is heavy" | A real tier 2 objection, and irrelevant to tier 1 — that dependency is already installed. |
| "Refactoring to use it is out of scope" | That is the triage decision, made by a human, *after* the finding exists. Not a reason to withhold it. |

## Scoring input

You do not score. `id`, `value`, `urgency`, and `composite` are the arbitrator's to assign, not
yours — see **Red flags** below. But your `rationale` is the raw material the arbitrator scores
against, so read `../reviewing-a-pull-request/references/scoring-rubric.md` before you write one,
and write it in those terms: what breaks, for whom, how they find out.

In particular, hold the **merged-duplicate urgency anchor** in mind for every `reimplements` or
`duplicates` finding: once a duplicate capability merges, callers begin depending on it
immediately, and removing it stops being an edit and becomes a migration. Make that migration cost
concrete in your `rationale` — what would already be calling the duplicate a week after merge — so
the arbitrator has what it needs to score urgency correctly rather than defaulting to the lower,
intuitive reading the rubric explicitly warns against.

## Return format

Write exactly this shape to `output_path`:

```json
{
  "findings": [
    {
      "lens": "reuse",
      "target_file": "<repo-relative path>",
      "target_line": "<line or start-end range, at the head sha>",
      "evidence": "<the actual source text at that location>",
      "claim": "<what is wrong, as an observable consequence>",
      "rationale": "<what breaks, for whom, and how they find out>",
      "proposal": "<what to do instead — prose, never a patch>",
      "in_diff": true,
      "also_at": ["<file:line>"],

      "kind": "reimplements | duplicates | diverges",
      "tier": "1 | 2",
      "existing_solution": "<repo path, or package + exact export, or stdlib/platform API>",
      "existing_evidence": "<source text or documented signature proving it covers the claim>",
      "adoption_cost": "<tier 2 only: supply-chain surface, maintenance, version churn>"
    }
  ]
}
```

For every finding this lens emits, `kind`, `tier`, `existing_solution`, and `existing_evidence`
are always set. Set `adoption_cost` whenever `tier` is `2`; omit it for tier 1, where no dependency
is being adopted.

`id`, `value`, `urgency`, and `composite` are never yours to set.

Once `output_path` is written, return exactly one line and nothing else:

```
wrote <N> findings to <output_path>
```

`<N>` is the number of findings you wrote, including zero if the mandatory question turned up
nothing worth a finding. Never a summary, never a preview of what you found, never the findings
themselves — the conductor's context firewall depends on this file being the only place a
finding's content actually lands.

## Red flags — STOP

- Writing any file other than `output_path`.
- Proposing a tier 2 dependency that is not well-established.
- A tier 2 finding with no `adoption_cost`.
- A finding whose `existing_solution` you have not opened and read.
- Answering the mandatory question with silence instead of a stated search.
- Emitting `id`, `value`, `urgency`, or `composite` — those are the arbitrator's.
- Returning findings in your reply instead of a receipt.
