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
  "output_path": "<absolute path to .guardtower/<run>/findings/reuse.json>",
  "skill_path": "<absolute path to the SKILL.md this dispatch names>",
  "schema_path": "<absolute path to finding-schema.md>"
}
```

That is the whole brief. Nothing hands you a prepared survey of the repository, and nothing
should: **existence-checking is a query, not a preload.** You do not map the codebase and then
look for duplicates in the map; you take one candidate out of the diff and go looking for that one
thing.

**Work inside the read radius `schema_path` defines** — the diff, the changed files, the dependency
manifest, and one hop from a changed line — and reach past it only by the **one targeted search per
candidate** the radius allows. This lens is the one that most wants to keep looking, because a
null answer always feels like it might be one more grep away from a hit. It is not: one search,
then the answer is whatever that search returned. The manifest is what separates tier 1 from tier
2 below; the lock file is outside the radius and you do not read it.

Every path in this brief, and every path you read or search, resolves **inside `worktree`** —
never the user's checked-out tree. `changed_paths` describes the code at `head_sha` inside that
worktree, and so does every manifest and source file you open; nothing you touch exists anywhere
else.

`skill_path` is this document and `schema_path` is the finding contract you write to — open the
contract before you write anything, because the arbitrator drops a finding for a field you did not
know it wanted, and because the read radius is defined there. They are paths in the brief rather
than links in this file because a dispatched subagent cannot resolve a relative citation from a
directory it was never told it is standing in.

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

Answering it is a search you run yourself, **once** per candidate, not a lookup in something handed
to you. For each candidate: name the capability in the words you would search for, run that **one**
grep against the worktree, and read the answer off the manifest already inside your radius — not
that grep plus its synonyms, and not a widening series of them until something turns up.

**A null answer is a finished answer, not a cue to widen.** One search that returns nothing settles
the candidate: the reuse branch closes and the extract branch opens under the bar below. Going back
for a second search with different words is how a bounded question becomes an open-ended survey of
the application, and it is the specific thing the read radius exists to stop.

A null answer is acceptable, but only together with the search that produced it: what you searched
for, and where. **That record is load-bearing, not a footnote.** It is the
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

**The record has a place to go: the `unanswered` array in your output file.** Write one entry per
candidate whose question came back empty — the candidate, and the one search you ran for it. It is
one line per candidate, because one search is all the radius allows and there is nothing else to
report. It is not a finding, it is not scored, and the arbitrator skips it; it exists so that
"load-bearing" is
something the file can actually hold. Do not put it in your receipt, and do not name a null
candidate in your reply: the first live run had nowhere to put this record and returned its null
candidates by name to the conductor, breaching the context firewall to satisfy a rule this skill
had made mandatory and then given no home. A record required to be produced and then structurally
discarded is a rule that guarantees the breach; the array is the fix.

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

**Which form you owe depends on one thing: is the existing solution in this repository?**

- **A path in this repo** — open it and quote the source text. It is inside your read radius by
  definition, since a repo path is exactly what a targeted search returns.
- **Anything else** — a language stdlib call, a platform API, an installed package, or a `tier: 2`
  package that is not installed — cite the **documented signature**. There is no dependency tree in
  the worktree to open, and going to find one is outside the radius.

That is the whole rule, and the split is *in this repo or not*, never *openable or not*. An earlier
version split it the second way and added a carve-out saying installed packages counted as openable
because the conductor linked `vendor/` in — which made the strong form of the rule, *never cite an
`existing_solution` you have not opened*, **unsatisfiable by construction** on the first live run,
where 3 of this lens's 4 findings cited an installed package and the tree was not there. A rule
nothing can satisfy gets ignored or silently drops good findings, and both happened. The rule above
is satisfiable for every citation you can make, because every citation is on one side of it or the
other.

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

**Occurrences come from inside the read radius, found by the one search the pattern gets** — the
same bound every other question in this lens works under. A shape that does not repeat three times
within the diff, the changed files, and one hop from a changed line has not earned an abstraction
*here*, whatever it does elsewhere in the application. Do not go looking for the third occurrence:
the bar is three verified occurrences inside the radius, and a search that finds two settles the
question at two.

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
      "also_at": ["<file:line, or file:start-end>"],

      "kind": "reimplements | duplicates | diverges | extract",
      "tier": 1,
      "existing_solution": "<repo path, or package + exact export, or stdlib/platform API>",
      "existing_evidence": "<source text or documented signature proving it covers the claim>",
      "adoption_cost": "<tier 2 only: supply-chain surface, maintenance, version churn>"
    }
  ],

  "unanswered": [
    {
      "candidate": "<the new file, module, class, exported function or utility>",
      "searched": "<the one search you ran for it: the words, and where you ran them>"
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

**`unanswered` is a sibling of `findings`, not a finding.** It carries **The mandatory question**'s
null-answer record: one entry per candidate the search came back empty on, whether or not that
candidate went on to earn an `extract` finding. Write `[]` when every candidate turned up something
that already solves it. Nothing scores it and nothing gates it — the arbitrator skips the array
entirely — and that is the point: the record is kept where it can be audited without any of it
reaching the conductor.

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
- Reading outside the read radius: a lock file, an installed package's source, or any file more
  than one hop from a changed line.
- Running a second search for a candidate the first search already answered, or widening a search
  with synonyms until it returns something.
- Proposing a tier 2 dependency that is not well-established.
- A tier 2 finding with no `adoption_cost`.
- A finding whose `existing_solution` is a repo path you have not opened and quoted, or is outside
  this repo and carries no documented signature.
- Answering the mandatory question with silence instead of a stated search.
- Keeping the null-answer record out of `unanswered`, or naming a null candidate in your reply
  instead of writing it there.
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
