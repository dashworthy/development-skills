---
name: reviewing-a-pull-request
description: Use when reviewing a GitHub pull request or GitLab merge request with guardtower - dispatches reuse, security, code smell and abstraction analysts against the PR in an isolated worktree, scores their findings through an arbitrator, and posts the ones the user approves. Never modifies the repository under review.
---

# Reviewing a Pull Request

## The two rules

> **Rule one — Guardtower reports.** It never modifies the repository under review, never writes
> a test, never changes your checked-out branch, and never posts to a forge without explicit
> per-item approval.

> **Rule two — the context firewall.** The conductor reads the arbitrator's brief and nothing
> else. Not a diff body, not an analyst's finding, not a file an analyst read.

Rule two requires a mechanism, not an instruction — see **Context discipline** below. Every step
that follows is written to serve these two rules, not the other way around; when an instruction
below appears to conflict with either one, the rule wins and the run halts.

## Ask, don't configure

Threshold and lens selection are asked fresh every run; nothing about a run is written to disk for
a later run to read. Verity's README records that its removed config layer accounted for roughly
15 of its ~34 defects found during its build — guardtower does not reintroduce that layer. Never
write a config file to save yourself asking next time; see **Red flags — STOP**.

## Context discipline

The conductor holds this run's brief, its verdicts, and its numbers. It does **not** read diffs,
source files, or analyst findings — not because an instruction forbids it, but because reading one
of those in this context is exactly what the context firewall exists to prevent. Every step that
needs to read a diff, a source file, or a finding is dispatched to a subagent, and that subagent
returns a verdict, a count, or a receipt — never the raw text.

The **one exception**: the arbitrator's return is the single permitted read, and reading it is
required. It carries three things and nothing else — the items that cleared the gate, with their
scores and rationale; the dropped list, with each item's one-line reason its evidence didn't hold;
and the discarded entries, verified but scored below the threshold. Everything the conductor
reports, and everything it renders into `brief.md`, comes from that one return value.

Six named skills get dispatched over the course of a run: one of `surveying-for-reuse`,
`reviewing-for-security`, `detecting-code-smell`, `simplifying-through-abstraction` per selected
lens; then `arbitrating-findings`; then, only after triage, `posting-review-comments`. One more
dispatch follows a **reference document** instead of a skill name, because the work it does —
mapping the repo — belongs out of the conductor's context but isn't reusable in its own right:
hand a subagent `references/mapping-the-repo.md` as its complete brief.

## Preflight

### The worktree

A PR-only tool cannot assume your checked-out branch is the PR. It may be a different branch, the
same branch at a different commit, dirty with unrelated work, or from a fork you have never
fetched. So guardtower never reads the PR through your working tree and never switches your
branch:

1. Fetch the head ref — `git fetch origin pull/<n>/head` on GitHub, `git fetch origin merge-requests/<n>/head`
   on GitLab. Both resolve fork-sourced changes.
2. `git worktree add --detach <tempdir> <head-sha>` — a second checkout in a temp directory
   **outside the repository**, e.g. `<tempdir>=$(mktemp -d)`. Not just hygiene: a worktree left
   inside the repo tree, anywhere that resolves outside `.guardtower/`, shows up as an untracked
   path at the Reconcile re-measure and HALTs an otherwise clean run — even though it did no harm,
   the run stops anyway, because reconciliation cannot tell a harmless worktree from a real
   violation by path alone. `mktemp -d` puts it out of reach of that test entirely, which is why
   it is the instruction rather than "pick a path under `.guardtower/`". See **Reconcile**.
3. Analysts and the mapper read **inside that worktree**. The `<base-sha>...<head-sha>` diff is
   computed there too.
4. Remove the worktree at the end of the run, on every exit path including a halt — see
   **Cleanup**.

Your branch, your index, and your uncommitted work are untouched for the whole run. An analyst
that writes a file inside the temp worktree does no damage, because the worktree is discarded with
it. And reconciliation therefore only has to watch the **main** tree — see **Reconcile**.

### Steps

1. **Detect the forge** from `git remote get-url origin`. `github.com` → `gh`; `gitlab.*` →
   `glab`. Self-hosted or ambiguous → ask the user, do not guess. **Keep the path portion of that
   same URL**: it is the only place `repo` comes from — `owner/repo` on GitHub, the full project
   path (`group/subgroup/project`, or the numeric project id) on GitLab. Nothing later in preflight
   produces it; step 3's `gh pr view` is not asked for it, so a run that discards the origin URL
   after the forge check has to go back for it at **Post**.
2. **Verify the CLI** is present and authenticated — `gh auth status` or `glab auth status`.
   Missing or unauthenticated → name the tool, say how to fix it, and stop. This mirrors verity's
   stance on a missing `jq`: a fixable local problem is not a reason to quietly deliver less.
