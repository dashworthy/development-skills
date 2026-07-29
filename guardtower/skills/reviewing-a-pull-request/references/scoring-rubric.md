# Scoring rubric

A bare 0–100 with no criteria is not reproducible across runs — the same reason verity spells
out what separates a high-risk finding from a medium one. This rubric is published, and both
analysts and arbitrator work to it, so two runs over the same PR land on the same numbers.

## Value — what accepting it is worth

| Score | Criterion |
|---|---|
| 90–100 | Removes a live defect, a security hole, or a data-loss path |
| 70–89 | Removes duplication or complexity that has caused, or will predictably cause, a bug |
| 40–69 | Genuine improvement with no concrete failure attached |
| 0–39 | Stylistic preference, or defense-in-depth on a path already guarded elsewhere |

## Urgency — what waiting costs

| Score | Criterion |
|---|---|
| 90–100 | Ships in this PR and is exploitable or breaking once merged |
| 70–89 | Cost of fixing rises sharply after merge — public API, migration, data shape |
| 40–69 | Same cost later as now |
| 0–39 | Cheaper later, or may become moot |

**Anchor — a merged duplicate is a migration.** A `reimplements` or `duplicates` finding sits at
**70–89** on urgency, not 40–69. Once a duplicate capability merges, callers begin depending on it
immediately, and removing it stops being an edit and becomes a migration. This anchor is stated
explicitly because the alternative reading is the intuitive one and it quietly kills the lens:
value 85 with urgency 60 composites to 75 and is discarded, so an aggressive reuse challenge that
finds real duplication would produce nothing that ever clears the gate. With the correct reading,
85 and 80 composite to 83 and pass.

## Composite and gate

**Composite:** `round(0.6 × value + 0.4 × urgency)`. Default gate: **80**.

## Tie-break

**Tie-break.** Rank by `composite` descending, then `value` descending, then `target_file`
ascending, then `id` ascending — a total order, so two runs over the same findings render an
identical brief.

