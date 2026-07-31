---
name: posting-review-comments
description: Use when dispatched by guardtower to post approved review findings to a GitHub pull request or GitLab merge request - posts one review, never posts a finding the user did not approve, and writes nothing to the repository
---

# Posting Review Comments

## You post only what you were given

State this first and unconditionally, because every section below assumes it: every item in
`approved` was marked in scope by a human during triage. Anything not in that array does not
exist as far as this skill is concerned — not a finding triage deferred, not one you think was cut
in error, not one you notice yourself while composing a comment. You do not re-derive scope, you
do not add a finding back because it looks important, and you do not read `deferred.md` or any
other artifact to double-check the human's call. **Never post a finding the user did not
approve.**

This is the only skill in guardtower that writes anything outside the repository. Every analyst
and the arbitrator are advisory — a wrong call there costs a bad line in a brief nobody has acted
on yet. A wrong call here is a comment on someone's pull request, visible to every other reviewer,
that cannot be un-posted by deleting a local file.

## What you receive

One dispatch per run:

```json
{
  "forge": "github | gitlab",
  "pr_number": 482,
  "repo": "<owner/repo, or GitLab project id/path>",
  "base_sha": "<PR base sha>",
  "head_sha": "<PR head sha>",
  "run_id": "<YYYY-MM-DD>-<pr-number>-<suffix>",
  "lenses_run": ["reuse", "security", "smell"],
  "lenses_skipped": ["<lens>", "..."],
  "approved": [ "<the in-scope subset of the arbitrator's `passed` array>" ]
}
```

`forge`, `pr_number`, `repo`, `approved`, and `head_sha` are this task's declared interface.
`base_sha`, `run_id`, `lenses_run`, and `lenses_skipped` are included alongside them because two
requirements below cannot be met without them and the conductor already holds all four at zero
extra cost: GitLab's discussion API requires a `base_sha` in addition to `head_sha` to anchor a
diff position (see **One review, submitted once**), and the summary comment cannot name the run or
say which lenses were skipped (see **Summary comment structure**) without being told.

Each entry in `approved` carries exactly the fields the arbitrator assigns in its `passed` array —
never more, never invented here. See `../arbitrating-findings/SKILL.md`'s Return format for the
authoritative field list: `id`, `lens`, `target_file`, `target_line`, `claim`, `rationale`,
`proposal`, `in_diff`, `also_at`, `value`, `urgency`, `composite`, plus `kind` on every reuse
finding, `tier` and `existing_solution` on every reuse finding except an `extract` one, and
`adoption_cost` at tier 2. If a field this skill wants isn't on
that list, it doesn't exist yet — that is a conductor or arbitrator change, not something to
paper over here.

## One review, submitted once

Build the whole review — every inline comment and the one summary body — before you submit
anything, then post it as a single request, so the reviewer gets one notification rather than one
per comment. Below, `$REPO` is `repo`; `$PR` and `$MR` are both `pr_number` (GitHub calls it a
pull number, GitLab a merge request iid); `$HEAD_SHA` and `$BASE_SHA` are `head_sha` and
`base_sha`.

GitHub, via `gh api` with a JSON body built in a heredoc — one call, one pending review, submitted
as `COMMENT` so it posts immediately without requiring a separate approve/request-changes step.
**The heredoc delimiter is unquoted (`<<JSON`, not `<<'JSON'`) on purpose:** a quoted delimiter
suppresses every expansion inside the body, so `$HEAD_SHA` would post to the pull request as that
literal nine-character string rather than the sha, and the review would attach to nothing.

```sh
gh api "repos/$REPO/pulls/$PR/reviews" \
  --method POST \
  --input - <<JSON
{
  "commit_id": "$HEAD_SHA",
  "event": "COMMENT",
  "body": "<summary markdown, per Summary comment structure>",
  "comments": [
    { "path": "src/auth/token.js", "line": 31, "side": "RIGHT", "body": "**guardtower security-001** (93) …" }
  ]
}
JSON
```

GitLab has no single-request equivalent: one discussion per inline comment, plus one note for the
summary. This is still "one review, submitted once" in the sense that matters — no per-finding
notification-worthy event beyond what the routing below produces, and every call happens in the
same batch with nothing held back for a later pass:

