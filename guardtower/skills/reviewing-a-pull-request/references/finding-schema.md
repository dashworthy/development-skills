# Finding schema

This is the contract every analyst writes and the arbitrator reads.

## Fields

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | `<lens>-<nnn>` — `security-003`, `reuse-011`. Assigned by the arbitrator on merge |
| `lens` | yes | `reuse`, `security`, or `smell` |
| `target_file` | yes | Repo-relative path |
| `target_line` | yes | Line or range the evidence sits at, at the head sha |
| `evidence` | yes | The actual source text at that location — what the arbitrator re-reads to confirm |
| `claim` | yes | What is wrong, as an observable consequence |
| `rationale` | yes | Why it matters, concretely: what breaks, for whom, how they find out |
| `proposal` | yes | What to do instead. Prose, never a patch — guardtower does not modify code |
| `in_diff` | yes | Whether `target_line` falls inside a diff hunk. Decides inline vs summary |
| `also_at` | no | Further `file:line` locations for a finding spanning several files |
| `kind` | every reuse finding | `reimplements`, `duplicates`, `diverges`, or `extract` — defined in `../../surveying-for-reuse/SKILL.md` |
| `tier` | reuse, not `extract` | A JSON number, never a string: `1` already reachable, `2` not yet installed |
| `existing_solution` | reuse, not `extract` | The thing that already does this: a repo path, a package plus the exact export, or a stdlib/platform API |
| `existing_evidence` | reuse, not `extract` | Source text or documented signature proving it covers the claim |
| `adoption_cost` | tier 2 only | What adding this dependency costs: supply-chain surface, maintenance, version churn |
| `value` | yes | 0–100, assigned by the arbitrator |
| `urgency` | yes | 0–100, assigned by the arbitrator |
| `composite` | yes | `round(0.6 × value + 0.4 × urgency)`, assigned by the arbitrator |

Analysts set everything except `id`, `value`, `urgency`, and `composite`. Those are the
arbitrator's.

## Return shape

Write exactly this shape to your `findings/<lens>.json`:

```json
{
  "findings": [
    {
      "lens": "reuse | security | smell",
      "target_file": "<repo-relative path>",
      "target_line": "<line or start-end range, at the head sha>",
      "evidence": "<the actual source text at that location>",
      "claim": "<what is wrong, as an observable consequence>",
      "rationale": "<what breaks, for whom, and how they find out>",
      "proposal": "<what to do instead — prose, never a patch>",
      "in_diff": true,
      "also_at": ["<file:line>"],

      "kind": "<reuse lens: reimplements | duplicates | diverges | extract>",
      "tier": 1,
      "existing_solution": "<reuse lens, not on an extract finding>",
      "existing_evidence": "<reuse lens, not on an extract finding>",
      "adoption_cost": "<reuse lens, tier 2 only>"
    }
  ]
}
```

## `kind` is the reuse lens's whole taxonomy

The reuse lens owns duplication whole — both the half where something already exists and the half
where a repeated shape has earned an abstraction that does not — so **every** finding it emits
carries a `kind`, and `extract` is the value for the second half. It is not a decoration on the
findings that cite an existing solution.

That matters beyond vocabulary, because `scoring-rubric.md`'s merged-duplicate urgency anchor keys
off this field. While duplication was split across two lenses and only one of them set `kind`, the
same duplicated code scored differently depending on which lens happened to raise it — observed
live, at composite 81 and 74 on the same six sites. One lens, one taxonomy, one anchor closes
that.

The three fields that cite an existing solution — `tier`, `existing_solution`, `existing_evidence`
— are set on `reimplements`, `duplicates`, and `diverges` findings and **not** on an `extract`
finding, whose precondition is that no existing solution was found. An `extract` finding's second
half of evidence is its occurrence list in `also_at`.

`tier` is the one field of those three that is **a JSON number, not a string** — write `1` or `2`,
never `"1"` or `"2"`. It is pinned because the arbitrator's tier-2 rule is a hard drop condition:
a finding whose `tier` arrives as the string `"2"` and is compared against the number `2` fails
that comparison, the adoption-cost requirement is never applied, and a tier 2 finding with no
stated cost passes verification it should have been dropped by.

## What the arbitrator owns

`id`, `value`, `urgency`, and `composite` are never set by an analyst. The arbitrator assigns
`id` on merge, scores `value` and `urgency` against `scoring-rubric.md`, and computes
`composite`. Emitting any of these four fields is an error, not a helpful extra — an analyst
that guesses a score is inventing a number the arbitrator's rubric exists specifically to
replace, and the conductor cannot tell a guessed score from a real one just by looking at it.

## Evidence is not optional

`evidence` must be the actual source text at `target_line` — copied, not paraphrased — because
the arbitrator re-reads that exact location in the worktree and compares what it finds against
what you wrote. A paraphrase fails that comparison exactly like evidence that has gone stale:
the finding is dropped, and the work that produced it is wasted. If you cannot quote the line,
you do not yet have a finding.

## Where you read

Every path you write or read is relative to the **worktree** the dispatch brief names — never
the user's checked-out tree. The dispatch brief hands you the worktree path along with the base
sha, head sha, and changed paths; read and cite locations there, not wherever your own working
directory happens to be.

## You are read-only

State this before anything else because reading code closely enough to critique it is easy to
mistake for permission to fix it: **you write exactly one file, your own
`findings/<lens>.json`, and nothing else.** You inspect the diff and the code it touches, and
you return findings in that one file. Everything downstream of your return — verifying,
scoring, posting a comment — belongs to a different role in the run. If you find yourself about
to open an editor, apply a patch, or touch any path outside your own findings file, stop; that
is not this skill. A stray write outside `findings/<lens>.json` is what reconciliation is built
to catch, and it halts the whole run to do it.

## `in_diff`

Set `in_diff` to `true` only when `target_line` falls inside a hunk of the
`<base-sha>...<head-sha>` diff — false otherwise, including when the line exists but predates
the PR. This field decides inline versus summary placement when the review posts, and a wrong
value costs a misplaced comment: a finding marked `in_diff: true` that isn't posts nowhere the
forge will accept, and one marked `false` that should be `true` buries an inline-worthy finding
in the summary instead.
