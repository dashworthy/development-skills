---
name: simplifying-through-abstraction
description: Use when dispatched by guardtower to audit a pull request for structural complexity a higher-level pattern would tame - reports only abstractions justified by repetition that already exists, and modifies nothing
---

# Simplifying Through Abstraction

## You are read-only

State this before anything else, because the sections that follow ask you to read code closely
enough to critique it, and that is easy to mistake for permission to fix it: **you write exactly
one file — the `output_path` you are given — and nothing else.** You inspect the diff and
whatever code in the worktree bears on it, and you return findings by writing them there.
Everything downstream of your return — extracting the shared function, introducing the state
machine, collapsing the branches into a table — belongs to a different role in a different tool
entirely; guardtower does not fix anything it finds. If you find yourself about to open an editor,
apply a patch, or "just factor this out while you're in there," stop; that is not this skill. A
stray write to any path other than `output_path` is what reconciliation is built to catch, and it
halts the whole run to do it.

## What you receive

One dispatch per run:

```json
{
  "lens": "abstraction",
  "worktree": "<absolute path to the detached worktree>",
  "base_sha": "<PR base sha>",
  "head_sha": "<PR head sha>",
  "changed_paths": ["<repo-relative path>", ...],
  "repo_map": "<the mapper's return, verbatim>",
  "output_path": "<absolute path to .guardtower/<run>/findings/abstraction.json>"
}
```

`repo_map` is the mapper's structured answer to "what already exists here" — modules and
utilities, the dependency manifest, stdlib and platform APIs already in play, conventions, and
test locations. Read it to locate occurrences of a pattern elsewhere in the repo that this diff's
new code joins — a finding here often rests on occurrences outside the diff itself, per
**Multi-file findings** below. It does not replace reading the diff: the occurrence count in
**Abstraction is earned, never anticipated** is answered from the diff and the code it touches,
not from `repo_map` alone.

Every path in this brief, and every path you read, resolves **inside `worktree`** — never the
user's checked-out tree. `changed_paths` and `repo_map` describe the code at `head_sha` inside
that worktree; nothing you touch exists anywhere else.

## Abstraction is earned, never anticipated

This is the defining rule of the lens, and the reason it is the easiest of the four to get wrong
in the expensive direction: proposing structure the code does not yet need. Propose an
abstraction only where the repetition or branching it would collapse **already exists in the
code**, and say how many occurrences and where. *Two occurrences is a coincidence; three is a
pattern.* An abstraction proposed for a case that has not happened yet is speculative, and
speculative abstraction costs more than the duplication it prevents.

## What to look for

Each of these earns a finding only when the pattern it names is already present, per the rule
above — never for a shape you can merely imagine the code growing into:

- **Sprawling hard-coded branching** — an `if`/`elif` or `switch` chain that keeps growing as new
  cases arrive → a table or strategy map, so a new case adds a row instead of a new branch.
- **A duplicated conditional ladder appearing in several places** — the same sequence of checks,
  copied at each call site → one policy object the call sites share, so a change to the ladder
  happens once instead of at every copy.
- **Ad-hoc sequencing and orchestration** — steps that call each other directly, with the order
  and branching implicit in the call graph → an explicit pipeline, so the order is read from one
  place instead of traced through calls.
- **Scattered state transitions with no single place to read the machine** — a status mutated
  from several call sites with no shared record of which transitions are legal → a state machine,
  so the legal transitions live in one place a reader can check.
- **Repeated try/retry/backoff ladders** — the same retry loop, rebuilt with slightly different
  constants at each call site → one retry policy, so a change to backoff behavior happens once.
- **Parallel `switch` statements over the same enum in different files** — a case added to the
  enum means finding and updating every switch already written over it → polymorphism or one
  dispatch table, so a new case is added in one place instead of hunted down across files.

## Say what it costs

Every abstraction adds indirection, and indirection has a reader cost: one more file to open, one
more layer between the call site and the behavior it triggers. **Each finding's `proposal` must
state what the reader gains against what the indirection costs. A finding that only names the
gain is incomplete.**

## Multi-file findings

These usually span several files. Put the clearest occurrence in `target_file`/`target_line` and
every other in `also_at`. Expect `in_diff` to be `false` often, which routes the finding to the
summary comment rather than an inline one; that is correct, not a failure.

## Scope is the diff

The repetition or branching a finding proposes to collapse must be introduced or extended by this
PR. Pre-existing repetition the diff did not touch is not this PR's finding, even when it turns up
a pattern that has clearly been begging for this abstraction for months — that is a real
observation, but it belongs to whichever PR actually touches it, not this one.

## Scoring input

You do not score. `id`, `value`, `urgency`, and `composite` are the arbitrator's to assign, not
yours — see **Red flags** below. But your `rationale` is the raw material the arbitrator scores
against, so read `../reviewing-a-pull-request/references/scoring-rubric.md` before you write one,
and write it in those terms: what breaks, for whom, how they find out.

## Return format

Write exactly this shape to `output_path`:

```json
{
  "findings": [
    {
      "lens": "abstraction",
      "target_file": "<repo-relative path>",
      "target_line": "<line or start-end range, at the head sha>",
      "evidence": "<the actual source text at that location>",
      "claim": "<what is wrong, as an observable consequence>",
      "rationale": "<what breaks, for whom, and how they find out>",
      "proposal": "<what to do instead — prose, never a patch>",
      "in_diff": true,
      "also_at": ["<file:line>"]
    }
  ]
}
```

This lens sets no reuse-only fields — never `kind`, `tier`, `existing_solution`,
`existing_evidence`, or `adoption_cost`; those belong to `surveying-for-reuse` alone. `id`,
`value`, `urgency`, and `composite` are never yours to set either.

Once `output_path` is written, return exactly one line and nothing else:

```
wrote <N> findings to <output_path>
```

`<N>` is the number of findings you wrote, including zero if nothing in the diff earns an
abstraction under the rule above. Never a summary, never a preview of what you found, never the
findings themselves — the conductor's context firewall depends on this file being the only place a
finding's content actually lands.

## Red flags — STOP

- Proposing an abstraction for repetition that does not yet exist.
- Proposing one without stating its indirection cost.
- Counting two occurrences as a pattern.
- Reporting pre-existing repetition the diff did not touch.
- Writing any file other than `output_path`.
- Emitting `id`, `value`, `urgency`, or `composite` — those are the arbitrator's.
- Returning findings instead of a receipt.
