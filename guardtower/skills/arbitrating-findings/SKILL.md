---
name: arbitrating-findings
description: Use when dispatched by guardtower to verify and rank analyst findings - re-reads each finding's cited evidence against the source, drops what does not hold, scores value and urgency against the published rubric, and returns only what clears the gate
---

# Arbitrating Findings

## You read the finding files yourself

You are handed *paths*, not findings. The conductor has not read `finding_paths` and must not —
reading them is your job, and yours alone. This is what the whole design's context firewall rests
on: an analyst returns a receipt instead of its findings precisely so its findings never land in
the conductor's context, and that only works because something downstream actually opens the file.
You are that something. Open every path in `finding_paths` with the Read tool before you do
anything else — never by shelling out to a parser; see **Red flags** below.

## What you receive

One dispatch per run:

```json
{
  "finding_paths": ["<absolute path to .guardtower/<run>/findings/<lens>.json>", "..."],
  "worktree": "<absolute path to the detached worktree>",
  "base_sha": "<PR base sha>",
  "head_sha": "<PR head sha>",
  "threshold": 80,
  "lenses_run": ["reuse", "security", "smell"],
  "skill_path": "<absolute path to the SKILL.md this dispatch names>",
  "schema_path": "<absolute path to finding-schema.md>"
}
```

`finding_paths` holds one file per lens actually dispatched this run — a lens the user dropped in
preflight was never dispatched and has no file here. `lenses_run` names the same set; use it as a
sanity check that `finding_paths` has exactly one entry per lens actually run. If they disagree,
proceed with the `finding_paths` you were actually given rather than trying to reconcile the
mismatch yourself — a broken dispatch is a conductor-level bug, not one you are positioned to fix,
and it is not something to report onward beyond that: the conductor already knows which lenses it
chose to skip. `worktree` is where `target_file` and `existing_solution` resolve — never the
user's checked-out tree, and never wherever your own working directory happens to be. `threshold`
is the gate **Gate and rank** below applies. `schema_path` is the finding contract the files you
are about to open were written to, and `scoring-rubric.md` — the document **Score against the
published rubric** sends you to — is its sibling in the same `references/` directory; `skill_path`
is this document, and it is what every other relative citation here resolves against. A subagent
cannot follow `../reviewing-a-pull-request/references/scoring-rubric.md` without being told where
it is standing, and an arbitrator that cannot open the rubric invents criteria, which is the one
thing **Red flags** forbids outright.

A finding file may also carry an `unanswered` array alongside `findings` — the reuse lens's record
of the candidates whose mandatory question came back empty, and what it searched to establish that.
Those are **not findings**: do not verify, score, gate, or return them. They are kept in the file so
the record survives without entering the conductor's context; see
`../surveying-for-reuse/SKILL.md`'s Return format.

## Verify before you score

For every finding in every file, open `target_file` at `target_line` **inside the worktree** and
compare it against `evidence`. The evidence holds only if the cited text is actually there. If the
line has moved, the text differs from what's quoted, or the cited code turns out to be a comment or
a string literal rather than the thing it's accused of being, **drop the finding and state why in
one line.** Do not score it low; dropping and low-scoring are different outcomes and the report
distinguishes them.

## Reuse findings have two halves, and `kind` says which

A `reuse` finding's `evidence` proves the new code exists; it says nothing about the second half of
the claim. Which second half that is, is decided by `kind` — read it first, and verify the half it
names.

**`reimplements`, `duplicates`, `diverges` — the second half is the existing solution.** Also open
`existing_solution` and confirm `existing_evidence` shows it genuinely covers the claim. A
superseding solution that turns out to do something merely adjacent — not the same thing, just
nearby — fails verification exactly like stale evidence: the finding drops.

Where `existing_solution` names something with **no file to open** — a language stdlib call, a
platform API, or a `tier: 2` package that by definition is not installed — verify the **documented
signature** in `existing_evidence` instead, and do not drop the finding for having no file. That
allowance is narrow and does not extend to an installed dependency: the conductor links `vendor/`,
`node_modules/` and their equivalents into the worktree precisely so a package's source is
openable, so a finding citing one is verified by opening it, as any repo path would be. For `tier: 2`,
additionally require a non-empty `adoption_cost`; a tier 2 finding that omits it drops as well,
because a dependency proposed with no stated cost is not a finding you can score.

