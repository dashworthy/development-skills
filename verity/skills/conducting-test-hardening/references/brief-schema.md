# Brief schema

A brief is one markdown file per iteration at `.verity/briefs/<n>.md`. It carries four
item kinds. Every item has an `id` of the form `<suite>-<track>-<nnn>` — for example
`backend-unit-003`. Ownership findings use `<suite>` of `unowned`.

An item carried into a later iteration KEEPS its original id, and gains `carried_from`
naming the iteration it first appeared in. This is what lets the conductor tell rework
from new work.

## Gap finding

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | `<suite>-<track>-<nnn>` |
| `suite` | yes | Owning suite name, as confirmed during stack detection |
| `track` | yes | `unit`, `gherkin`, or `mutation` |
| `target_file` | yes | Application file, repo-relative |
| `target_symbol` | yes | Function, method, class, or scenario the gap sits in |
| `behavior` | yes | The specific untested behavior or branch, stated as an **observable outcome** — what the code does that nothing would notice breaking |
| `risk_level` | yes | `high`, `medium`, or `low`. The conductor ranks on this |
| `risk` | yes | Why an escape here would matter — one sentence, concrete. Justifies `risk_level`; it does not replace it |
| `test_intent` | yes | What the test must **assert**, specific enough for the verifier to check the written test against afterwards |
| `target_test_file` | yes | Where the test should go; an EXISTING file wherever one fits |
| `status` | yes | `open`, `satisfied`, or `rework`. The conductor sets it; the writer and verifier are what move it |
| `satisfied_by` | no | Test names that satisfied this item, written by the conductor from the writer's return |
| `iteration` | yes | Iteration number that first produced this item |
| `carried_from` | no | Iteration number this item first appeared in, when carried forward |
| `prior_verdict` | no | `weak`, `invalid`, or `unevaluated` when this is a carried-forward item |
| `prior_defect` | no | The defect name from the verifier's taxonomy |
| `prior_defect_location` | no | `file:line` the verifier flagged. A defect name alone lets a writer reproduce the same defect in a new guise |
| `prior_unevaluated_reason` | no | Present when `prior_verdict` is `unevaluated`: the verifier's stated reason it could not judge the attempt (suite errored, code under test no longer exists, environment could not run it) |
| `mutant_operator` | no | Present when `track` is `mutation`: the mutation operator that survived |
| `mutant_line` | no | Present when `track` is `mutation`: `file:line` of the surviving mutant |

**`behavior` versus `test_intent`.** They are not the same field said twice, and the verifier's
brief-drift check depends on the difference. `behavior` is what the *code* does that is
currently unguarded. `test_intent` is what the *test* must assert to guard it. For a boundary
gap: behavior = "returns the last element when the index equals length-1"; test_intent =
"assert the value at index length-1 equals the final element, and that index length raises".
When the verifier checks for drift, `test_intent` is the authoritative anchor.

**Surviving mutants are gap findings with `track: mutation`, but they arrive incomplete.**

A mutation report gives an operator and a location — nothing more. It does not tell you what
behavior went unguarded, what a test should assert, or which file that test belongs in. So a
surviving mutant is **evidence pointing at a line, not a finished item**, and the auditor is
what turns one into the other:

1. The conductor passes surviving mutants to the next iteration's auditor as carry-forward,
   each carrying only `suite`, `mutant_operator`, and `mutant_line`.
2. The auditor **reads the code at that line** and derives `target_symbol`, `behavior`,
   `test_intent`, `target_test_file`, `risk_level`, and `risk` exactly as it would for a gap it
   found by reading the diff. The mutant tells it where to look; the code tells it what to say.
3. If the auditor reads the line and concludes the surviving mutant is not worth a test —
   equivalent mutants and unreachable branches both happen — it drops the item and says so in
   its return rather than emitting a finding with invented fields.

Never fabricate `behavior` or `test_intent` from an operator name. "ConditionalBoundary survived
at Foo.ext:42" is not a behavior, and a test written against that string would assert nothing
meaningful. Once the auditor has derived the fields, the item ranks, dedups, and carries forward
like any other gap.

**Ranking must be total, not partial.** Order gap findings by `risk_level` (high, medium, low),
then rework items before fresh ones within a level, then by `target_file` ascending, then by
`id` ascending. The last two exist so that two runs over the same findings produce the same
brief; without them the order of peers is whatever the merge happened to produce.

## Breakage finding

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | `<suite>-breakage-<nnn>` |
| `suite` | yes | Owning suite, or `unowned` |
| `target_file` | yes | Application file, repo-relative |
| `target_symbol` | yes | Where the suspect behavior lives |
| `observation` | yes | What the code actually does |
| `expectation` | yes | What it appears intended to do, and what that belief rests on |
| `confidence` | yes | `high`, `medium`, or `low` |

A breakage finding NEVER carries a proposed fix. Verity does not modify application code,
and a fix in the brief invites someone to apply it.

## Ownership finding

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | `unowned-ownership-<nnn>` |
| `path` | yes | Changed file matching no suite's `paths.app` |
| `note` | yes | Why it is unowned — outside every glob, or caught by an exclude |

## Rework item

A gap finding with `carried_from`, `prior_verdict`, `prior_defect`, and where available
`prior_defect_location` populated, and `status` set to `rework`. It is not a separate kind;
the fields are what mark it.

## Who writes what

Every consumer's write surface is defined here so none of them has to invent one.

| Role | Reads | Writes back |
|---|---|---|
| Auditor | prior items as carry-forward input | new gap and breakage findings, with `risk_level` set |
| Conductor | everything | assigns `id` and `iteration`, dedups, ranks by `risk_level`, maintains `status` and `satisfied_by` |
| Writer | gap findings for its target file | per item: satisfied or not, with a reason when not, plus the test names it wrote |
| Verifier | `test_intent` and `behavior` for the item a test claims | per test: verdict, defect name, and `file:line` |

The writer and verifier return their results to the conductor rather than editing the brief
file directly — the conductor owns the document. Their return shapes are defined in their own
skills, but the fields they populate here are `status`, `satisfied_by`, `prior_verdict`,
`prior_defect`, and `prior_defect_location`.
