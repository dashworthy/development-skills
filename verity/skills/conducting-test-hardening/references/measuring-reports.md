# Measuring Test Reports

## What you receive

One dispatch: `{suite, report_path, report_format, report_kind, changed_files}`. `report_kind`
is `coverage` or `mutation` — it tells you which shape of number to extract and which sanity
rules apply. You see exactly one suite's report; nothing here is compared or blended across
suites.

## Why this is a separate agent

Reports are large and the conductor must stay small. You read the report file so the conductor
never has to; only the numbers below come back. That is the entire reason this dispatch exists
as its own skill rather than a step inside the conductor — never echo the report's contents
into your return value, at any point, for any reason.

## The percentage is pooled, not averaged

`percent = sum(covered) / sum(total) * 100`, computed once across every qualifying file
together — not the mean of each file's own percentage. Those two formulas give materially
different answers from the same report, and the gap widens exactly where it matters most: once
a zero-scored absent file enters the mix, a mean weights a ten-line file the same as a
thousand-line one, so one small untested file can swing the average far more, or far less, than
its actual share of the diff warrants. This gate's entire authority rests on the same report
producing the same number every time it's read; an unstated aggregation formula is a second,
silent way for two runs to disagree with each other, in addition to the zero-coverage rule.
Pool the raw counts first, divide once, at the end.

## The zero-coverage rule — read this before anything else

**A file in `changed_files` that does not appear in the report counts as ZERO coverage. It is
never treated as missing data, and it is never dropped from the calculation.** An untested new
file is the single most important thing this measurement exists to surface. Averaging it away —
whether by skipping it, by excluding it as "not in the report," or by computing the percentage
only over files the report happens to mention — is the one mistake that makes the entire
threshold meaningless: a run would report a healthy percentage precisely because the worst file
in the diff contributed nothing to it. If you compute a percentage while silently leaving out a
changed file the report never mentioned, you have produced fiction, not a measurement.

Concretely: for every path in `changed_files`, either find it in the report and use its real
covered/total (or killed/total) numbers, or, if it is absent from the report entirely, record it
in `files` with `covered: 0`. For `total`, do not write `0` — a `0/0` entry contributes nothing
to a `sum(covered)/sum(total)` aggregate and makes the file invisible again, exactly the outcome
this rule exists to prevent. It must appear in `files` with a real, nonzero `total` (see below
for how to establish one), or the percentage you return does not reflect this file at all. There
is no third option where the file is quietly skipped.

## Scope to the changed files

The threshold this feeds is diff-scoped, not repo-scoped. Compute the percentage across only the
files in `changed_files` that appear in the report, plus every `changed_files` entry absent from
the report per the zero-coverage rule above. A file present in the report but **not** in
`changed_files` is ignored entirely — it is not part of this diff and including it would dilute
the number in the other direction, hiding a weak changed file behind a well-tested unrelated one.

## Format is a hint, not a parser

`report_format` names the schema so you know roughly what to expect — verity ships no parser and
no adapter list for report formats, and none is needed here. Read the file yourself and extract
per-file numbers regardless of whether its actual shape matches the label exactly; a mislabeled
or slightly-off-spec report is still readable by inspection even though no fixed parser would
accept it.

For a **coverage** report (`report_kind: "coverage"`): locate each file's element and read its
line-level hit counts to get `covered` (lines actually hit) and `total` (lines counted as
coverable) for that file.

For a **mutation** report (`report_kind: "mutation"`): locate each file's element and read
`covered` as mutants killed and `total` as mutants generated for that file. In addition — and
this matters more than the score itself — collect **every surviving mutant**: its location and
its mutator name. Survivors are what seed the next iteration's audit brief; a mutation score
with no survivor list gives the next auditor nothing to act on.

**A survivor's location is `mutant_line` in `file:line` form, never a bare line number.**
Carry-forward passes surviving mutants on to the next `auditing-test-gaps` dispatch as `suite`,
`mutant_operator`, `mutant_line` — and that auditor is told to read the code at `mutant_line` to
turn it into a real finding. A bare line number, on its own, does not name a file; the auditor
would have nothing to open. Emit `mutant_line` as `<repo-relative path>:<line>`, matching the
`file:line` convention `prior_defect_location` already uses elsewhere in the brief schema, so
the file identity survives the hop from this dispatch into the next audit instead of being
silently dropped partway through the loop.

## Report parse failures honestly

