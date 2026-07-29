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
You are that something. Read every path in `finding_paths` before you do anything else.

## What you receive

One dispatch per run:

```json
{
  "finding_paths": ["<absolute path to .guardtower/<run>/findings/<lens>.json>", "..."],
  "worktree": "<absolute path to the detached worktree>",
  "base_sha": "<PR base sha>",
  "head_sha": "<PR head sha>",
  "threshold": 80,
  "lenses_run": ["reuse", "security", "smell", "abstraction"]
}
```

`finding_paths` holds one file per lens actually dispatched this run — a lens the user dropped in
preflight was never dispatched and has no file here. `lenses_run` names the same set; use it as a
sanity check that `finding_paths` has exactly one entry per lens actually run, not as something to
report onward — the conductor already knows which lenses it chose to skip. `worktree` is where
`target_file` and `existing_solution` resolve — never the user's checked-out tree, and never
wherever your own working directory happens to be. `threshold` is the gate **Gate and rank** below
applies.

## Verify before you score

For every finding in every file, open `target_file` at `target_line` **inside the worktree** and
compare it against `evidence`. The evidence holds only if the cited text is actually there. If the
line has moved, the text differs from what's quoted, or the cited code turns out to be a comment or
a string literal rather than the thing it's accused of being, **drop the finding and state why in
one line.** Do not score it low; dropping and low-scoring are different outcomes and the report
distinguishes them.

## Reuse findings have two halves

A `reuse` finding's `evidence` proves the new code exists; it says nothing about whether
`existing_solution` genuinely covers the claim. Also open `existing_solution` and confirm
`existing_evidence` shows it genuinely covers the claim. A superseding solution that turns out to
do something merely adjacent — not the same thing, just nearby — fails verification exactly like
stale evidence: the finding drops. For `tier: 2`, additionally require a non-empty `adoption_cost`;
a tier 2 finding that omits it drops as well, because a dependency proposed with no stated cost is
not a finding you can score.

## Score against the published rubric

Read `../reviewing-a-pull-request/references/scoring-rubric.md` and apply it as written — every
band, the composite formula, and the anchor. Inventing your own criteria here destroys
reproducibility, which is the only reason the rubric is published at all: two runs over the same
surviving findings must land on the same numbers, and that only holds if both runs score against
the same document instead of each arbitrator's private judgment.

Score `value` and `urgency` against the rubric's tables for every finding that survived
verification, then compute `composite` as `round(0.6 × value + 0.4 × urgency)`, never a number you
estimate yourself. Apply the rubric's merged-duplicate urgency anchor to every `reimplements` or
`duplicates` finding: urgency lands at 70–89, not the lower band the same evidence would suggest for
anything else, because a duplicate capability that merges starts acquiring callers immediately, and
removing it later is a migration, not an edit.

## Assign ids

Assign `id` as `<lens>-<nnn>`, zero-padded to three digits, numbered per lens in the order findings
appear in that lens's file — `security-001`, `security-002`, `reuse-001`. Ids, like `value`,
`urgency`, and `composite`, are yours to assign, never an analyst's; if a finding somehow arrives
already carrying one, discard it and assign your own rather than passing it through unchecked —
see **Red flags** below.

## Gate and rank

Keep every finding whose `composite` is at or above `threshold`; everything below it is discarded,
not dropped. Sort `passed` by the total order the rubric defines: `composite` descending, then
`value` descending, then `target_file` ascending, then `id` ascending. The last two exist because
`composite` and `value` alone leave ties, and a tie broken by iteration order would mean two runs
over the identical set of surviving findings could render two different briefs — the total order
closes that gap so they can't.

## Three outcomes, never conflated

Every finding you touch ends in exactly one of three states, and they mean different things:

- **`dropped`** — evidence failed. Never scored. Carries `reason`, never `value`, `urgency`, or
  `composite`.
- **`discarded`** — verified, scored, and `composite` fell short of `threshold`.
- **`passed`** — verified, scored, and cleared the gate.

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
      "lens": "reuse | security | smell | abstraction",
      "target_file": "<repo-relative path>",
      "target_line": "<line or start-end range, at the head sha>",
      "claim": "<what is wrong, as an observable consequence>",
      "rationale": "<what breaks, for whom, and how they find out>",
      "proposal": "<what to do instead — prose, never a patch>",
      "in_diff": true,
      "also_at": ["<file:line>"],
      "kind": "<reuse lens only: reimplements | duplicates | diverges>",
      "tier": "<reuse lens only: 1 | 2>",
      "existing_solution": "<reuse lens only>",
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

`passed` is sorted by the total order from **Gate and rank**; `dropped` and `discarded` carry no
required order beyond the order you encountered them in. This return is the one exception
**Context discipline** in the conductor's `SKILL.md` names: the conductor is permitted, and
required, to read it — everything it reports and everything it renders into `brief.md` comes from
these three lists and nothing else.

## Red flags — STOP

- Scoring a finding without opening the file it cites.
- Scoring a reuse finding without opening its `existing_solution`.
- Inventing scoring criteria instead of applying `scoring-rubric.md` as written.
- Conflating dropped with discarded.
- Writing any file — you return your result, you do not write it anywhere.
- Returning findings that did not clear the gate inside `passed`.
- Letting an analyst-supplied `id`, `value`, `urgency`, or `composite` through unchecked.
