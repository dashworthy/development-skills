---
name: conducting-test-hardening
description: Use when implementation work is finished and about to be handed off - before opening a pull request, merging a branch, declaring work complete, or wrapping up when the user asks to move on. Also applies when tests already pass but nobody has checked whether they would fail if the behavior broke, when self-reviewing a diff before handoff, or when skipping testing because the change felt small or time was short.
---

# Conducting Test Hardening

## The Iron Rule

> Verity writes tests. It never modifies application code, and it never rewrites an existing
> test case. When code appears wrong, it halts and hands the decision to the user. Violating
> the letter is violating the spirit.

Every step below is written to serve this rule, not the other way around. When an instruction
and the Iron Rule appear to conflict, the Iron Rule wins and the run halts.

**Ask, don't configure.** There is no file anywhere declaring suites, paths, commands,
thresholds, or a loop limit for this project. Anything that information used to live in gets
derived from git and the project itself, or asked of the user, fresh, every run. Never write a
config file to save yourself asking next time — that file, and the defects it produced, are why
this run works the way it does now.

## Why this runs now

Nothing forces this skill to run. There is no hook that blocks finishing a branch without it —
the only thing standing between "done" and "actually done" is whether this fires at the moment
above, on its own, before anyone asks for it by name. If a reason not to run it just occurred to
you, it is almost certainly one of these:

| Excuse | Reality |
|---|---|
| "I'll run it after this" | After this becomes after the PR, after merge, after it's forgotten. The diff in front of you right now is the one this audits — run it before that diff moves. |
| "The change is too small to bother" | Small diffs are exactly where a missing test costs least to write and most to skip silently — nobody re-reviews a two-line change for what it forgot to guard. |
| "The user is in a hurry" | A hurried user asked for the task finished, not for the testing step quietly dropped. Say what you're about to run and why, then run it. |
| "The tests already pass" | Passing proves nothing about whether they'd fail if the behavior broke. That gap is the entire reason this skill exists. |
| "There's no test suite here" | Then say so once detection confirms it, and ask what to run. An unconventional project is a normal preflight outcome, not a reason to skip the audit. |
| "I already reviewed it myself" | Self-review isn't adversarial. A fresh audit with no investment in the code catches what your own confidence in it papers over. |
| "It's just a refactor, behavior shouldn't have changed" | Refactors are exactly where behavior silently changes. If it truly didn't, the tests confirm that quickly and cheaply. |
| "I'll just mention the gap in my summary" | Naming a gap in prose hands the user a to-do item, not finished work. They asked for the tests, not a note that some are missing. |

## Context discipline

The conductor holds this run's briefs, verdicts, and numbers. It does **not** read diffs or test
bodies, and it holds no config — there isn't one to hold. Every step that needs to read a diff,
a test body, a stack's file tree, or a report file is dispatched to a subagent that returns a
verdict, a count, or a finding — never the raw text. This is what keeps iteration N+1 as cheap as
iteration 1: the conductor's own context grows by a few brief entries and a handful of numbers
per iteration, not by the diff and every test file and report it has ever looked at.

Three named skills get dispatched by name over the course of a run: `auditing-test-gaps`,
`writing-tests-from-brief`, `verifying-test-integrity`. Two more dispatches follow a **reference
document** instead of a skill name, because the work they do (scanning a tree for manifests, or
reading a coverage or mutation report) belongs out of the conductor's context but isn't its own
reusable skill: hand a subagent `references/detecting-the-stack.md` for stack detection, or
`references/measuring-reports.md` for turning a report into numbers, as its complete brief, and
take back only what each document's own return format specifies.

The one exception to "never read a diff" is mechanical, not analytical: when reconciliation
halts, it surfaces the touched paths and their diff to the *user* as evidence. The conductor
relays that text; it does not reason over its contents to decide anything. Deciding what a diff
means is always someone else's job — `auditing-test-gaps` for changed application code,
`verifying-test-integrity` for written tests.

## Preflight

