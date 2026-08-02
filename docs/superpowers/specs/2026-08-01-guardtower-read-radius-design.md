# Guardtower: bound the research with a read radius

## The problem

Guardtower's analysts research the application far past the change they were asked to review.
Across the three lenses and the conductor, a single run currently licenses:

- a dependency **manifest and lock file** read, in two separate lenses
- a per-candidate grep of the worktree for "those words and for the obvious synonyms"
- a stdlib and platform-API sweep per candidate
- a **second** whole-worktree search per pattern, to build an `extract` finding's occurrence list
- opening installed package source in `vendor/` or `node_modules/` to quote it
- a worktree search for pre-existing mitigations, on the security lens
- and, to make the package reads possible at all, the conductor symlinking the **entire installed
  dependency tree** into the detached worktree before dispatching anything

None of that is the review. It is reconnaissance the review rests on, and it has grown until the
reconnaissance is most of the run.

## The mechanism

One rule, stated once in `finding-schema.md` — the contract all three lenses already share — and
referenced by each lens instead of each lens carrying its own research licence.

**Inside the radius, open anything, without justification:**

- the `<base-sha>...<head-sha>` diff
- any file in `changed_paths`, in full
- the dependency manifest — **one file, never the lock file**
- any file a changed line directly leads to: what it imports, what it calls into, what calls it.
  **One hop, from a changed line.**

**Outside the radius, you get one targeted search per candidate.** A search for a named thing you
already hold — not a scan, not a synonym expansion, not a second pass. If it comes back empty the
answer is *not found*, and the finding either stands on what you already have or is not written.

The radius is deliberately mechanical. "Read what the change touches, plus one hop, plus one search
when you have a specific question" is checkable by the analyst mid-run in a way that "don't
over-research" is not.

## What follows from it

### The dependency-tree symlink is deleted

`reviewing-a-pull-request/SKILL.md`'s worktree step 3 — the `for dep in vendor node_modules .venv
.bundle target Pods` loop and its justification — exists only so analysts can open installed
package source. Nothing else uses it. It goes, along with the "The worktree also carries the
repository's installed dependency tree" paragraph repeated in all three lenses and in
`finding-schema.md`'s **Where you read**.

### The evidence standard splits on "in this repo," not "openable"

Today `existing_evidence` splits on whether a thing has source to open, with a carve-out stating
that installed packages **do** have source — because the symlink put it there — and must therefore
be opened rather than cited by signature.

With no tree, the split becomes one line with no carve-out:

- `existing_solution` is a **path in this repository** → open it and quote the source text.
- `existing_solution` is **anything else** — language stdlib, platform API, an installed package, a
  `tier: 2` package that is not installed → cite the **documented signature**.

The arbitrator's mirror rule changes with it: the sentence scoping the documented-signature
allowance away from installed dependencies is removed, because that allowance is now the rule for
everything outside the repo.

**This is not a regression to the pre-symlink state.** That state paired *never cite an
`existing_solution` you have not opened* with a worktree that had no packages in it — unsatisfiable
by construction, which is why it silently dropped 3 of 4 reuse findings on the first live run. The
new rule explicitly names signature citation as correct outside the repo, so it is satisfiable for
every citation an analyst can make.

### `extract` findings get rarer, and that is correct

An `extract` finding's `also_at` occurrences must now be found inside the radius, via the one
search. The bar stays at three verified occurrences. A repeated shape that does not appear three
times within the diff and one hop does not earn an extract finding.

This is the lens's own **Scope is the diff** rule applied honestly rather than waived for the one
finding kind that used to search the whole tree to satisfy itself.

### Security's dependency and mitigation work comes inside the radius

- **Dependency surface** is what the diff changes, read against the manifest. The lock file, and
  with it the hunt for a transitive package that "never appears in the diff," is dropped.
- **Existing mitigations** are checked in the code the diff calls into — one hop, already free.
  Where reachability cannot be traced inside the radius, no finding is emitted. That is what
  **Theoretical findings are out of scope** already demanded; the radius makes it enforceable.

### `unanswered` slims to one line per candidate

With one search per candidate, the three-field record collapses. `searched`, `manifest_checked`
and `considered` become a single `searched` field. The array itself stays: it is what separates
"nothing already does this" from "I did not look," and at one line per candidate it is cheap.

## Explicitly unchanged

The detached worktree and the branch-safety it buys, reconciliation and its HALT, the two rules,
the context firewall, the receipt protocol, `scoring-rubric.md`, the 80 gate, cross-lens dedup,
triage, and posting. None of those are research, and none are touched.

The smell lens keeps its linter/formatter config read: one file, already conditional on being about
to flag something a tool might own, and the only thing preventing that lens from duplicating a
linter.

## Test impact

`tests/validate.sh` carries 185 grep-anchored checks. Three anchor the dependency tree directly and
are retired:

- `finding-schema.md tells analysts the dependency tree is reachable in the worktree`
- `every analyst is told the installed dependency tree is reachable in the worktree`
- `conductor: links the dependency tree into the worktree, read-only`

Checks anchoring the read radius replace them: the radius stated in `finding-schema.md`, every
analyst pointing at it, the one-search-per-candidate bound, and the in-repo/not-in-repo evidence
split on both the reuse lens and the arbitrator. Net count is roughly unchanged.
