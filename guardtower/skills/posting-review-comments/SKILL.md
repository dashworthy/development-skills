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
  "start_sha": "<GitLab diff-version anchor — never equal to base_sha>",
  "run_id": "<YYYY-MM-DD>-<pr-number>-<suffix>",
  "lenses_run": ["reuse", "security", "smell"],
  "lenses_skipped": ["<lens>", "..."],
  "skill_path": "<absolute path to the SKILL.md this dispatch names>",
  "approved": [ "<the in-scope subset of the arbitrator's `passed` array>" ]
}
```

`forge`, `pr_number`, `repo`, `approved`, and `head_sha` are this task's declared interface.
`base_sha`, `start_sha`, `run_id`, `lenses_run`, `lenses_skipped`, and `skill_path` are included
alongside them because requirements below cannot be met without them and the conductor already
holds all six at zero extra cost: GitLab's discussion API requires `base_sha` **and** `start_sha`
in addition to `head_sha` to anchor a diff position (see **One review, submitted once**), the
summary comment cannot name the run or say which lenses were skipped (see **Summary comment
structure**) without being told, and `skill_path` is what lets this skill resolve the relative
citation below to the arbitrator's own document from whatever directory a subagent starts in.

Each entry in `approved` carries exactly the fields the arbitrator assigns in its `passed` array —
never more, never invented here. See `../arbitrating-findings/SKILL.md`'s Return format for the
authoritative field list: `id`, `lens`, `target_file`, `target_line`, `claim`, `rationale`,
`proposal`, `in_diff`, `also_at`, `corroborated_by`, `value`, `urgency`, `composite`, plus `kind`
on every reuse finding, `tier` and `existing_solution` on every reuse finding except an `extract`
one, and `adoption_cost` at tier 2. If a field this skill wants isn't on
that list, it doesn't exist yet — that is a conductor or arbitrator change, not something to
paper over here.

## One review, submitted once

Build the whole review — every inline comment and the one summary body — before you submit
anything, then post it as a single request, so the reviewer gets one notification rather than one
per comment. Below, `$REPO` is `repo` and `$ENC_REPO` is `repo` URL-encoded; `$PR` and `$MR` are
both `pr_number` (GitHub calls it a pull number, GitLab a merge request iid); `$HEAD_SHA`,
`$BASE_SHA` and `$START_SHA` are `head_sha`, `base_sha` and `start_sha`.

### Finding text never reaches the shell as text

Do this before either forge block, because both depend on it. **Every body — inline or summary —
is assembled into a shell variable from a quoted heredoc, and reaches a command only as `"$VAR"`.**
Real finding text is hostile to a shell: the first live run's rationales contained `$data`,
`$settings`, `$e`, `$connection`, backticks and double quotes, every one of them an ordinary
identifier quoted in prose about the code. Written literally into an unquoted heredoc or between
double quotes, `$data` expands to the empty string and deletes itself from the posted comment
without a word, a backtick opens a command substitution, and a single `"` ends the JSON string and
breaks the request.

```sh
SUMMARY=$(cat <<'GT_BODY'
<summary markdown, per Summary comment structure>
GT_BODY
)
BODY_1=$(cat <<'GT_BODY'
**guardtower security-001** (93) — $data is interpolated into the query …
GT_BODY
)
```

The delimiter **is** quoted there, and that is the point: the shell performs no expansion at all
inside a quoted heredoc, so those bytes arrive exactly as the analyst wrote them. Shas and paths go
in as shell variables the command substitutes; finding text goes in as data the shell never reads.

GitHub, via `gh api` — one call, one pending review, submitted as `COMMENT` so it posts immediately
without requiring a separate approve/request-changes step. `python3` assembles the JSON, because
`json.dumps` escapes every quote, backslash and control character correctly and the bodies reach it
through the environment rather than through a Python literal, so nothing a finding contains can
break the program that is quoting it. This keeps the no-`jq` property intact: python3 is already
this plugin's stdlib JSON tool, so nothing new can be missing.

```sh
export HEAD_SHA SUMMARY BODY_1
python3 - <<'GT_JSON' | gh api "repos/$REPO/pulls/$PR/reviews" --method POST --input -
import json, os
print(json.dumps({
    "commit_id": os.environ["HEAD_SHA"],
    "event": "COMMENT",
    "body": os.environ["SUMMARY"],
    "comments": [
        {"path": "src/auth/token.js", "line": 31, "side": "RIGHT",
         "body": os.environ["BODY_1"]},
    ],
}))
GT_JSON
```