1. **Establish the baseline.** Try `git symbolic-ref refs/remotes/origin/HEAD` first; if that
   fails (no remote, or it isn't set), probe local branches named `main`, `master`, then `trunk`
   in that order. Whichever way it's inferred, **confirm it with the user** before using it —
   don't run a diff against a guessed baseline just because the guess was confident.
2. **Detect the stack.** Dispatch a subagent with `references/detecting-the-stack.md` as its
   full brief. It returns candidate suites with their commands, paths, tracks, and an evidence
   trail — never a raw tree listing. **When it cannot infer a command, or the tree has no
   manifest, CI file, or runner config at all, ask the user directly** — for exactly the fields
   it couldn't derive (what runs the suite, what runs one test in isolation, what emits coverage
   and where the report lands, what counts as application code versus tests). That is a normal
   path through preflight, not a failure state; treat any evidence-backed answer the subagent did
   find as confirmed unless the user corrects it, and treat every gap it left as a question, not
   a guess you fill in yourself.
3. **Compute the diff scope.** `git diff --name-only <base>...HEAD` for committed changes, plus
   uncommitted changes and untracked files, excluding `.verity/`. Route each changed file to a
   suite by the paths confirmed in step 2; a file matching no suite's application paths becomes
   an ownership finding for iteration 1's brief rather than being silently dropped or guessed at.

   Reconciliation takes its own snapshot immediately before each write phase — see the loop's
   Write step. Do not take one here: a snapshot from this point would predate the suite runs in
   steps 5 and 6, whose coverage files, caches and reports would then read as unexplained new
   paths at the first reconcile.
4. **Stop if nothing participates.** If no suite owns a changed file, say so plainly and stop —
   there is nothing to harden.
5. **Require a green suite.** Run each participating suite's test command. State why explicitly:
   with pre-existing failures, a failure surfacing later in the loop cannot be attributed to a
   test verity just wrote — the signal the whole loop depends on is gone from the first
   iteration. On any failure, stop and list exactly which suites failed and how. This step
   doubles as validating the commands step 2 produced; a command that errors out entirely (not
   merely red) means detection got it wrong, and the fix is to ask the user for the right one,
   not to guess a variant.
6. **Measure the baseline.** Dispatch a subagent with `references/measuring-reports.md` as its
   brief, once per participating suite, to capture coverage (and mutation, where that track is
   enabled) before any test is written. Without a baseline, "no improvement" has nothing to
   compare against. A suite with no coverage or mutation command at all simply has nothing to
   measure here — note that plainly and carry on; see **Thresholds that cannot be measured**
   below for how that plays out at the end.
7. **Ask whether to write tests at all.** Offer both modes explicitly, because the user cannot
   pick an option nobody told them exists: the full run, which audits and then writes tests to
   close what it finds, or **audit-only**, which produces the brief and stops before any test is
   written. Audit-only is the right call more often than it sounds — when the user wants to see
   the gaps before committing to filling them, when they want to write the tests themselves, or
   when they are deciding whether the diff is even ready. Default to the full run if they have no
   preference. If they choose audit-only, the loop exits after the brief and the breakage check;
   skip the threshold question entirely, since nothing will be measured against it.
8. **Agree the thresholds and the iteration cap.** Ask the user, or offer defaults and let them
   accept or override: 80% coverage and 3 iterations are reasonable starting points. Apply the
   agreed coverage threshold to every participating suite — suites are still evaluated
   separately and never blended into one figure, they just share the same bar unless the user
   asks for something suite-specific. If any participating suite has a mutation track enabled,
   ask separately whether to gate on a minimum mutation score at all; mutation gating is opt-in,
   not assumed, since plenty of projects have no mutation tooling worth gating on. None of this
   gets written anywhere for next time — ask again next run.

## The loop

Repeat the following per iteration until an exit condition is reached.

- **Audit.** For every (suite, track) pair confirmed in preflight, dispatch one
  `auditing-test-gaps` agent, in parallel, per `superpowers:dispatching-parallel-agents`. Pass
  each agent only that suite's slice: its changed files, its current report numbers, and its
  carry-forward from the previous iteration — never another suite's data, and never the raw diff
  beyond what that one suite owns.
- **Merge.** Dedup incoming findings by (`target_file`, `behavior`). Assign each new item an
  `id` of the form `<suite>-<track>-<nnn>` (`unowned-ownership-<nnn>` for ownership findings,
  `<suite>-breakage-<nnn>` for breakage findings) and set its `iteration` to the current
  iteration number. A carried item keeps its **original** `id` and gains `carried_from` naming
  the iteration it first appeared in — never a new id, or the conductor loses the ability to
  tell rework from new work. Rank gap findings with the brief schema's total order: `risk_level`
  (high, medium, low), then rework items before fresh ones within a level, then `target_file`
  ascending, then `id` ascending — in that order, with no step skipped, so two runs over the
  same findings render an identical brief. Write `.verity/briefs/<n>.md` from
  `references/brief-template.md`.
