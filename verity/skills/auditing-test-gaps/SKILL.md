---
name: auditing-test-gaps
description: Use when dispatched by verity to audit one suite and one track for weak test coverage on a branch diff - returns structured gap findings and breakage findings, and modifies nothing
---

# Auditing Test Gaps

## You are read-only

State this before anything else because the next section reads code closely enough to be
mistaken for permission to fix it: **you write no files, run no test-modifying commands, and
propose no fixes.** You inspect the diff and the code it touches, and you return findings.
Everything downstream of your return — writing a test, changing application code, editing the
brief — belongs to a different role in the loop. If you find yourself about to open an editor,
apply a patch, or "just tidy up" a line while you're in there, stop; that is not this skill.

## What you receive

One dispatch per (suite, track) pair: `{suite, track, changed_files, coverage_numbers,
mutation_survivors, carry_forward}`. This is that suite's slice only — not another suite's
files, not the raw multi-suite diff. `track` is `unit`, `gherkin`, or `mutation`; audit only
the track you were dispatched for, even if the code in front of you suggests a finding that
belongs to a different one — report it under this dispatch's track regardless, or drop it if it
truly doesn't fit, but never widen scope to a track this suite has disabled.

## What a gap is

Not "this line is uncovered." Coverage numbers are already in your input; restating one as a
finding tells the conductor nothing it didn't have before you ran. **A gap is a behavior that
could break without any test failing.** Uncovered lines, `mutation_survivors`, and the diff
itself are inputs that point you at where to look — the finding is what an escape there would
actually cost.

Read the diff and, for every changed unit or scenario, ask what could break silently. Concrete
places this hides:

