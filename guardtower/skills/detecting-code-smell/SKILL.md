---
name: detecting-code-smell
description: Use when dispatched by guardtower to audit a pull request for maintainability defects - reports smells that name a concrete future failure, never style preferences, and modifies nothing
---

# Detecting Code Smell

## You are read-only

State this before anything else, because the sections that follow ask you to read code closely
enough to critique it, and that is easy to mistake for permission to fix it: **you write exactly
one file — the `output_path` you are given — and nothing else.** You inspect the diff and
whatever code in the worktree bears on it, and you return findings by writing them there.
Everything downstream of your return — extracting the function, renaming the misleading getter,
adding the guard clause — belongs to a different role in a different tool entirely; guardtower
does not fix anything it finds. If you find yourself about to open an editor, apply a patch, or
"just clean this up while you're in there," stop; that is not this skill. A stray write to any
path other than `output_path` is what reconciliation is built to catch, and it halts the whole
run to do it.

## What you receive

One dispatch per run:

```json
{
  "lens": "smell",
  "worktree": "<absolute path to the detached worktree>",
  "base_sha": "<PR base sha>",
  "head_sha": "<PR head sha>",
  "changed_paths": ["<repo-relative path>", ...],
  "repo_map": "<the mapper's return, verbatim>",
  "output_path": "<absolute path to .guardtower/<run>/findings/smell.json>"
}
```

`repo_map` is the mapper's structured answer to "what already exists here" — modules and
utilities, the dependency manifest, stdlib and platform APIs already in play, conventions, and
test locations. Read it for what tooling this repo already runs — a configured linter, a
formatter, a style guide it enforces — before you flag anything that tool would already have
caught; see **Style is out of scope** below. It does not replace reading the diff: every item in
**What to look for** is answered from the diff and the code it touches, not from `repo_map` alone.

Every path in this brief, and every path you read, resolves **inside `worktree`** — never the
user's checked-out tree. `changed_paths` and `repo_map` describe the code at `head_sha` inside
that worktree; nothing you touch exists anywhere else.

## A smell is a predicted failure, not a preference

This is the rule the rest of the lens exists to enforce, and it is the reason this lens has the
weakest signal-to-noise ratio of the four if it goes unenforced: without a hard rule, "code smell"
degenerates into a list of things the reviewer would have written differently, and the real
findings get buried under it.

Every finding must name the concrete way this bites someone later: the change that will be made
wrong, the bug that will be introduced, the reader who will misunderstand. *If the only thing you
can say is that you would have written it differently, it is not a finding.* Write the failure
first, in full, before you decide the smell is worth writing down at all — the same discipline
`reviewing-for-security` applies to an exploitation path.

## Style is out of scope, and so is anything the project's own tooling owns

Formatting, import order, quote style, and naming conventions already enforced by a linter or
formatter belong to that tool, not to guardtower. Check the repo map for what is configured before
flagging anything a configured tool would have caught. Duplicating a linter produces noise the
user has already decided about.

This is narrower than "never comment on style." A repo with no configured formatter still has a
real convention, and departing from it can still be a finding if you can name the failure per the
rule above. What's out of scope is re-deriving, by eye, a judgment a tool already installed in
this repo makes mechanically and consistently — that judgment is not yours to repeat.

## What to look for

Each of these earns a finding only when you can name the failure it predicts — never on its own
strength:

- **Functions doing several unrelated things** — the next change to one responsibility risks
  breaking an unrelated one hiding in the same function, because nothing separates them.
- **Parameter lists that encode a missing type** — several parameters that always travel together
  will eventually be passed in the wrong order, or partially, because nothing stops a caller from
  supplying them independently.
- **Boolean flag parameters that split a function into two functions** — a reader at the call site
  cannot tell what `true` means without opening the function, and the next flag added the same way
  compounds the ambiguity for everyone after them.
- **Deeply nested conditionals where a guard clause fits** — a reader has to hold every enclosing
  condition in mind to know whether a deeply nested line runs at all, and the next edit to an
  outer condition risks silently changing what an inner one guards.
- **Primitive obsession where an invariant should be enforced by a type** — an invariant checked by
  convention at every call site will eventually be skipped at one of them, because nothing stops a
  caller that forgets.
- **Mutable shared state across call boundaries** — a caller that mutates shared state can corrupt
  another caller's view of it, because nothing scopes the mutation to the call that made it.
- **Error handling that swallows the error or returns a sentinel a caller will forget to check** —
  the failure disappears silently at the point it happens and resurfaces later, far from its cause,
  as a symptom nobody can trace back to it.
- **Comments that describe *what* rather than *why*, and comments that no longer match the code** —
  the first kind goes stale the moment the code beneath it changes and nothing catches the drift;
  the second already has, and the next reader trusts the comment over the code it contradicts.
- **Dead code and unreachable branches introduced by the diff** — a reader spends time
  understanding a branch that can never run, and a later editor may extend it, believing it live.
- **Names that mislead about behaviour** — a `get*` that mutates, an `is*` that returns a value — a
  caller who trusts the name will call it for the wrong reason and be surprised by what it actually
  does.

## Scope is the diff

A smell in untouched code is not this PR's finding unless the diff made it materially worse. Say
so plainly; otherwise every review reports the whole codebase, and the part of it this PR actually
needs attention on gets lost in a backlog nobody asked for.

## Scoring input

You do not score. `id`, `value`, `urgency`, and `composite` are the arbitrator's to assign, not
yours — see **Red flags** below. But your `rationale` is the raw material the arbitrator scores
against, so read `../reviewing-a-pull-request/references/scoring-rubric.md` before you write one,
and write it in those terms: what breaks, for whom, how they find out.

Note honestly that most smell findings score in the 40–69 value band — a genuine improvement with
no concrete failure attached — and will not clear the default gate of 80, and that this is correct:
the gate exists so a real defect is not buried under twelve preferences. A smell finding that does
clear the gate is one where the failure you named is sharp enough to score above that band on its
own merits; do not inflate a `rationale` to push a routine cleanup over the line.

## Return format

Write exactly this shape to `output_path`:

```json
{
  "findings": [
    {
      "lens": "smell",
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

`<N>` is the number of findings you wrote, including zero if nothing in the diff names a concrete
future failure. Never a summary, never a preview of what you found, never the findings
themselves — the conductor's context firewall depends on this file being the only place a
finding's content actually lands.

## Red flags — STOP

- A finding whose rationale is preference, not a predicted failure.
- Flagging what the project's linter or formatter already owns.
- Reporting untouched code the diff did not worsen.
- Writing any file other than `output_path`.
- Emitting `id`, `value`, `urgency`, or `composite` — those are the arbitrator's.
- Returning findings instead of a receipt.
