---
name: reviewing-a-pull-request
description: Use when reviewing a GitHub pull request or GitLab merge request with guardtower - dispatches reuse, security and code smell analysts against the PR in an isolated worktree, scores their findings through an arbitrator, and posts the ones the user approves. Never modifies the repository under review.
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

Five named skills get dispatched over the course of a run: one of `surveying-for-reuse`,
`reviewing-for-security`, `detecting-code-smell` per selected lens; then `arbitrating-findings`;
then, only after triage, `posting-review-comments`. That list is exhaustive: every dispatch a run
makes follows one of those named skills, and nothing else is dispatched.

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
3. **Link the repository's dependency tree into it.** `git worktree add --detach` produces a
   clean checkout, so every gitignored dependency directory is simply absent — `vendor/` for
   Composer, `node_modules/` for npm, `.venv/` for pip, a vendored Go tree, whatever this
   ecosystem installs into. Symlink each one that exists in the main checkout into the worktree,
   before dispatching anything:

   ```sh
   for dep in vendor node_modules .venv .bundle target Pods; do
     [ -e "$MAIN/$dep" ] && [ ! -e "$WORKTREE/$dep" ] && ln -s "$MAIN/$dep" "$WORKTREE/$dep"
   done
   ```

   **Without this, two lenses silently shrink.** On the first live run the security analyst
   reported that whether a `crypted_string` column type and an encoder service existed at all was
   "all vendor-resident. I resolved this by not asserting anything that depended on vendor
   behavior, which cost at least one candidate finding" — a lens that quietly reviews less than it
   was asked to. The reuse lens is worse off: its red flag *a finding whose `existing_solution` you
   have not opened and read* is unsatisfiable by construction when the existing solution lives in
   an installed package, and 3 of that run's 4 reuse findings cited one, so an arbitrator applying
   the rule as written would have dropped all three.

   Read-only reuse of the main checkout's dependency tree is safe: nothing in a run writes through
   the link. Every analyst and the arbitrator are read-only by instruction, the conductor creates
   the link rather than they, and **Reconcile** measures the main tree by path — which the link
   points into but nothing modifies. The links live inside the temp worktree, so `git worktree
   remove --force` takes them with it, and removing a symlink never touches what it points at.
4. Analysts read **inside that worktree** — the diff, and every manifest, config file, source file
   or installed package they open to answer a question. The `<base-sha>...<head-sha>` diff is
   computed there too.
5. Remove the worktree at the end of the run, on every exit path including a halt — see
   **Cleanup**.

Your branch, your index, and your uncommitted work are untouched for the whole run. An analyst
that writes a file inside the temp worktree does no damage, because the worktree is discarded with
it. And reconciliation therefore only has to watch the **main** tree — see **Reconcile**.

### Steps

**Every step below runs with the working directory inside the repository under review** — the
checkout whose `origin` is the forge hosting this PR, never the directory guardtower happened to be
invoked from. On the first live run the conductor's own cwd was the *plugin* repo, where
`git remote get-url origin` returns a different remote entirely, so step 1 would have detected the
wrong forge and step 3 resolved the wrong project, both without erroring. `.guardtower/<run>/` is
rooted at that same repository's root, for the same reason: it is the tree **Reconcile** measures,
and an artifact root anywhere else puts every write this run makes outside the only check there is.

1. **Detect the forge** from `git remote get-url origin`. `github.com` → `gh`; `gitlab.*` →
   `glab`. Self-hosted or ambiguous → ask the user, do not guess. **Keep two parts of that same
   URL.** The path portion is the only place `repo` comes from — `owner/repo` on GitHub, the full
   project path (`group/subgroup/project`, or the numeric project id) on GitLab. Nothing later in
   preflight produces it; step 3's `gh pr view` is not asked for it, so a run that discards the
   origin URL after the forge check has to go back for it at **Post**. The **host** portion is what
   `glab` needs on a self-hosted GitLab — export it as `GITLAB_HOST` before any `glab` call,
   including step 2's:

   ```sh
   ORIGIN=$(git remote get-url origin)
   export GITLAB_HOST=$(printf '%s' "$ORIGIN" | sed -e 's|^[a-z+]*://||' -e 's|^[^@]*@||' -e 's|[:/].*$||')
   ```

   Unset, every `glab` call targets gitlab.com — so `glab auth status` asks about a host the user
   has no account on, reports unauthenticated, and **preflight halts on a correctly-configured
   machine.** Self-hosted GitLab is the common enterprise case, not an edge one.