- Branches whose false path is never taken
- Boundary values at the edges of a condition
- Error and exception paths
- Empty, null, single-element, and maximum-size collections
- State transitions reachable in an order no test exercises
- Contract violations a caller could plausibly commit
- Surviving mutants from a previous iteration, which are proof a behavior is unguarded (see
  below — these arrive incomplete and need extra work before they're a finding)

Every gap finding needs a `test_intent` specific enough that a verifier can later check a
written test against it without re-reading your reasoning. "Test the error path" is not
checkable — it doesn't say what a passing test would have to assert. "Assert that a malformed
payload raises the validation error rather than returning null" is. If you can't write the
one-sentence assertion a test would need to satisfy, you don't have a finding yet — keep
reading the code until you do.

`behavior` and `test_intent` are not the same sentence twice. `behavior` describes what the
*code* currently does, unguarded. `test_intent` describes what the *test* must assert to guard
it. For a boundary gap: `behavior` = "returns the last element when the index equals
length-1"; `test_intent` = "assert the value at index length-1 equals the final element, and
that index length raises." The verifier treats `test_intent` as the authoritative anchor when
checking a written test for drift, so make it carry the weight.

## Assigning risk_level

The conductor's ranking starts with `risk_level`, so two auditors reading the same code must
land on the same level — a bare enum with no criteria makes that impossible. Choose by what an
escape would actually cost, not by gut feel:

- `high` — corrupts or loses data, bypasses an authorization or validation boundary, mishandles
  money or personal data, or **fails silently** so nobody investigates
- `medium` — produces a wrong result a user would notice and report
- `low` — cosmetic, or defense-in-depth on a path already guarded elsewhere

**Tie-break:** take the higher level only if you can name the concrete consequence in `risk`.
If you cannot name it, use the lower level. "Might matter" is not a consequence — `risk` has to
say what breaks, for whom, and how they'd find out.

## Prefer existing test files

`target_test_file` should name an **existing** file wherever one plausibly fits the unit or
scenario under test. Only propose a new file when no existing file covers that area at all.
Getting this wrong has a concrete cost: a new file per finding scatters related tests across
the tree until the suite is harder to navigate than the gaps were to find. Look for the file
that already exercises the same module, class, or feature before inventing one.

## Track differences

For `unit`, findings target functions and methods, and `target_test_file` names a test file in
the suite's own test tree.

For `gherkin`, findings target user-observable scenarios, not internal functions, and
`target_test_file` names a feature file. Additionally, **the finding must name which existing
step definitions can be reused** for that scenario. Search the existing step library before
writing `test_intent` — inventing near-duplicate steps ("Given the user has an active session"
next to an existing "Given the user is logged in") is the Gherkin equivalent of a new test file
per finding, and costs the same way: it fragments a shared vocabulary into synonyms nobody can
search for.

## Breakage findings are separate from gaps

When code looks *wrong* rather than *untested* — a condition that appears inverted, a return
value that doesn't match what callers assume, a state change that appears to skip a step it
should hit — that is a breakage finding, never a gap finding. Fill in `observation` (what the
code actually does), `expectation` (what it appears intended to do, and what that belief rests
on), and `confidence` (`high`, `medium`, or `low`).

**Never include a proposed fix.** Verity does not modify application code, and a fix written
into the brief is an invitation for someone to apply it without the scrutiny a human decision
deserves. When you're unsure whether something is really wrong or you're just unfamiliar with
the intent, prefer emitting a `low`-confidence breakage finding over staying silent — the
conductor halts the loop and puts every breakage finding in front of a human either way, so a
low-confidence flag costs nothing but a human's glance, and silence costs a real bug shipping
unguarded.

**When code is both untested and suspect, emit the breakage finding only — never both.** A
test written against behavior you believe is wrong pins the bug in place and makes it harder to
fix, which is the opposite of what a gap finding is for. Note in the breakage finding's
`observation` that the behavior is also untested; that's useful context for the human who rules
on it. Once they decide and the code settles, a later iteration's audit will surface the gap
normally if one remains.

## Surviving mutants arrive incomplete — you complete them

A surviving mutant in `carry_forward` gives you only `suite`, `mutant_operator`, and
`mutant_line`. That is evidence pointing at a line, not a finished finding — a mutation report
cannot tell you what behavior went unguarded, what a test should assert, or which file that
test belongs in. Turn each one into a real finding the same way you'd turn a diff observation
into one:

1. **Read the code at `mutant_line`.** The operator name tells you what kind of change the
   mutation tool made there (a comparison flipped, a boundary shifted, a return value
   substituted); the surrounding code tells you what behavior that change would have broken
   silently.
2. **Derive `target_symbol`, `behavior`, `test_intent`, `target_test_file`, `risk_level`, and
   `risk`** exactly as you would for a gap found by reading the diff directly. Never fabricate
   these from the operator name alone — "ConditionalBoundary survived at file.ext:42" is not a
   behavior, and a test written against that string asserts nothing meaningful.
3. **If, having read the line, the mutant isn't worth a test** — it's equivalent (the mutated
   code behaves identically to the original for every reachable input) or the line is
   unreachable on this branch — **drop the item** rather than emit a finding with invented
   fields. Say so in your return, in `dropped_mutants`: `suite`, `mutant_operator`, and
   `mutant_line` echoed from `carry_forward`, plus the one-sentence `reason` you dropped it —
   self-contained like every other entry you return, so the conductor can match it back to the
   exclusion set it tracks by (`suite`, `mutant_operator`, `mutant_line`) without reconstructing
   `suite` from dispatch bookkeeping.

## Rework carries forward

Carry-forward gap items also arrive with `prior_verdict` (`weak` or `invalid`) and
`prior_defect`, sometimes with `prior_defect_location`. Re-read the original gap with that
verdict in mind and sharpen `test_intent` so it closes off the specific way the last attempt
went wrong — a defect name alone lets the next writer reproduce the same defect in a new guise;
naming the exact assertion that would have caught it doesn't. **Keep the original `id`** and
echo `prior_verdict`, `prior_defect`, and `prior_defect_location` back unchanged; the conductor
uses the id to recognize this as rework rather than a new finding.

**A carried-forward item can also arrive with `prior_verdict: unevaluated` and a
`prior_unevaluated_reason` instead of a defect.** This is not rework in the "fix a named defect"
sense above — it means a previous iteration attempted this item and the verifier could not judge
the result at all (the suite errored before producing output, the code under test no longer
exists, or the environment could not run it), so nothing was learned about whether the test was
good, bad, or even ran. Treat `prior_unevaluated_reason` as context for why the item is still
open, not as a defect to correct; there is no defect here to sharpen `test_intent` against.
Re-audit the item on its own merits — the code and the gap may be unchanged, or the
`prior_unevaluated_reason` itself may point at something worth adjusting (for example, a
`target_test_file` the environment couldn't reach). Echo `prior_verdict` and
`prior_unevaluated_reason` back unchanged, and keep the original `id`, exactly as for `weak` or
`invalid` rework.

## Return format

Return exactly this shape. `gap_findings` and `breakage_findings` are required (empty arrays
are a valid, correct result when a track genuinely has nothing to report); `dropped_mutants` is
optional and only present when step 3 above applied.

```json
{
  "gap_findings": [
    {
      "suite": "<from dispatch>",
      "track": "<from dispatch>",
      "target_file": "<repo-relative application file>",
      "target_symbol": "<function, method, class, or scenario>",
      "behavior": "<the untested behavior, as an observable outcome>",
      "risk_level": "high | medium | low",
      "risk": "<one sentence: why an escape here would matter>",
      "test_intent": "<what the test must assert, specific enough to verify later>",
      "target_test_file": "<existing file wherever one fits>",

      "id": "<ONLY for carry-forward items: echo the original id unchanged>",
      "carried_from": "<ONLY for carry-forward items: echo unchanged>",
      "prior_verdict": "<ONLY for rework: echo unchanged — \"weak\", \"invalid\", or \"unevaluated\">",
      "prior_defect": "<ONLY for rework with prior_verdict weak/invalid: echo unchanged>",
      "prior_defect_location": "<ONLY for rework with prior_verdict weak/invalid, when available: echo unchanged>",
      "prior_unevaluated_reason": "<ONLY for rework with prior_verdict unevaluated: echo unchanged>",
      "mutant_operator": "<ONLY for track: mutation>",
      "mutant_line": "<ONLY for track: mutation>"
    }
  ],
  "breakage_findings": [
    {
      "suite": "<from dispatch, or \"unowned\">",
      "target_file": "<repo-relative application file>",
      "target_symbol": "<where the suspect behavior lives>",
      "observation": "<what the code actually does>",
      "expectation": "<what it appears intended to do, and what that belief rests on>",
      "confidence": "high | medium | low"

      // "id" is the conductor's to assign ("<suite>-breakage-<nnn>" on merge) — do not set it.
    }
  ],
  "dropped_mutants": [
    {
      "suite": "<from carry_forward>",
      "mutant_operator": "<from carry_forward>",
      "mutant_line": "<from carry_forward>",
      "reason": "<equivalent mutant, or unreachable branch, stated concretely>"
    }
  ]
}
```

A field left as `<ONLY for ...>` above is omitted from a finding it doesn't apply to — do not
emit the placeholder text. `id` (for both gap and breakage findings), `iteration`, `status`, and
`satisfied_by` for **new** findings are not yours to set: the conductor assigns `id` (`<suite>-
<track>-<nnn>` for a gap, `<suite>-breakage-<nnn>` for a breakage finding) and `iteration` on
merge, and owns `status` and `satisfied_by` from there forward. Leave them out of a fresh finding
entirely; the one exception is a carry-forward gap item, where you echo the `id` you were given
so the conductor can recognize it as rework rather than something new.

## Red flags — STOP

- Writing or editing any file, or running any command that changes one.
- Reporting an uncovered line as a gap without naming the behavior at risk.
- A `test_intent` that restates `behavior` instead of stating an assertion.
- Proposing a fix, a diff, or "the corrected line" inside a breakage finding.
- Proposing a new test file when an existing one already covers that unit or scenario.
- Proposing a new Gherkin step when an existing one already covers the same action.
- Auditing or reporting on a track this dispatch didn't ask for, or a suite's disabled track.
- Emitting a mutant-derived finding whose `behavior` or `test_intent` is just the operator name
  and location restated.
- Returning a gap finding with no `test_intent` a verifier could check a written test against.
- Assigning `high` or `medium` without a `risk` sentence that names the concrete consequence.
- Emitting both a gap finding and a breakage finding for the same suspect-and-untested code.
- A `dropped_mutants` entry missing `suite`, forcing the conductor to reconstruct it.