3. **Resolve the PR/MR** — base sha, head sha, and changed paths — with `gh pr view <n> --json baseRefOid,headRefOid,files`
   (GitHub) or `glab mr view <n>` (GitLab). **Paths only**; the conductor never reads diff
   contents.
4. **Stop if nothing reviewable changed.** Say so plainly and exit.
5. **Fetch and add the detached worktree**, per **The worktree** above.
6. **Snapshot the main tree** — `git diff --numstat HEAD` and `git status --porcelain` — before
   dispatching the first subagent of the run, so the mapper is inside the check too.
7. **Map the repo.** Dispatch one subagent with `references/mapping-the-repo.md` as its complete
   brief, together with its payload: `worktree` — the absolute path from step 5 — and `head_sha` —
   from step 3. The document itself defines neither; it expects both handed to it and its own stop
   list forbids mapping at any other commit, so dispatching it without this payload leaves it
   nothing to read. It returns existing modules and utilities, stack, conventions, and test
   locations — never a raw tree listing. The reuse analyst cannot answer "does this already exist?"
   from the diff alone, and mapping once beats four analysts each re-scanning the tree.
8. **Agree the gate.** Offer the default threshold of 80 and all four lenses; let the user
   override either. Persist neither. A lens the user drops is not dispatched, and is named in the
   final report, so a short brief is never mistaken for a clean one.

## Run id

`<YYYY-MM-DD>-<pr-number>-<suffix>`, where `suffix` is a random lowercase alphanumeric string of
at least six characters — `2026-07-29-482-k3f9qa`. Generate it from the system's entropy source,
never from the model:

```sh
LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6
```

If `.guardtower/<run>/` somehow already exists, regenerate rather than reusing or appending — that
is a `stat`, not a read.

This removes the last exception to "a run never looks at prior artifacts." An earlier sequential
scheme had to enumerate existing directories to pick the next integer; a random suffix needs no
such lookup, so the rule now holds with no carve-out at all — a future editor must not reintroduce
a directory scan to "make ids cleaner."

## The pass

One analyst per selected lens, dispatched **in parallel**, per
`superpowers:dispatching-parallel-agents` — `surveying-for-reuse` (reuse), `reviewing-for-security`
(security), `detecting-code-smell` (smell), `simplifying-through-abstraction` (abstraction). Each
receives exactly this dispatch brief:

```json
{
  "lens":          "reuse | security | smell | abstraction",
  "worktree":      "<absolute path to the detached worktree>",
  "base_sha":      "<PR base sha>",
  "head_sha":      "<PR head sha>",
  "changed_paths": ["<repo-relative path>", ...],
  "repo_map":      "<the mapper's return, verbatim>",
  "output_path":   "<absolute path to .guardtower/<run>/findings/<lens>.json>"
}
```

Each analyst reads the diff and whatever files it needs from the worktree, writes its findings to
`output_path` in the shape `references/finding-schema.md` defines, and returns **only a receipt**:
`wrote <N> findings to <output_path>` — never a finding, never a summary of one.

**State this plainly: an analyst returns a receipt; if you find yourself reading a finding, the
firewall has already failed.** The conductor's context grows by one short receipt per lens,
independent of PR size.

Once every dispatched analyst has returned its receipt, dispatch `arbitrating-findings` with this
payload:

```json
{
  "finding_paths": ["<each dispatched analyst's output_path>"],
  "worktree":      "<absolute path from preflight step 5>",
  "base_sha":      "<from preflight step 3>",
  "head_sha":      "<from preflight step 3>",
  "threshold":     "<the value agreed in preflight step 8>",
  "lenses_run":    ["<lens>", "..."]
}
```

Name every field. `threshold` is not optional decoration: it is the gate the arbitrator applies,
and preflight step 8 exists precisely so the user can move it. Hand over the paths alone, and the
number the user agreed is silently discarded — the arbitrator falls back to the `80` in its own
example dispatch — so "agree the gate" becomes decorative. `worktree` is where the arbitrator
resolves `target_file` and `existing_solution`, never the user's checked-out tree; without it,
evidence is verified against whatever tree the subagent happens to be standing in, which is the
user's own possibly-dirty checkout, and the single step this whole design rests on returns a
verdict it never actually verified. `base_sha` and `head_sha` fix the revision verification runs
against, and `lenses_run` is the sanity check that `finding_paths` holds exactly one entry per lens
actually dispatched. A conductor that hands over only the paths is telling the arbitrator to
consult five fields it was never given — the same gap the mapper dispatch had before preflight
step 7 spelled its payload out, and the poster's had before **Post** did.

It reads the finding files itself, verifies each one's evidence against the worktree at the head
sha, scores and gates what holds per `references/scoring-rubric.md`, and returns exactly three
things — the items that cleared the threshold, the dropped list with each item's one-line reason
its evidence didn't hold, and the discarded entries that were verified but scored below the
threshold — and nothing else. This is the one return value **Context discipline**
names as the permitted exception. It is also the only source for `brief.md`'s summary counts and
for **Reporting, always** below: the conductor cannot re-derive a dropped or discarded count from
anywhere else without reading a finding file itself, which rule two forbids.