```sh
glab api "projects/:id/merge_requests/$MR/discussions" \
  --method POST \
  -f body="**guardtower security-001** (93) …" \
  -f 'position[position_type]=text' \
  -f "position[new_path]=src/auth/token.js" \
  -f "position[new_line]=31" \
  -f "position[head_sha]=$HEAD_SHA" \
  -f "position[base_sha]=$BASE_SHA" \
  -f "position[start_sha]=$BASE_SHA"

glab mr note "$MR" --message "<summary markdown, per Summary comment structure>"
```

## Routing

`in_diff: true` becomes an inline comment at `target_file`:`target_line`; `in_diff: false` becomes
a line in the one summary comment. This is a constraint of the forges, not a design preference:
GitHub and GitLab only accept an inline comment on a line present in the diff, so a finding whose
evidence sits in untouched code — common for reuse findings, where the duplicated original is not
part of the change — cannot be anchored inline. Relocating it to the summary is correct; relocating
it *silently* is not, so the return names which findings were moved and why (see **Return
format**).

## Comment body format

Every posted comment — inline or inside the summary — follows the same template:

```
**guardtower <id>** (<composite>) — <claim>

<rationale>

<proposal>

Also at: <also_at, comma-joined>

Existing solution: <existing_solution>
Adoption cost: <adoption_cost>

value <value> · urgency <urgency>
```

The `Also at` line appears only when `also_at` is non-empty — omit the line entirely when the
finding sits at a single location. Do not omit it when it *is* populated: an `extract` finding
usually spans several files, and `target_file`/`target_line` names only the clearest of them, so a
comment that drops `also_at` silently reports one occurrence of a problem the analyst found in
five.

The `Existing solution` line appears only for reuse findings that cite one — `reimplements`,
`duplicates`, and `diverges`, never `extract`, which by definition found nothing that already
solves the problem. The `Adoption cost` line appears only for reuse findings at tier 2. Omit both
for every other finding, and omit `Adoption cost` alone for a tier 1 reuse finding. The `value <n> · urgency <n>` footer is never omitted — it is
what lets a reader see how the finding scored without opening `brief.md`.

## Summary comment structure

One comment, built once, in this shape:

```
## guardtower

Run `<run_id>`. Lenses run: <lenses_run, comma-joined>. Lenses skipped: <lenses_skipped,
comma-joined, or "none">.

### <lens>

- **<id>** — `<target_file>:<target_line>` — <claim>
  (full body per Comment body format)

### <next lens>
…
```

Findings are grouped by `lens`, each group holding every approved finding from that lens with
`in_diff: false`, in the order `approved` arrives in. **Where a lens was skipped, say so** — list
it under Lenses skipped rather than letting its absence read as "this lens ran and found
nothing." A short summary comment must never read as a clean bill of health when the truth is that
nobody looked.

## Failure handling

If the API call fails, report the failure with the response body and stop. Do not retry with a
reduced payload — dropping a comment to get the request to succeed silently changes what gets
posted from what the user approved — and do not fall back to posting a plain comment when an
inline one was intended, for the same reason: both are quiet, unannounced changes to an approved
set, and this skill's first rule is that it posts only what it was given.

## Return format

Return exactly this shape:

```json
{
  "posted_inline": 4,
  "posted_summary": 2,
  "review_url": "<url>"
}
```

Alongside it, name every finding that was relocated from an inline comment to the summary — by
`id` and by the one-line reason from **Routing** — so the person reading the result can see that a
finding moved, not just that a count changed. A relocation is not a new field on this JSON; it is
part of what you report when you return it.

## Red flags — STOP

- Posting anything not in `approved`.
- Posting one comment per finding instead of one review, submitted once.
- Silently relocating an inline comment to the summary without saying so.
- Retrying with a reduced payload after a failure, or falling back to a plain comment when an
  inline one was intended.
- Writing any file in the repository — this skill posts to the forge, it does not touch disk.
- Using `jq` to build or parse the request. Guardtower deliberately has no tool whose absence
  would silently weaken a run; shelling out to `jq` reintroduces exactly that dependency.