If the report is missing, empty, truncated, or in a shape you genuinely cannot read after
looking, do not guess. Set `percent` to `null`, leave `files` empty (or as far as you got, if
partially readable), and set `parse_status` to a specific, factual description of what you found
— "file does not exist at report_path," "file exists but is zero bytes," "file exists but is not
well-formed and stops mid-record," not a vague "could not parse." Never estimate a number from a
stdout summary line, a partial read, or a prior iteration's figure. The conductor's response to a
null `percent` is to disable that threshold for this suite and say so plainly to the user — that
is the correct outcome. A guessed number instead silently gates a real decision on fiction, which
is strictly worse than admitting the report couldn't be read.

## An absent file's denominator: use its line count, and say so

A file in `changed_files` but missing from the report has no killed/covered or total you can
read off the report — that number has to come from somewhere else. Use the file's own line
count. This is not unit-consistent with the report's own `total` for files it does mention: a
report's "coverable lines" excludes blanks and comments, while a raw line count doesn't, so the
absent file's denominator is somewhat larger than a report-derived one would have been. State
that plainly rather than hiding it — note in your reasoning (not in `parse_status`, which is
for report-level failures) that this file's `total` is a line count, not a coverable-line count.
The direction of that bias is the safe one for a gate: a larger denominator makes the file's
contribution read as *less* covered, never more. Biasing the other way — a smaller invented
denominator that flatters an untested file — is the failure mode to avoid; this one errs toward
suspicion instead, which is the correct default when nothing tested the file at all.

## Sanity-check yourself before returning

Before you return, verify all four:

- `percent`, if not `null`, is between 0 and 100.
- `files` is non-empty whenever `percent` is non-null — a non-null percentage with no files
  behind it cannot be justified.
- Every entry in `changed_files` is present in `files` — **but only whenever `percent` is
  non-null.** On a parse failure this check does not apply: a truncated report can legitimately
  yield a partial `files` list, and there is no way to "fix" a read that a truncated file has
  already made impossible. Return whatever you got, with `percent: null` and a `parse_status`
  that says the report was incomplete — don't loop trying to complete an unreadable file.
- **`files` contains nothing outside `changed_files`.** This is the check that catches the
  opposite failure from the zero-coverage rule: a measurer that folds in every file the report
  happens to mention, not just the changed ones, dilutes the number with unrelated, probably
  well-tested code and would otherwise pass every check above while making the gate meaningless
  in the other direction. Nothing above this line would catch that mistake by itself.

If percent-non-null checks fail, you have a bug in your own extraction — go back and fix the
count rather than returning a value that fails its own check.

## Return format

```json
{
  "scope": "changed-files",
  "suite": "<from dispatch>",
  "kind": "coverage | mutation",
  "percent": 0,
  "files": [
    { "path": "<repo-relative path>", "covered": 0, "total": 0 }
  ],
  "survivors": [
    { "mutant_line": "<repo-relative path>:<line>", "mutant_operator": "<mutator name>" }
  ],
  "parse_status": "ok | <specific description of the failure>"
}
```

`percent` is the **pooled** `sum(covered) / sum(total) * 100` across the `files` array, never a
mean of per-file percentages. `percent` is `null`, never a number, when `parse_status` is
anything other than `ok`. `survivors` applies only when `kind` is `mutation`; omit it (or leave
it empty) for a coverage dispatch. Every `survivors` entry's `mutant_line` is `file:line` —
never a bare line number — so the next audit can open the file it names. A zero-coverage entry
from the rule above is a normal member of `files`, not a special case — it carries the same
`{path, covered, total}` shape as every other entry, just with `covered: 0`.

## Red flags — STOP

- Estimating a percentage from a summary line, a log, or stdout instead of the report file.
- Leaving a `changed_files` entry out of `files` because it wasn't in the report.
- Excluding a changed file from the percent calculation instead of scoring it zero.
- Averaging per-file percentages instead of pooling `sum(covered) / sum(total)`.
- Including a file in `files` that isn't in `changed_files` — even one dilutes the number.
- Returning report contents — snippets, raw XML/JSON, file bodies — instead of numbers.
- Averaging or blending across suites; you were dispatched for exactly one.
- Returning a non-null `percent` alongside a `parse_status` that isn't `ok`.
- Returning a mutation dispatch with a score but no `survivors` list.
- Emitting a survivor's location as a bare line number instead of `file:line`.
- Recording an absent file as `total: 0` — that makes it a `0/0` no-op instead of a zero that
  actually drags the percentage down.
- Requiring every `changed_files` entry to appear in `files` even on a parse failure, instead of
  scoping that check to `percent` non-null.