- **Halt on breakage.** If the brief contains any breakage finding, present every one to the
  user and STOP — before any writer is dispatched. This is unconditional; there is no setting
  that turns it off. Never write a test that pins in behavior a breakage finding flags as
  suspect, and never fix the flagged code — that decision belongs to the user.
- **Audit-only exit.** If preflight step 7 settled on audit-only — or the user asks for one at any
  point before the write phase — stop here: after
  the brief is written and the breakage check has run, before Write. Report the brief as this
  run's output and exit `audit-only`. This exit is neither pass nor failure: it does not
  increment or reset the dry counter and it does not write any test.
- **Dry check.** An empty brief (no gap, breakage, or ownership findings) increments a dry
  counter; two consecutive empty briefs exits `dry`. Any non-empty brief resets the counter to
  zero.
- **Snapshot, then Write.** **Immediately before dispatching any writer this iteration**, record
  `git diff --numstat HEAD` (per-file added/deleted counts) and `git status --porcelain` (for the
  untracked files numstat does not cover). This is the only baseline reconciliation compares
  against, and it is taken fresh every iteration — never once for the whole run. Everything that
  happened earlier is therefore already in it: the user's own uncommitted work, the coverage files
  and caches left by preflight's suite runs, and the tests, reports and artifacts produced by
  previous iterations. A run-scoped baseline would flag all of that as unexplained and halt on
  iteration 2.

  Use numstat, not `git status` alone, and the reason is not stylistic: a porcelain entry for an
  already-modified file reads ` M path` both before and after a writer appends to it — byte for
  byte the same — so a status-only baseline cannot see a writer editing a file that was already
  dirty. Those are exactly the files a writer is most likely to reach for. Numstat moves
  (`1 0 app.py` → `2 0 app.py`) and catches it.

  Then: group open and rework gap findings by `target_test_file`. Dispatch one
  `writing-tests-from-brief` agent per distinct target file, each carrying only the findings for
  that file. Never dispatch two writers at the same target test file — that is a race on the
  same file with no defined winner.
- **A writer may return a breakage finding of its own.** When any writer does: halt the run
  immediately, present it alongside any tests already written by other writers in the same
  phase, and do not proceed to Reconcile, Verify, or Measure. This is a writer telling you a test
  cannot be written without changing application code — precisely the case the run must stop
  for.
