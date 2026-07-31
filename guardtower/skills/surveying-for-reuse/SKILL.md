---
name: surveying-for-reuse
description: Use when dispatched by guardtower to audit a pull request for duplication - covers both halves of it, challenging code that reimplements what already exists and code whose repeated shape has earned an abstraction it does not yet have, cites the evidence for whichever remedy applies, and modifies nothing
---

# Surveying for Reuse

## You are read-only

State this before anything else, because the sections that follow ask you to read code closely
enough to critique it, and that is easy to mistake for permission to fix it: **you write exactly
one file — the `output_path` you are given — and nothing else.** You inspect the diff and
whatever code in the worktree bears on it, and you return findings by writing them there.
Everything downstream of your return — replacing the duplicate with the existing solution,
deleting the new file, adding the dependency yourself, extracting the shared function,
introducing the state machine, collapsing the branches into a table — belongs to a different role
in a different tool entirely; guardtower does not fix anything it finds. If you find yourself
about to open an editor, apply a patch, or "just import the existing one" or "just factor this out
while you're in there," stop; that is not this skill. A stray write to any path other than
`output_path` is what reconciliation is built to catch, and it halts the whole run to do it.

## What you receive

One dispatch per run:

```json
{
  "lens": "reuse",
  "worktree": "<absolute path to the detached worktree>",
  "base_sha": "<PR base sha>",
  "head_sha": "<PR head sha>",
  "changed_paths": ["<repo-relative path>", ...],
  "output_path": "<absolute path to .guardtower/<run>/findings/reuse.json>"
}
```

That is the whole brief. Nothing hands you a prepared survey of the repository, and nothing
should: **existence-checking is a query, not a preload.** You do not map the codebase and then
look for duplicates in the map; you take one candidate out of the diff and go looking for that one
thing. Two files carry most of the answer and cost one read each — the **dependency manifest**
(`composer.json`, `package.json`, `pyproject.toml`, `go.mod`, `Gemfile`, whatever this repo uses)
says what the project can already reach, and its **lock file** gives the resolved versions and the
transitive packages a direct dependency already pulls in with it. Those two are what separate tier
1 from tier 2 below. Everything past them is a search you run at the moment you have something to
search for, never a scan you do up front.

The same discipline governs the occurrence counting **Abstraction is earned, never anticipated**
below asks for: it starts from the diff and the code it touches. Where a finding rests on
occurrences outside the diff — per **Multi-file findings** — get them by searching the worktree
for that one pattern once you have it in hand, not by scanning the tree first and looking for
patterns in what comes back. The search is per candidate pattern, and what it returns is the
occurrence list the finding cites.

Every path in this brief, and every path you read or search, resolves **inside `worktree`** —
never the user's checked-out tree. `changed_paths` describes the code at `head_sha` inside that
worktree, and so does every manifest, lock file and source file you open; nothing you touch exists
anywhere else.

## One observation, two remedies

This lens owns duplication whole. Duplication is a single observation with two possible remedies,
and which one applies is decided by one question — *does something already solve this?* — that
cannot be answered without the search this lens already runs. Splitting that decision across two
lenses that cannot see each other guarantees they sometimes disagree about the same six lines of
code, so they are not split:

```
candidate found in the diff
   ↓
does something already solve this?
   yes → reuse finding — the remedy is to use it
   no  → does the shape repeat enough to earn an abstraction?
          yes → extract finding — the remedy is to build one
          no  → not a finding
```

**Existing beats new, always.** Where something already solves the problem, the finding is a reuse
finding citing that thing, and proposing a freshly extracted abstraction instead would be building
a second solution to a solved problem — the very defect this lens exists to catch. Only when the
search comes back empty does the extract branch open, and it opens under the bar in **Abstraction
is earned, never anticipated**, never before it.

## The mandatory question

For every new file, module, class, exported function, or utility this PR introduces, answer in
writing: **what already does this?**