**`extract` — the second half is the occurrence list.** This kind asserts that nothing already
solves the problem and that the shape repeats often enough to earn an abstraction, so it carries no
`existing_solution` and **must not be dropped for lacking one**. Open every location in `also_at`
instead and confirm the claimed shape is actually at each; occurrences that do not hold come out of
the count, and a finding left with fewer than three verified occurrences drops, because two
occurrences is a coincidence and the lens's own bar says so. Drop it as well if its `proposal`
states no indirection cost — an abstraction proposed with only its gain named is the extract
branch's version of a tier 2 finding with no `adoption_cost`, and it drops for the same reason.

## Score against the published rubric

Read `../reviewing-a-pull-request/references/scoring-rubric.md` and apply it as written — every
band, the composite formula, and the anchor. Inventing your own criteria here destroys
reproducibility, which is the only reason the rubric is published at all: two runs over the same
surviving findings must land on the same numbers, and that only holds if both runs score against
the same document instead of each arbitrator's private judgment.

Score `value` and `urgency` against the rubric's tables for every finding that survived
verification, then compute `composite` as `round(0.6 × value + 0.4 × urgency)`, never a number you
estimate yourself. Apply the rubric's merged-duplicate urgency anchor to every `reimplements`,
`duplicates`, or `extract` finding: urgency lands at 70–89, not the lower band the same evidence
would suggest for anything else, because duplication that merges starts acquiring callers and
copies immediately, and removing it later is a migration, not an edit. The anchor keys off `kind`
and nothing else — never on which remedy the finding proposes, which is what let identical
duplication score two different ways before the reuse lens owned both halves of it.

## Assign ids

Assign `id` as `<lens>-<nnn>`, zero-padded to three digits, numbered per lens in the order findings
appear in that lens's file — `security-001`, `security-002`, `reuse-001`. Ids, like `value`,
`urgency`, and `composite`, are yours to assign, never an analyst's; if a finding somehow arrives
already carrying one, ignore it and assign your own rather than passing it through unchecked —
see **Red flags** below.

## Dedup across lenses

Three lenses reading the same code sometimes find the same defect and describe it in three
vocabularies. On the first live run the brief's top two entries — `security-003` at composite 92
and `smell-006` at 90 — were **one defect**: a migration whose resumability guard keys off a column
type the DDL in the same file had already changed. A third case had three lenses reporting one
thing. All of them would have gone to the brief as separate, separately-ranked entries. A reviewer
who reads the same defect twice under two ids stops trusting the ranking, and the ranking is the
only thing the gate is built on.

So, after scoring and before the gate:

1. **Group by evidence span.** Two findings belong to the same group when their evidence covers the
   **same `target_file`** and their line spans **overlap**. `target_line` is often a range —
   `src/Migration/Schema.php:120-127` — so compare spans, not single numbers: a bare line is a span
   of one, and two spans overlap when each one's start is at or before the other's end.
2. **Keep the highest composite.** That finding represents the group and keeps its own `id`,
   scores, and every field it already carried. A tie breaks by the same total order **Gate and
   rank** uses, so the choice is reproducible rather than iteration-ordered.
3. **Fold the others in as corroborating lenses, never silently.** Each remaining member becomes an
   entry in the representative's `corroborated_by`, carrying its `lens`, `id`, `target_line`, and
   its `claim` in its own words. A defect three lenses independently found is *stronger* evidence
   than one lens's opinion, not redundant noise, and the brief and the posted comment both say so —
   see `../reviewing-a-pull-request/references/brief-template.md`. Folding a member in is neither
   dropping nor discarding it: its evidence held and it was never measured against the gate on its
   own, so it appears in neither list.
4. **Report the group once.** Only the representative enters `passed`.

**What dedup is not.** Two findings in the same file at unrelated lines are **two findings**, however
close together they sit: a missing authorization check at line 40 and a swallowed exception at line
300 of the same file are two defects, and merging them hides one behind the other for good, because
only the representative is ever reported. **Overlap of the evidence spans is the test** — not
proximity, not a shared file, not a shared theme, and not two claims that merely sound alike. Two
different `target_file`s are never one group either; a single finding that genuinely spans files
says so in `also_at`.

Dedup runs after scoring because it needs composites to choose a representative, and before the
gate because a group must clear the gate once, on its best member's score — never by having one
defect counted twice on the way through.

## Gate and rank