- **Reconcile.** This step is now the *only* thing standing between a dispatched agent and
  application code — there is no hook watching what gets written while a writer runs. Treat it
  accordingly:

  1. Compare against **this iteration's pre-write snapshot** — the one taken in the Write step
     moments ago — not against a clean tree, and compare *content counts* rather than status
     entries. Verity runs on work in progress, so uncommitted application changes are the normal
     starting state and not evidence of anything; and by now the tree also carries caches, coverage
     files and reports from every suite run so far. All of it is already in that snapshot. Run both
     measurements again and collect a path as **touched** when either holds:
     - it is absent from the snapshot entirely — it did not exist, or was clean, when this
       iteration's writers were dispatched; or
     - its added or deleted line counts **differ from the snapshot's counts** — it was already
       there, and something has changed it since.

     A file whose counts are identical is untouched by this write phase and is not a violation.
     Flagging those would halt nearly every real run on its first reconcile.

     **Do not substitute `git status --porcelain` for the count comparison.** Its entry for an
     already-modified file reads ` M path` both before and after a writer appends to it — byte
     for byte the same — so a status-only comparison silently passes a writer editing a file the
     user had already touched, which is the likeliest escape there is. The counts are what make
     this check real.
  2. Resolve every touched path, and every symlink found under a suite's test area, to its real
     location before comparing anything: `readlink -f <path>`, or where that's unavailable,
     `cd "$(dirname <path>)" && pwd -P` joined back with the basename. A symlink that sits inside
     an allowed test location but resolves to a target outside it is a violation on its own,
     whether or not anything has been written through it yet — its existence is the escape.
  3. Compare each resolved path against the test and fixture locations confirmed during stack
     detection (each participating suite's own test root, any harness scripts the user named as
     part of the test surface, and this run's own `.verity/briefs/`). Anything whose resolved
     location falls outside all of those HALTS the run: present the offending paths and their
     diff to the user and stop.
  4. Check the touched pre-existing test files for a rewrite rather than an append, using **the
     same snapshot step 1 used** — one measurement answers both questions. Step 1 asks "did
     anything change outside the test surface"; step 4 asks "did a test file *lose* lines". Compare
     each touched test file's deleted-line count against its snapshot value. A
     file is a violation only when its count **rose** relative to its own baseline — lost lines
     this run, a rewrite of an existing test case, not the append-only edit the Iron Rule
     requires. HALT the same way.

  **Never auto-revert either kind of violation.** Reverting is destructive and the conductor
  cannot know whether the violation is a bug worth diagnosing or evidence the user needs to see
  intact. Surfacing it and stopping is the correct action.
- **Verify.** Dispatch `verifying-test-integrity` with the new test names, their suite, and the
  `test_intent` and `behavior` of each brief item they claim to satisfy. From its returned
  verdicts, update each claimed item:
  - `valid` → `satisfied`, with `satisfied_by` set to the test names.
  - `weak` and `invalid` → `rework`, carrying forward `prior_verdict`, `prior_defect`, and
    `prior_defect_location` from the verifier's return so the next audit knows exactly what
    went wrong.
  - `unevaluated` → stays `open`, carrying forward `prior_verdict: unevaluated` and the
    verifier's stated reason as `prior_unevaluated_reason`. This is not a defect and not a
    pass — the suite errored before producing output, the code under test no longer exists, or
    the environment could not run it. A verifier that cannot judge a test must say so rather
    than fabricate `weak`/`invalid`/`valid`, and the conductor must not resolve that absence of
    judgment on its behalf by picking a side.

  Items no writer or verifier touched this iteration stay `open`.
- **Measure.** Per participating suite: run the test command again (green required), then the
  coverage command, then the mutation command where that track is enabled. If a mutation run
  stalls or the environment kills it before it finishes, skip that suite's mutation gate for
  this iteration and record it rather than either stalling the loop or silently counting it as a
  pass. Dispatch a subagent with `references/measuring-reports.md` per suite to turn the raw
  reports into numbers. Keep every suite's numbers separate; never blend them into one figure.
- **Decide.** Evaluate the exit table below against this iteration's numbers.

## Degraded conditions

Each of these is reported in the iteration's output, never silently absorbed into a pass.

| Condition | Response |
|---|---|
| A dispatched agent dies or returns nothing | Retry once. On a second failure, treat that track as empty for this iteration and say so in the report. It does NOT count as passing, so a run cannot reach `pass` where a (suite, track) auditor died twice in a row. |
| A suite's test command turns out not to run in this environment | Skip that suite with a loud note. It does NOT count as passing, so a run cannot reach `pass` while a participating suite was skipped. |
| A coverage or mutation command doesn't exist, or its report won't parse | That threshold disables for that suite; report which one and why — see Thresholds that cannot be measured. |
| A mutation run stalls or is killed before finishing | Skip that gate for the iteration; report it. |

## Exit conditions

| Exit | Condition |
|---|---|
| `pass` | Every participating suite meets the agreed coverage threshold (and mutation threshold, if one was agreed) on numbers that were actually measured this run |
| `dry` | Brief empty for two consecutive iterations |
| `cap` | The agreed iteration cap is exhausted with thresholds unmet |
| `halt` | Breakage finding, reconciliation violation, or no improvement |
| `audit-only` | The user asked for an audit without writing tests |

`audit-only` is decided immediately after the brief and the breakage check, not by this Decide
step at the end of the iteration — see the loop's Audit-only exit.

Thresholds are evaluated **per suite, never blended** — a strong suite cannot cover for a weak
one, and a run cannot report `pass` on an average.

**Thresholds that cannot be measured.** If a coverage or mutation command doesn't exist, or its
report won't parse, say so plainly and do not gate that suite on it — a run that reports success
while measuring nothing is the false green this whole tool exists to prevent. A `pass` reached
this way must name, explicitly, every suite and metric that was excluded from gating rather than
folding silently into "every participating suite passed."

**A missing tool is not an unmeasurable threshold.** Separate the two, because they call for
opposite responses. *The project has no coverage command* is a fact about the project — disable
that gate and report it. *The report exists but the tooling to read it is absent* — most often
`jq`, which the agents parsing coverage and mutation reports rely on — is a fixable problem on
this machine, and silently disabling the gate turns a one-line install into a permanently weaker
run that still reports `pass`. When a report exists and cannot be read for want of a tool, say
which tool, say how to install it, and ask whether to continue with that gate disabled or stop so
the user can install it. Never fold it into "the report won't parse."

**"No improvement" means**, across all participating suites in this iteration: coverage did
not rise, mutation score did not rise, AND the verifier returned no new `valid` tests. Any one
of those three moving in any suite is progress; continue the loop. Only when all three are flat
everywhere does this iteration count as no improvement, which halts.

`unevaluated` counts toward **neither** term — not the satisfied set, not the "new `valid`
tests" count. Treating it as satisfied would claim a gap is closed when nobody said so;
treating it as a defect would claim the test is bad when nobody said that either — it is an
absence of judgment, not a verdict, and the loop carries it forward rather than resolving it
either way. Consequently, an iteration that produces only `unevaluated` verdicts and no
coverage or mutation movement counts as no improvement and halts, exactly like an iteration
that produced nothing at all — it must not loop forever re-attempting tests nobody can judge.

## Carry-forward

Surviving mutants, `weak` and `invalid` verdicts, and unsatisfied (`open` or `rework`) brief
items become the next iteration's audit input. That `open` set includes items no writer or
verifier touched this iteration **and** items a verifier returned `unevaluated` — an attempted,
unjudged item carries forward exactly like an untouched one, plus the verifier's stated reason
so the next audit knows a prior attempt didn't resolve it. They keep their original `id`s and
gain `carried_from`. A surviving mutant carries forward only `suite`, `mutant_operator`, and
`mutant_line` (`file:line`, never a bare line number) — the next `auditing-test-gaps` dispatch
reads the code at that line and derives `target_symbol`, `behavior`, `test_intent`,
`target_test_file`, `risk_level`, and `risk` itself, or drops the item and says why if the
mutant is not worth a test.

An auditor may return `dropped_mutants` — mutants it read and judged not worth a test because
they are equivalent or the branch is unreachable. Record each as (`suite`, `mutant_operator`,
`mutant_line`) in a **run-scoped set**, and never pass one in that set to another audit for the
rest of the run. This is not optional bookkeeping: surviving mutants are re-derived from the
mutation report every iteration, not read from a stored list, and an equivalent mutant survives
every run *by definition* — without this set, the same mutant gets re-dispatched, re-read, and
re-dropped on every remaining iteration, spending an audit on a foregone conclusion each time.
Log the run-scoped dropped set in the final report, so the user can see which mutants verity
decided not to chase and why.

## Reporting, always

Whichever exit is reached, report it plainly, together with:

- The actual per-suite numbers, alongside the command output that produced them — never a
  summary of a summary, and never a threshold claimed met without the run that proved it.
- Every suite or metric named in **Thresholds that cannot be measured**, so a `pass` never reads
  as stronger than what was actually checked.
- The run-scoped dropped-mutant set from Carry-forward, so the user can see what verity decided
  not to chase.
- Any degraded condition hit along the way (a dead auditor, a skipped suite, a stalled mutation
  run) and what it means for whether `pass` was reachable at all.

Then invoke `superpowers:verification-before-completion` before reporting anything as met. There
is no gate file to clear and no marker to remove — this run's briefs under `.verity/briefs/`
are left in place as the audit trail, and the next run asks its questions fresh rather than
reading anything back from this one.

## Red flags — STOP

- Reading a diff or a test body in the conductor's own context instead of dispatching it.
- Modifying application code for any reason, including to "just make the test pass."
- Writing tests when a breakage finding is open.
- Auto-reverting a reconciliation violation instead of surfacing it.
- Blending coverage or mutation numbers across suites into one figure.
- Reporting a threshold as met without the command output that proves it.
- Dispatching two writers at the same target test file.
- Continuing past the brief into Write when the user asked for an audit only.
- Reporting `pass` without naming every suite or metric that could not be measured.
- Proceeding to Reconcile, Verify, or Measure after any writer returns a breakage finding of its
  own in this iteration's Write phase.
- Marking an `unevaluated` item `satisfied` or `rework` instead of leaving it `open`, or
  counting it toward either side of the no-improvement check.
- Reporting `pass` for a run where a (suite, track) auditor died twice in a row, the same way a
  skipped suite blocks `pass` — an unaudited track is exactly the false green the gate exists
  to prevent.
- Inferring or hard-coding a threshold, a suite list, or a command instead of asking the user or
  deriving it from evidence.
- Writing a config file, a shell library, or a hook "to make this more reliable next time" —
  that is exactly the layer that was removed, and exactly what caused most of the defects.