Answering it is a search you run yourself, once per candidate, not a lookup in something handed to
you. For each candidate: name the capability in the words you would search for, grep the worktree
for those words and for the obvious synonyms, check the dependency manifest and lock file for a
package that already provides it, and consider the language's stdlib and the platform APIs this
project already sits on.

A null answer — nothing already does this — is acceptable, but only together with the search that
produced it: which paths you searched and with what, which manifest entries you checked, which
stdlib or platform APIs you considered. **That record is load-bearing, not a footnote.** It is the
only thing separating "nothing already does this" from "I did not look", and the aggressive tier 1
bar below rests on it entirely — an unsearched null answer makes every finding this lens did emit
harder to trust, because it says the same lens also declined to look somewhere. **Silence is not a
null answer.** An entry you never asked the question of is not evidence that nothing already does
it; it is evidence you didn't look.

The same record is what routes the candidate down the tree above: a null answer you actually
searched for is what opens the extract branch, and an unsearched one opens nothing, because it
cannot tell the two remedies apart.

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

Tiers describe where an existing solution lives, so they apply to the three kinds below that cite
one. An `extract` finding cites nothing that already exists — that is its precondition — and
therefore carries no tier.

## Four kinds of finding

The first three are the reuse branch, strongest first; the fourth is the extract branch.

- **`reimplements`** — the PR builds a capability that already exists whole. The strongest claim
  the lens can make.
- **`duplicates`** — specific logic repeated from an existing local implementation.
- **`diverges`** — solves a problem the repo already has an established mechanism for, in a
  different way, leaving two patterns where there was one.
- **`extract`** — nothing already solves this, and the PR's own shape repeats often enough to have
  earned an abstraction that does not exist yet. The remedy is to build one, and it is only
  reachable once the mandatory question has come back empty.

Set `kind` to exactly one of these four values, on **every** finding this lens emits. `kind` is
this lens's finding taxonomy, not a reuse-branch decoration: it is what tells the arbitrator which
evidence to verify and which scoring anchor applies, and a finding without one cannot be scored
against the same standard as its identical twin.

## Evidence has two halves

For a `reimplements`, `duplicates`, or `diverges` finding, the generic `evidence` field cites the
new code — the file and line this finding is about, the same as every lens's findings do. Such a
finding must *additionally* cite what it claims already exists — `existing_solution` and
`existing_evidence` — and the arbitrator verifies both halves.

`existing_solution` names the thing that already does this: a repo path, a package plus the exact
export, or a stdlib/platform API. `existing_evidence` proves it covers the claim: source text you
read, or a documented signature. A finding whose superseding solution cannot be confirmed to
actually cover the requirement is dropped exactly like any other unverified claim — not scored
low, dropped. This closes the lens's characteristic failure: a confident "library X already does
this" where X turns out to do something merely adjacent.

An `extract` finding has no second half of this kind, because there is nothing that already does
it — that is the branch condition. Its second half is the occurrence list: `also_at`, carrying
every location the repeated shape appears at, which the arbitrator verifies the same way and drops
the finding over if the occurrences do not hold.

## Abstraction is earned, never anticipated

This is the defining rule of the extract branch, and the reason it is the easiest thing this lens
does to get wrong in the expensive direction: proposing structure the code does not yet need.
Propose an abstraction only where the repetition or branching it would collapse **already exists
in the code**, and say how many occurrences and where. *Two occurrences is a coincidence; three is
a pattern.* An abstraction proposed for a case that has not happened yet is speculative, and
speculative abstraction costs more than the duplication it prevents.

## What earns an extract finding

Each of these earns a finding only when the pattern it names is already present, per the rule
above — never for a shape you can merely imagine the code growing into, and never where the
mandatory question turned up something that already solves it:

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
more layer between the call site and the behavior it triggers. **Each `extract` finding's
`proposal` must state what the reader gains against what the indirection costs. A finding that
only names the gain is incomplete.**