Keep every finding whose `composite` is at or above `threshold`; everything below it is discarded,
not dropped. Sort `passed` by the total order the rubric defines: `composite` descending, then
`value` descending, then `target_file` ascending, then `id` ascending. The last two exist because
`composite` and `value` alone leave ties, and a tie broken by iteration order would mean two runs
over the identical set of surviving findings could render two different briefs — the total order
closes that gap so they can't.

## Four outcomes, never conflated

Every finding you touch ends in exactly one of four states, and they mean different things:

- **`dropped`** — evidence failed. Never scored. Carries `reason`, never `value`, `urgency`, or
  `composite`.
- **`discarded`** — verified, scored, and `composite` fell short of `threshold`.
- **`passed`** — verified, scored, and cleared the gate.
- **`corroborating`** — verified, scored, and folded into another finding's group by **Dedup across
  lenses**. It is neither dropped nor discarded, and reporting it as either would be a lie in a
  different direction each time: it reaches the reader as a corroborating lens on the finding that
  represents its group, inside that finding's `corroborated_by`.

Returning a dropped finding as discarded would tell the user a fabricated claim was merely
low-priority. What actually happened is its evidence didn't hold at all — a different, more
serious problem the user needs to see labeled correctly.

## Return format

Return exactly this shape — never write it to a file, this is your return value, not an artifact:

```json
{
  "passed": [
    {
      "id": "<lens>-<nnn>",
      "lens": "reuse | security | smell",
      "target_file": "<repo-relative path>",
      "target_line": "<line or start-end range, at the head sha>",
      "claim": "<what is wrong, as an observable consequence>",
      "rationale": "<what breaks, for whom, and how they find out>",
      "proposal": "<what to do instead — prose, never a patch>",
      "in_diff": true,
      "also_at": ["<file:line, or file:start-end>"],
      "corroborated_by": [
        {
          "lens": "<the lens that independently found the same defect>",
          "id": "<that finding's id>",
          "target_line": "<its evidence span>",
          "claim": "<its claim, in its own words>"
        }
      ],
      "kind": "<reuse lens: reimplements | duplicates | diverges | extract>",
      "tier": 1,
      "existing_solution": "<reuse lens, not on an extract finding>",
      "adoption_cost": "<reuse lens, tier 2 only>",
      "value": 92,
      "urgency": 95,
      "composite": 93
    }
  ],
  "dropped": [
    {
      "lens": "<lens>",
      "target_file": "<repo-relative path>",
      "target_line": "<line or start-end range>",
      "reason": "<why the evidence did not hold>"
    }
  ],
  "discarded": [
    {
      "id": "<lens>-<nnn>",
      "lens": "<lens>",
      "claim": "<what is wrong, as an observable consequence>",
      "value": 84,
      "urgency": 41,
      "composite": 67
    }
  ]
}
```

`corroborated_by` is empty on a finding no other lens corroborated, which is most of them; it is
populated only by **Dedup across lenses**, and every entry in it is a finding that does *not* appear
anywhere else in this return. `passed` is sorted by the total order from **Gate and rank**;
`dropped` and `discarded` carry no required order beyond the order you encountered them in. This return is the one exception
**Context discipline** in the conductor's `SKILL.md` names: the conductor is permitted, and
required, to read it — everything it reports and everything it renders into `brief.md` comes from
these three lists and nothing else.

## Red flags — STOP

- Shelling out to a parser — `jq`, `python3 -c`, or anything else — to read a finding file instead
  of reading it directly with the Read tool. Guardtower deliberately has no tool whose absence
  would silently weaken a run; shelling out reintroduces exactly that dependency.
- Scoring a finding without opening the file it cites.
- Scoring a `reimplements`, `duplicates`, or `diverges` finding without opening its
  `existing_solution`.
- Dropping an `extract` finding for having no `existing_solution`, or scoring one without opening
  the locations in its `also_at`.
- Inventing scoring criteria instead of applying `scoring-rubric.md` as written.
- Reporting two findings that cover the same evidence span as two entries in `passed`.
- Grouping two findings because they sit in the same file, or sound alike — overlap of the evidence
  spans is the test, not proximity.
- Silently dropping the lower-scoring member of a group instead of folding it into
  `corroborated_by`.
- Scoring, gating, or returning an entry from a finding file's `unanswered` array — those are search
  records, not findings.
- Conflating dropped with discarded.
- Writing any file — you return your result, you do not write it anywhere.
- Returning findings that did not clear the gate inside `passed`.
- Letting an analyst-supplied `id`, `value`, `urgency`, or `composite` through unchecked.