An earlier version of this skill wrote that body into a heredoc with an **unquoted** delimiter so
the shell would substitute `$HEAD_SHA` into it. That is a correctness bug, not a style choice: the
one expansion that fills the sha in is the same expansion that empties `$data` out of a rationale,
and no delimiter choice serves both. Quoting the delimiter and substituting the sha in Python
serves both, which is why the sha is read from the environment above rather than written into the
document at all. **Do not "simplify" this back to a shell-interpolated body.**

GitLab has no single-request equivalent: one discussion per inline comment, plus one note for the
summary. This is still "one review, submitted once" in the sense that matters — no per-finding
notification-worthy event beyond what the routing below produces, and every call happens in the
same batch with nothing held back for a later pass:

```sh
glab api "projects/$ENC_REPO/merge_requests/$MR/discussions" \
  --method POST \
  -f body="$BODY_1" \
  -f 'position[position_type]=text' \
  -f "position[new_path]=src/auth/token.js" \
  -f "position[new_line]=31" \
  -f "position[head_sha]=$HEAD_SHA" \
  -f "position[base_sha]=$BASE_SHA" \
  -f "position[start_sha]=$START_SHA"

glab mr note "$MR" -R "$REPO" --message "$SUMMARY"
```

**Address the project explicitly; never `projects/:id`.** `:id` is resolved by `glab` from the git
remote of whatever directory the process happens to be standing in, and a dispatched subagent's
working directory is not guaranteed to be the repository under review — so `:id` can silently
resolve to a different project and post this run's review onto a stranger's merge request. `repo`
was handed to this skill exactly so it never has to infer that. `glab mr note "$MR"` carries the
same dependency and needs `-R "$REPO"` for the same reason. **`repo` must be URL-encoded** in the
path: every `/` becomes `%2F`, so `oro/wastequip` is `oro%2Fwastequip` — an unencoded slash splits
the path segment and the API answers 404.

**`position[start_sha]` is `start_sha`, never `base_sha`.** They are different values — measured
live at `base_sha e2c4753` against `start_sha cdc22db` on the same merge request — and `start_sha`
changes on every push, seven diff versions on that one MR. GitLab validates the whole position
triple against a stored diff version, so a triple carrying `base_sha` where `start_sha` belongs
matches no version and the API rejects the comment. Every inline comment then fails, and **Failure
handling** below correctly refuses to fall back — so this one field decides whether the entire
inline set posts or none of it does. If `start_sha` is missing from your dispatch, say so and stop;
do not substitute `base_sha` for it.

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

Corroborated by: <corroborated_by, one "<lens> (<id>): <claim>" per entry, comma-joined>

Existing solution: <existing_solution>
Adoption cost: <adoption_cost>

value <value> · urgency <urgency>
```

The `Also at` line appears only when `also_at` is non-empty — omit the line entirely when the
finding sits at a single location. Do not omit it when it *is* populated: an `extract` finding
usually spans several files, and `target_file`/`target_line` names only the clearest of them, so a
comment that drops `also_at` silently reports one occurrence of a problem the analyst found in
five.

The `Corroborated by` line appears only when `corroborated_by` is non-empty, and it is not
decoration: it names the other lenses that found this same defect independently, at the same
evidence span, which the arbitrator folded into this finding instead of posting twice (see
`../arbitrating-findings/SKILL.md`'s Dedup across lenses). Two lenses reaching the same conclusion
from different starting points is stronger evidence than one lens's opinion, and dropping the line
posts the weaker of the two claims the reviewer was entitled to see.

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
- Writing a finding's text anywhere the shell will expand it — an unquoted heredoc, an unquoted
  command substitution, or between double quotes in the command itself.
- Sending `base_sha` as `position[start_sha]`, or posting inline without `start_sha` at all.
- Addressing the project as `projects/:id`, or calling `glab mr note` with no `-R "$REPO"`.
- Posting one comment per finding instead of one review, submitted once.
- Silently relocating an inline comment to the summary without saying so.
- Retrying with a reduced payload after a failure, or falling back to a plain comment when an
  inline one was intended.
- Writing any file in the repository — this skill posts to the forge, it does not touch disk.
- Using `jq` to build or parse the request. Guardtower deliberately has no tool whose absence
  would silently weaken a run; shelling out to `jq` reintroduces exactly that dependency.