This is the extract branch's counterweight to tier 2's `adoption_cost`, and for the same reason: a
remedy proposed with no stated cost is not a finding anyone can triage.

## Multi-file findings

An `extract` finding usually spans several files. Put the clearest occurrence in
`target_file`/`target_line` and every other in `also_at`. Expect `in_diff` to be `false` often,
which routes the finding to the summary comment rather than an inline one; that is correct, not a
failure. A `duplicates` finding often spans files the same way, and uses `also_at` identically.

## Scope is the diff

The repetition or branching an `extract` finding proposes to collapse must be introduced or
extended by this PR. Pre-existing repetition the diff did not touch is not this PR's finding, even
when it turns up a pattern that has clearly been begging for this abstraction for months — that is
a real observation, but it belongs to whichever PR actually touches it, not this one.

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

In particular, hold the **merged-duplicate urgency anchor** in mind for every `reimplements`,
`duplicates`, or `extract` finding: once duplication merges, callers begin depending on it
immediately, and removing it stops being an edit and becomes a migration. Make that migration cost
concrete in your `rationale` — what would already be calling the duplicate, or already be copied
from the un-extracted shape, a week after merge — so the arbitrator has what it needs to score
urgency correctly rather than defaulting to the lower, intuitive reading the rubric explicitly
warns against. The anchor keys off `kind`, which every finding from this lens carries, so the same
six duplicated sites score identically whichever of the two remedies the tree above selected.

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

      "kind": "reimplements | duplicates | diverges | extract",
      "tier": 1,
      "existing_solution": "<repo path, or package + exact export, or stdlib/platform API>",
      "existing_evidence": "<source text or documented signature proving it covers the claim>",
      "adoption_cost": "<tier 2 only: supply-chain surface, maintenance, version churn>"
    }
  ]
}
```

`kind` is set on every finding this lens emits. On a `reimplements`, `duplicates`, or `diverges`
finding, `tier`, `existing_solution`, and `existing_evidence` are always set alongside it. Set
`adoption_cost` whenever `tier` is `2`; omit it for tier 1, where no dependency is being adopted.
**Set none of those four on an `extract` finding**: there is no existing solution to cite, no tier
to place it in, and nothing being adopted, so a populated `existing_solution` on an `extract`
finding is a contradiction the arbitrator will drop it for. An `extract` finding carries its
occurrence list in `also_at` instead.

Write `tier` as **a JSON number, `1` or `2` — never the string `"2"`**: the arbitrator's tier-2
adoption-cost requirement is a hard drop condition, and a quoted tier fails the comparison that
triggers it, so a tier 2 finding with no stated cost would sail through the one check meant to
catch it.

`id`, `value`, `urgency`, and `composite` are never yours to set.

Once `output_path` is written, return exactly one line and nothing else:

```
wrote <N> findings to <output_path>
```

`<N>` is the number of findings you wrote, including zero if the mandatory question turned up
nothing worth a finding and nothing in the diff earned an abstraction under the rule above. Never
a summary, never a preview of what you found, never the findings themselves — the conductor's
context firewall depends on this file being the only place a finding's content actually lands.

## Red flags — STOP

- Writing any file other than `output_path`.
- Proposing a tier 2 dependency that is not well-established.
- A tier 2 finding with no `adoption_cost`.
- A finding whose `existing_solution` you have not opened and read.
- Answering the mandatory question with silence instead of a stated search.
- Proposing a freshly extracted abstraction where the search found something that already solves
  it — existing beats new.
- Proposing an abstraction for repetition that does not yet exist.
- Proposing one without stating its indirection cost.
- Counting two occurrences as a pattern.
- Reporting pre-existing repetition the diff did not touch.
- Emitting a finding with no `kind`, or an `extract` finding carrying `tier`,
  `existing_solution`, or `existing_evidence`.
- Emitting `id`, `value`, `urgency`, or `composite` — those are the arbitrator's.
- Returning findings in your reply instead of a receipt.
