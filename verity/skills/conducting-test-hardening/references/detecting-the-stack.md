# Detecting the Stack

## Overview

This reference discovers *suites*, plural. A repository may run several independent test
harnesses — one per component, one per language, one per package in a monorepo — and each
one becomes its own candidate, never merged into a shared one. The job ends at a proposal: a
JSON object describing candidate suites and the evidence behind each field, returned to
whoever dispatched this work. It never writes anything — confirming the proposal with the
user, and validating it by running the commands, belongs to the dispatcher.

## The evidence hierarchy

This is the core of this reference. Four sources, strongest first. Consult them in order for
every field of every candidate suite. When two sources disagree on the same field, the
stronger source wins — but a strong source answering one field does not excuse skipping it
for another field the weaker source would otherwise have to supply. Record which source
produced every command and every path in the evidence trail; a command with no recorded
source is not evidence, it is a guess.

1. **Declared scripts in project manifests.** The commands the team actually runs day to
   day, usually already carrying the flags and paths that matter. This is the strongest
   evidence because it reflects what maintainers chose, not what a tool defaults to.
2. **CI workflow definitions.** The canonical invocation, and the best source for coverage
   flags and report output paths specifically — a CI pipeline that gates on a report or
   uploads one has to produce it, so the flag that writes a machine-readable file is
   usually already sitting in the workflow file even when it is missing from a manifest
   script.
3. **Runner configuration files.** Where report formats, output destinations, and test
   roots are declared for their own sake, independent of how they get invoked.
4. **`references/stack-markers.md`.** Consulted only when the first three sources yield
   nothing for a given suite or a given field. Everything it offers is a candidate
   requiring user confirmation, never a fact to assert outright.

## Discovering suite boundaries

Search the entire tree, not just the root — a monorepo's second harness lives in a
subdirectory a root-only search would never reach. One candidate suite per dependency
manifest or runner configuration file found anywhere in the tree; do not assume a
one-manifest, one-repository shape without checking.

For each candidate, derive `paths.app` and `paths.tests` from that runner's own configured
test roots and source roots — read its actual configuration rather than guessing from
directory names that merely look conventional. Two manifests of the same kind in different
directories are two suites, not one, even when they share a language or framework.

Compare every pair of candidate suites' `paths.app` globs against each other. Where two
overlap, this is a warning to surface, not a conflict to silently resolve by picking one —
overlapping ownership is exactly the ambiguity a clean suite boundary exists to avoid, and
guessing which suite should win hides a decision the user needs to make.

A tree with no manifest and no runner configuration anywhere yields zero suites. Say so
plainly. Do not manufacture a suite from a directory that merely contains source files —
that is not evidence of a runnable test command, and a suite with no evidence behind it is
exactly the failure this process exists to prevent.

## Naming suites

Duplicate suite names are a hard failure downstream, not a cosmetic annoyance — and the
monorepo case makes collisions likely: two suites of the same kind naturally attract the
same obvious name.

Derive the name from **where the suite lives, not what tool it runs**. A suite rooted at a
directory named `api` is `api`; one rooted in a client-side asset directory is `frontend`.
Naming after the runner guarantees a collision the moment a repo has two suites using it,
tells the reader nothing they cannot already see in `commands`, and would put a tool name
in a file that must stay ecosystem-neutral — avoid language abbreviations for the same
reason. For a single-suite project, `default` is fine.

Names must be unique, lowercase, and free of spaces and slashes.

**Disambiguate collisions by walking up the path, one segment at a time.** Start with the
suite root's last segment. While any two names collide, prepend the next segment up, joined
with a hyphen, to *each* colliding name — and repeat until every name is distinct. Two
suites rooted in a `web` app directory and a `mobile` app directory that both end in `api`
collide as `api`, then become `web-api` and `mobile-api`. Never disambiguate with a
counter: `api` and `api2` tells the reader nothing about which is which.

Verify uniqueness across the whole proposal before presenting it, since a collision
discovered later means redoing the run.

## Deriving commands

For every suite, derive `test`, `test_file` (with a `{file}` placeholder), and
`test_filter` (with a `{filter}` placeholder) from evidence, then `coverage`, `mutation`,
and `gherkin` wherever the evidence hierarchy supports them.

State plainly in the evidence trail that `test_filter` is required, not optional: the
verifier runs a single test in isolation to detect order dependence, and a suite proposed
without it loses that check entirely. If no source yields a way to filter to a single
test, say so as a warning rather than omitting the field silently — an omission reads as
"not applicable" when the true state is "not found."

## The report flag problem

A project's own coverage script frequently prints a human-readable summary to the terminal
without ever writing a machine-readable report to disk. A command that "runs coverage"
successfully by that definition is not sufficient — the proposal needs a report file at a
known path in a parseable format. When the evidence found stops short of a report, propose
the additional flag or step that would make it write one (the runner configuration file
and `references/stack-markers.md` both carry these), and say so explicitly in the
proposal: state that the base command was found but the report-writing flag was added by
this process and still needs confirmation, rather than presenting the augmented command as if
it had been observed directly.

## Determining tracks

- `unit` is enabled whenever a runner was found for the suite at all.
- `gherkin` is enabled **only** when BDD tooling is already present in the project —
  feature files, step definitions, and a runner capable of executing them. Never propose
  enabling it as a way to add BDD coverage to a project that lacks it; that is a decision
  for the user to make deliberately, not a default this process introduces.
- `mutation` is enabled only when mutation tooling is present in the project **and** its
  report format is machine-readable. Mutation tooling that exists but has no parseable
  report output is evidence of the tool, not evidence the track can run — leave it
  disabled and say why.

## Return format

Return a single, strictly valid JSON object — no comments, since the dispatcher parses this
with `jq`. Each element of `suites` is a full suite object (`name`, `paths`, `commands`,
`reports`, `tracks`, and optionally `thresholds`) — proposed, not yet written anywhere:

```json
{
  "suites": [],
  "evidence": [
    {
      "suite": "<suite name>",
      "field": "<dotted path, e.g. commands.coverage>",
      "value": "<what was derived>",
      "source": "manifest-script|ci-workflow|runner-config|stack-marker",
      "source_file": "<repo-relative path the value came from>"
    }
  ],
  "warnings": ["<free text: overlapping globs, missing test_filter, absent report tooling, unowned tree regions>"]
}
```

An empty `suites` array is a valid, correct result when no evidence of any suite exists —
that is the honest answer for a repository with no test harness, not a signal to fall back
to inventing one. Every suite it does contain must have at least one corresponding
`evidence` entry per field it populates. `warnings` must cover, at minimum, any overlapping
`paths.app` globs between suites, any suite missing `test_filter`, any track left disabled
for lack of report tooling, and any directory containing source files that no candidate
suite's `paths.app` claims.

## Red flags — STOP

- Inventing a command that no manifest, CI file, runner config, or marker entry supports.
  If nothing points to it, it does not go in the proposal.
- Enabling `gherkin` where no BDD tooling already exists in the project.
- Proposing a coverage command with no report output — either find the flag that produces
  one, or leave coverage out and say why.
- Writing any file directly. Confirming the proposal with the user, validating it by running
  the commands, and acting on it belongs to whoever dispatched this work, not to this process.
- Collapsing several independent harnesses into one suite because they share a language,
  a directory level, or a naming convention. Shared traits are not shared identity; each
  runnable harness gets its own suite.