2. **Verify the CLI** is present and authenticated — `gh auth status` or `glab auth status`, the
   latter with `GITLAB_HOST` already exported per step 1. Missing or unauthenticated → name the
   tool, say how to fix it, and stop. This mirrors verity's stance on a missing `jq`: a fixable
   local problem is not a reason to quietly deliver less.
3. **Resolve the PR/MR** — base sha, head sha, **start sha**, and changed paths. **Paths only**;
   the conductor never reads diff contents.

   ```sh
   # GitHub: named fields only. A bare `gh pr view <n>` prints the whole description.
   gh pr view <n> --json baseRefOid,headRefOid,files

   # GitLab: the MR object's `diff_refs` carries base_sha, start_sha and head_sha together.
   # Pipe the response through a field extractor so only the shas reach this context.
   glab api "projects/$ENC_REPO/merge_requests/<n>" \
     | python3 -c 'import json,sys; r=json.load(sys.stdin)["diff_refs"]; print(r["base_sha"], r["start_sha"], r["head_sha"])'

   # Changed paths, once step 5 has fetched the head ref — both commits must be present locally.
   git diff --name-only "$BASE_SHA...$HEAD_SHA"
   ```

   `$ENC_REPO` is `repo` URL-encoded — every `/` becomes `%2F`, so `oro/wastequip` is
   `oro%2Fwastequip`. **`glab mr view <n>` is not the command for this step**: it returns title,
   state, author, labels, url and a comment count, and none of the three shas or the changed
   paths.

   **`start_sha` comes from `diff_refs`, and it is not `base_sha`.** Measured on the first live
   run: `base_sha e2c4753`, `start_sha cdc22db` — different values, and `start_sha` changed on
   every push, seven diff versions on that one merge request. GitLab validates an inline comment's
   position triple against a stored diff version, so a position built with `start_sha` set to
   `base_sha` matches no version at all and every inline comment is rejected. Carry all three shas
   to **Post**.

   **The MR title and description must not enter this context.** `glab mr view <n>` prints the
   entire description — roughly 2,500 words of architecture narrative on the live MR — into the
   very step that says the conductor never reads diff contents. It is not a diff, but it is
   substantive prose about the code under review, written to persuade, and reading it primes every
   downstream judgement the conductor is supposed to make on the arbitrator's numbers alone.
   Request the fields you need and nothing else.
4. **Stop if nothing reviewable changed.** Say so plainly and exit.
5. **Fetch and add the detached worktree**, per **The worktree** above.
6. **Snapshot the main tree** — `git diff --numstat HEAD` and `git status --porcelain` — before
   dispatching the **first** subagent of the run, whichever subagent that is, so that no dispatch
   this run makes falls outside the check. See **Reconcile**.
7. **Agree the gate.** Offer the default threshold of 80 and all three lenses; let the user
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
(security), `detecting-code-smell` (smell). Each receives exactly this dispatch brief:

```json
{
  "lens":          "reuse | security | smell",
  "worktree":      "<absolute path to the detached worktree>",
  "base_sha":      "<PR base sha>",
  "head_sha":      "<PR head sha>",
  "changed_paths": ["<repo-relative path>", ...],
  "output_path":   "<absolute path to .guardtower/<run>/findings/<lens>.json>",
  "skill_path":    "<absolute path to the SKILL.md this dispatch names>",
  "schema_path":   "<absolute path to finding-schema.md>"
}
```