## Reconcile

Analysts are read-only by instruction, but nothing mechanically stops a dispatched agent from
writing. The worktree absorbs most of that risk, since a write there is discarded with it. What
remains is a write into the **main** tree:

- The snapshot from **Preflight** step 6 was taken **before the first subagent of the run — the
  mapper**, not just before the analysts. Re-measure `git diff --numstat HEAD` and `git status
  --porcelain` again **after the arbitrator returns** — the last subagent of the pass. One
  snapshot and one re-measurement bracket every subagent the run dispatches: mapper, analysts,
  arbitrator. Reconciling any earlier would leave the arbitrator outside the only check there is.
- A path is **touched** when it is absent from the snapshot, or when its added/deleted counts
  differ from the snapshot's. **Counts, not `git status` alone**: a porcelain entry for an
  already-modified file reads ` M path` both before and after a write, so a status-only comparison
  cannot see an agent editing a file that was already dirty — and running guardtower with
  unrelated work in progress is normal.
- Resolve every touched path with `readlink -f` (or `cd "$(dirname …)" && pwd -P`) before
  comparing, so a symlink pointing out of the allowed area is caught by its existence.
- Anything resolving outside `.guardtower/` **HALTS the run**: surface the offending paths and
  **the reconciliation diff of those paths** — what a subagent changed in them between the snapshot
  and the re-measure — to the user, and stop. That is not the PR diff, which rule two keeps out of
  this context regardless; it is the evidence of the violation, and it is confined to the paths the
  comparison just named. The worktree is still removed — see **Cleanup**.

**Never auto-revert.** Reverting is destructive and cannot distinguish a bug worth diagnosing from
evidence the user needs intact.

## Triage

Present every finding that cleared the gate — rendered from `references/brief-template.md` into
`.guardtower/<run>/brief.md` — with its scores and rationale. The user marks each one **in scope**
or **out of scope**:

- In scope → written to `.guardtower/<run>/approved.md`, then posted.
- Out of scope → written to `.guardtower/<run>/deferred.md` — a write-only backlog, never posted
  and never read by a later run.

Nothing is posted before this step completes.

## Post

Dispatch `posting-review-comments` with this payload:

```json
{
  "forge": "github | gitlab",
  "pr_number": "<from the reference the user gave>",
  "repo": "<owner/repo, or GitLab project id/path — from the origin URL, preflight step 1>",
  "base_sha": "<from preflight step 3>",
  "head_sha": "<from preflight step 3>",
  "run_id": "<this run's id>",
  "lenses_run": ["<lens>", "..."],
  "lenses_skipped": ["<lens>", "..."],
  "approved": ["<the in-scope subset of the arbitrator's passed array>"]
}
```

Name every field. `base_sha` is not optional decoration: GitLab's discussion API needs it
alongside `head_sha` to anchor a diff position, and `run_id`, `lenses_run` and `lenses_skipped` are
what let the summary comment name the run and admit which lenses were skipped. A poster handed only
the approved set is told by its own instructions to consult fields it was never given — the same
gap the mapper dispatch had before preflight step 7 spelled its payload out.

This happens only because guardtower is a PR-only tool to begin with — there is no local-diff mode
to post from by accident — and only after triage; nothing is dispatched until the user has marked
every posted item in scope. It posts a single pending review, submitted once: an inline comment
where `target_line` sits inside a diff hunk (`in_diff: true`), a line in the one summary comment
otherwise.

## Cleanup

`git worktree remove --force <tempdir>` on **every** exit path, including a halt — a stopped run is
not an exception. Then `git worktree prune`.

## Reporting, always

Whichever way the run ends, report:

- What was posted, and where.
- What was dropped by evidence failure, with the arbitrator's one-line reason for each.
- What was discarded by the gate — findings that were verified but scored below the threshold.
- Every lens the user chose not to run, named explicitly, so a short brief is never mistaken for a
  clean one.

Then invoke `superpowers:verification-before-completion` before reporting anything as done.

## Red flags — STOP

- Reading a diff or a finding in the conductor's own context instead of dispatching it.
- Switching the user's checked-out branch, or running `gh pr checkout`.
- Posting anything not marked in scope during triage.
- Auto-reverting a reconciliation violation instead of surfacing it.
- Leaving the temp worktree behind on any exit path, including a halt.
- Writing a config file "to make this more reliable next time."
- Reporting a threshold met without the numbers that prove it.
- Dispatching an analyst without the worktree path, so it reads your checked-out tree instead.
- Reading an analyst's `findings/<lens>.json` directly instead of waiting for its receipt and the
  arbitrator's return.
- Persisting threshold or lens selection anywhere for a later run to read.