Name every field here too. `skill_path` and `schema_path` are the two the brief used to leave a
dispatched analyst to guess: it carried a `lens` and no path to that lens's own SKILL.md, and it
told the analyst to write "the shape `finding-schema.md` defines" without saying where that
document is. The first live run's conductor patched both in as prose at dispatch time — a fix that
works once and is gone the next run, which is what a payload field exists to prevent. An analyst
that cannot open the contract writes to a shape it reconstructed from memory, and the arbitrator
drops findings for missing fields nobody ever showed it.

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
  "threshold":     "<the value agreed in preflight step 7>",
  "lenses_run":    ["<lens>", "..."],
  "skill_path":    "<absolute path to the SKILL.md this dispatch names>",
  "schema_path":   "<absolute path to finding-schema.md>"
}
```

Name every field. `threshold` is not optional decoration: it is the gate the arbitrator applies,
and preflight step 7 exists precisely so the user can move it. Hand over the paths alone, and the
number the user agreed is silently discarded — the arbitrator falls back to the `80` in its own
example dispatch — so "agree the gate" becomes decorative. `worktree` is where the arbitrator
resolves `target_file` and `existing_solution`, never the user's checked-out tree; without it,
evidence is verified against whatever tree the subagent happens to be standing in, which is the
user's own possibly-dirty checkout, and the single step this whole design rests on returns a
verdict it never actually verified. `base_sha` and `head_sha` fix the revision verification runs
against, and `lenses_run` is the sanity check that `finding_paths` holds exactly one entry per lens
actually dispatched. A conductor that hands over only the paths is telling the arbitrator to
consult five fields it was never given — the same gap the poster's dispatch had before **Post**
spelled its payload out. `skill_path` and `schema_path` close the same hole the analyst brief had:
the arbitrator is told to score against `scoring-rubric.md` and to read findings written to
`finding-schema.md`'s shape, and a subagent cannot resolve a relative citation from a directory it
was never told it is standing in. `schema_path` locates both — the rubric is its sibling in the
same `references/` directory.

It reads the finding files itself, verifies each one's evidence against the worktree at the head
sha, scores and gates what holds per `references/scoring-rubric.md`, and returns exactly three
things — the items that cleared the threshold, the dropped list with each item's one-line reason
its evidence didn't hold, and the discarded entries that were verified but scored below the
threshold — and nothing else. A passed item may carry `corroborated_by`: the other lenses that
found the same defect at the same evidence span, folded into it by the arbitrator's dedup step
rather than reported twice. Render it into `brief.md` — a defect three lenses independently found
is stronger evidence than one lens's opinion, and dropping the corroboration on the floor at the
render step throws away exactly the signal dedup was added to preserve. This is the one return value **Context discipline**
names as the permitted exception. It is also the only source for `brief.md`'s summary counts and
for **Reporting, always** below: the conductor cannot re-derive a dropped or discarded count from
anywhere else without reading a finding file itself, which rule two forbids.

## Reconcile

Analysts are read-only by instruction, but nothing mechanically stops a dispatched agent from
writing. The worktree absorbs most of that risk, since a write there is discarded with it. What
remains is a write into the **main** tree:

- The snapshot from **Preflight** step 6 was taken **before the first subagent of the run**, and
  re-measurement happens **after the arbitrator returns** — the last subagent of the pass. The
  reason is the bracket, not the identity of either subagent: this check is a pair of
  measurements, and it is worth exactly what it encloses. **One snapshot and one re-measurement
  must bracket every subagent the run dispatches**, leaving none of them outside. Today the first
  is the first analyst and the last is the arbitrator, so those are the two ends; if a run ever
  dispatches something earlier or later, the snapshot and the re-measurement move out to it rather
  than the bracket closing in. Reconciling any earlier would leave the arbitrator outside the only
  check there is, and snapshotting any later would leave whatever ran first outside it.
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
  "start_sha": "<from preflight step 3 — GitLab's diff-version anchor, never base_sha>",
  "run_id": "<this run's id>",
  "lenses_run": ["<lens>", "..."],
  "lenses_skipped": ["<lens>", "..."],
  "skill_path": "<absolute path to the SKILL.md this dispatch names>",
  "approved": ["<the in-scope subset of the arbitrator's passed array>"]
}
```

Name every field. `base_sha` is not optional decoration: GitLab's discussion API needs it
alongside `head_sha` to anchor a diff position, and `run_id`, `lenses_run` and `lenses_skipped` are
what let the summary comment name the run and admit which lenses were skipped. A poster handed only
the approved set is told by its own instructions to consult fields it was never given — the same
gap the arbitrator's dispatch had before **The pass** spelled its payload out.

**`start_sha` is the third of GitLab's three and the one nothing else can supply.** The position
triple is validated against a stored diff version; `start_sha` is not `base_sha` (measured live at
`e2c4753` and `cdc22db` on the same MR) and it changes on every push, so it cannot be derived,
guessed, or substituted downstream. Leave it out of this payload and the poster has no correct
value to send, every inline comment is rejected, and the poster's own no-fallback rule then kills
the whole inline set rather than degrading it — a run that posts nothing inline, from findings the
user already approved. `skill_path` is here for the reason it is on the other two dispatches: the
poster resolves the arbitrator's authoritative field list by a relative citation it cannot follow
without knowing where it stands.

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
- Reading the PR or MR title and description into this context — `glab mr view <n>` does it by
  default, which is why step 3 does not use it.
- Running a preflight command anywhere but inside the repository under review.
- Dispatching an analyst into a worktree whose dependency tree was never linked in.
- Dispatching the poster without `start_sha`, or with `start_sha` set to `base_sha`.
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
