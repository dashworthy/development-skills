#!/bin/sh
# Structural and behavioural validation for the guardtower plugin.
# POSIX sh. Uses python3 (stdlib only) for JSON. Never requires jq.
# Run from anywhere: sh guardtower/tests/validate.sh

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PLUGIN="$ROOT/guardtower"
fail=0

ok()   { printf 'ok   - %s\n' "$1"; }
bad()  { printf 'FAIL - %s\n' "$1"; fail=1; }
check(){ if [ "$1" -eq 0 ]; then ok "$2"; else bad "$2"; fi }

# Match a prose anchor regardless of how the source is line-wrapped. Prose in these documents is
# wrapped for readability; a check that depends on where the wrap falls breaks on a purely
# cosmetic reflow. Flattens newlines to spaces and collapses runs of whitespace before the literal
# substring search, so a sentence spanning two wrapped lines still matches as one phrase.
#
# `--` before the pattern is load-bearing, not tidiness: without it grep parses an anchor that
# begins with a hyphen — a markdown list item (`- **Also at:** …`) or a command-line flag
# (`--input - <<JSON`) — as its own options and dies with a usage error instead of searching. That
# is a FAILING check for a reason that has nothing to do with the document, and it hid two real
# anchors until they were written.
grep_flat() {  # grep_flat <file> <literal phrase>
  tr '\n' ' ' < "$1" | tr -s ' ' | grep -qF -- "$2"
}

# --- manifest ---------------------------------------------------------------

[ -f "$PLUGIN/.claude-plugin/plugin.json" ]; check $? "plugin.json exists"

if [ -f "$PLUGIN/.claude-plugin/plugin.json" ]; then
  python3 - "$PLUGIN/.claude-plugin/plugin.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
required={"name","description","version","author","license"}
missing=required-set(d)
assert not missing, f"plugin.json missing keys: {sorted(missing)}"
assert d["name"]=="guardtower", f'plugin.json name is {d["name"]!r}, expected "guardtower"'
assert d["version"]=="0.1.0", f'plugin.json version is {d["version"]!r}, expected "0.1.0"'
assert d["license"]=="MIT", f'plugin.json license is {d["license"]!r}, expected "MIT"'
assert d["author"]["email"]=="7387639+andyleach@users.noreply.github.com", "plugin.json author email mismatch"
PY
  check $? "plugin.json is valid and complete"
fi

# --- marketplace entry ------------------------------------------------------

python3 - "$ROOT/.claude-plugin/marketplace.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
e=[p for p in d["plugins"] if p["name"]=="guardtower"]
assert e, "no guardtower entry in marketplace.json"
assert e[0]["source"]=="./guardtower", f'guardtower source is {e[0]["source"]!r}, expected "./guardtower"'
PY
check $? "marketplace.json lists guardtower"

# --- command-only: there must be no hooks directory -------------------------

[ ! -d "$PLUGIN/hooks" ]; check $? "no hooks/ directory (guardtower is command-only)"

# --- README -----------------------------------------------------------------

[ -s "$PLUGIN/README.md" ]; check $? "README.md exists and is non-empty"

# --- shared references ------------------------------------------------------

# Defined here because this is the first appended block that needs it; later
# blocks reuse it rather than redefining it.
CONDUCTOR="$PLUGIN/skills/reviewing-a-pull-request"

for ref in finding-schema scoring-rubric; do
  [ -s "$CONDUCTOR/references/$ref.md" ]; check $? "reference $ref.md exists"
done

# The finding contract must name every field the arbitrator relies on. Each field is anchored
# to the start of its OWN table row (`| \`field\` |`), not a bare substring search — an
# unanchored search is satisfied by, e.g., "evidence" or "claim" appearing inside the
# existing_evidence row's Meaning column, or "tier" inside adoption_cost's Required column, so it
# would not catch that field's own row being deleted.
if [ -s "$CONDUCTOR/references/finding-schema.md" ]; then
  miss=""
  for field in lens target_file target_line evidence claim rationale proposal \
               in_diff also_at kind tier existing_solution existing_evidence adoption_cost; do
    grep -q '^| `'"$field"'` |' "$CONDUCTOR/references/finding-schema.md" || miss="$miss $field"
  done
  [ -z "$miss" ]; check $? "finding-schema.md documents every field (missing:$miss)"

  # Fields the arbitrator owns must be explicitly excluded from analyst output. Anchored to the
  # exclusion sentence itself, not a bare "arbitrator" search — that word appears 10 other times
  # in this file (the field table alone says "assigned by the arbitrator" four times), so it
  # would still pass with the "What the arbitrator owns" section deleted entirely.
  grep_flat "$CONDUCTOR/references/finding-schema.md" 'never set by an analyst'
  check $? "finding-schema.md states which fields the arbitrator assigns"

  # `tier` is a JSON number everywhere, never a string. Pinned because the arbitrator's tier-2
  # adoption_cost requirement is a hard drop condition: a finding whose tier arrives as "2" and is
  # compared against 2 fails that comparison, the requirement never fires, and a tier 2 finding
  # with no stated cost passes a check written specifically to drop it. Anchored to the sentence
  # that pins the type AND to the JSON example's own line, because either alone leaves the other
  # free to drift back to a string.
  grep_flat "$CONDUCTOR/references/finding-schema.md" '`tier` is the one field of those three that is **a JSON number, not a string**' \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" '"tier": 1,'
  check $? "finding-schema.md pins tier to a JSON number"

  # The lens set, anchored to its own table row. `lens` alone recurs everywhere in this file
  # (the return-shape JSON, the `<lens>` in id and path templates), so only the row that
  # enumerates the values catches a fourth lens being re-added or a third being dropped.
  grep_flat "$CONDUCTOR/references/finding-schema.md" '| `lens` | yes | `reuse`, `security`, or `smell` |'
  check $? "finding-schema.md names exactly the three lenses"

  # `kind`'s four values, and the branch conditionality of the three fields that cite an existing
  # solution. Both rows are separately deletable and each is wrong alone: a `kind` row missing
  # `extract` leaves extract findings untypeable and outside the scoring anchor, and a
  # `existing_solution` row still marked "reuse only" tells the arbitrator to demand a field an
  # extract finding cannot have, which drops every one of them. Anchored to each row's own cells,
  # not to the bare field name, which necessarily recurs in the return-shape JSON below.
  grep_flat "$CONDUCTOR/references/finding-schema.md" '| `kind` | every reuse finding | `reimplements`, `duplicates`, `diverges`, or `extract` —' \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" '| `tier` | reuse, not `extract` |' \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" '| `existing_solution` | reuse, not `extract` |' \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" '| `existing_evidence` | reuse, not `extract` |'
  check $? "finding-schema.md admits the extract kind and scopes the existing-solution fields off it"

  # And the prose that says WHY every reuse finding carries a kind — the merge's load-bearing
  # claim, and the one a future editor is most likely to undo by "tidying" kind back to a
  # reuse-branch decoration. Anchored to the two sentences that state the rule and the evidence
  # for it; the rows above would survive either being deleted.
  grep_flat "$CONDUCTOR/references/finding-schema.md" 'so **every** finding it emits carries a `kind`, and `extract` is the value for the second half' \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" 'the same duplicated code scored differently depending on which lens happened to raise it — observed live, at composite 81 and 74 on the same six sites'
  check $? "finding-schema.md states why every reuse finding carries a kind"

  # target_line ranges. All three lenses emitted them on the first live run — their evidence is
  # blocks, not lines — and all three flagged the schema for never saying whether `file:120-127` was
  # allowed. The field's own row said "Line or range" and stopped there, which is why three
  # independent analysts each had to guess the notation. Anchored to the bolded sentence that fixes
  # the FORM, since the row alone was what left it ambiguous, and to the widening of `also_at` to
  # the same two forms, which is separately deletable.
  grep_flat "$CONDUCTOR/references/finding-schema.md" '**A range is valid wherever a line is, and it is written `start-end` — `120-127`, inclusive at both ends.**' \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" '`also_at` takes the same two forms, `file:line` and `file:start-end`.'
  check $? "finding-schema.md documents target_line ranges and their form"

  # …and the counterweight, which matters now that dedup overlaps spans: a range padded out to the
  # enclosing function swallows every unrelated finding in it into one group. The rule above without
  # this one licenses exactly that.
  grep_flat "$CONDUCTOR/references/finding-schema.md" 'The one thing a range is not is a licence to widen.'
  check $? "finding-schema.md forbids widening a range past the evidence"

  # also_at's meaning, which was being used for two different things — further occurrences, and
  # supporting material that corroborates without being an occurrence — while both output surfaces
  # render it as "same problem, also here". The second use inflates the occurrence count the extract
  # bar is measured against, and an `extract` finding is dropped or kept on that count. Three
  # clauses: the definition, where non-occurrence support goes instead, and the separation from
  # cross-lens corroboration, which is a third thing again and belongs to the arbitrator.
  grep_flat "$CONDUCTOR/references/finding-schema.md" '**Every entry in `also_at` is a location where the same pattern this finding names actually occurs**' \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" '**Supporting material that is not an occurrence belongs in `rationale`' \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" 'Cross-lens corroboration is a third thing again and is neither'
  check $? "finding-schema.md defines also_at as occurrences and nothing else"

  # The one extra top-level key, and whose it is. Without this the reuse lens writes a sibling of
  # `findings` that the shared contract does not admit, which is drift in the direction the whole
  # document exists to prevent.
  grep_flat "$CONDUCTOR/references/finding-schema.md" 'the reuse lens writes an **`unanswered`** array holding its null-answer search record' \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" 'No other lens writes it, and nothing else is ever added at that level.'
  check $? "finding-schema.md admits the reuse lens's unanswered array"

  # corroborated_by is arbitrator-owned, like id/value/urgency/composite, and the row plus the
  # ownership sentence are separately deletable. The second clause carries the reason an analyst
  # could not fill it even if it tried, which is what makes the ownership non-arbitrary.
  grep -q '^| `corroborated_by` | no |' "$CONDUCTOR/references/finding-schema.md" \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" '`id`, `value`, `urgency`, `composite`, and `corroborated_by` are never set by an analyst.' \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" 'no lens can see another lens'"'"'s findings, which is why deduping them is a step that happens after all three have returned'
  check $? "finding-schema.md marks corroborated_by as the arbitrator's"

  # The dependency tree's reachability, on the document all three analysts share. The conductor
  # linking `vendor/` in is only half the fix; a lens that still believes an installed package is
  # unreadable goes on declining to assert anything about it.
  grep_flat "$CONDUCTOR/references/finding-schema.md" '**The dependency tree is reachable there.**' \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" 'the conductor links `vendor/`, `node_modules/`, `.venv/` and their equivalents in from the main checkout before dispatching you'
  check $? "finding-schema.md tells analysts the dependency tree is reachable in the worktree"
fi

# The rubric must carry the composite formula, the gate, and the migration anchor. Each is
# anchored to its own specific line/phrase, not a bare substring search — see the FAIL evidence
# in the fix report for why "80" and "migration" alone are satisfied by unrelated text elsewhere
# in this file even after the line they're meant to test is deleted.
RUBRIC="$CONDUCTOR/references/scoring-rubric.md"
if [ -s "$RUBRIC" ]; then
  grep_flat "$RUBRIC" '0.6 × value + 0.4 × urgency'
  check $? "scoring-rubric.md carries the composite weights"

  grep_flat "$RUBRIC" 'Default gate: **80**'
  check $? "scoring-rubric.md carries the default gate"

  grep_flat "$RUBRIC" 'Anchor — a merged duplicate is a migration'
  check $? "scoring-rubric.md carries the merged-duplicate urgency anchor"

  # …and the three kinds it applies to, which is the half that actually decides scoring. The
  # heading anchor above survives the sentence beneath it being narrowed back to two kinds, and
  # that narrowing IS the defect this whole lens merge was made to fix: with `extract` outside the
  # anchor, the same six duplicated sites score 81 or 74 depending only on which remedy the lens
  # chose. Second clause anchors the keys-off-`kind` rule, which is what forbids re-deriving the
  # anchor from the remedy; it is separately deletable and the first clause alone would not miss it.
  grep_flat "$RUBRIC" 'A `reimplements`, `duplicates`, or `extract` finding sits at **70–89** on urgency, not 40–69.' \
    && grep_flat "$RUBRIC" '**The anchor keys off `kind`, and every reuse finding carries one.**'
  check $? "scoring-rubric.md applies the anchor to extract, keyed off kind"

  # The three checks above all target text OUTSIDE the two band tables and the tie-break: the
  # composite line, the gate line, and the merged-duplicate anchor paragraph. Deleting the Value
  # table, the Urgency table and the tie-break together therefore left the whole suite green
  # (proven by mutation), i.e. the criteria the entire rubric exists to publish were deletable
  # undetected. Anchored below to the top and bottom band of each table — so a table gutted down to
  # its middle rows is caught too, not just one deleted wholesale — and to the tie-break's own
  # ranking sentence. Each row is matched on both cells: the score range alone recurs (`40–69` and
  # `70–89` appear in the anchor paragraph and in the smell analyst's honest-expectations note),
  # and the criterion text alone would not prove it is still a table row.
  grep_flat "$RUBRIC" '| 90–100 | Removes a live defect, a security hole, or a data-loss path |' \
    && grep_flat "$RUBRIC" '| 0–39 | Stylistic preference, or defense-in-depth on a path already guarded elsewhere |'
  check $? "scoring-rubric.md carries the Value band table"

  grep_flat "$RUBRIC" '| 90–100 | Ships in this PR and is exploitable or breaking once merged |' \
    && grep_flat "$RUBRIC" '| 0–39 | Cheaper later, or may become moot |'
  check $? "scoring-rubric.md carries the Urgency band table"

  grep_flat "$RUBRIC" '**Tie-break.** Rank by `composite` descending'
  check $? "scoring-rubric.md carries the tie-break"
fi

# --- skills: frontmatter, naming, and cross-references -----------------------

# Every document a markdown file cross-references must exist, resolved against the directory THAT
# FILE lives in — not against a fixed root, because the same citation text means different things
# from a SKILL.md and from a file one level deeper in references/. `[ -f "$_dir/$r" ]` handles the
# embedded ".." itself, so no realpath is needed.
#
# Two target shapes are matched, each behind any chain of `../` and directory components: a
# `references/<name>.md` document, and a `SKILL.md`. Both halves of that pattern were widened after
# M8. The old pattern required a literal `references/` segment and allowed at most one `../` level,
# so it matched neither `../arbitrating-findings/SKILL.md` (cited by the poster for the
# authoritative finding field list) nor `../../surveying-for-reuse/SKILL.md` (cited by
# finding-schema.md's `kind` row for the definitions of `reimplements`/`duplicates`/`diverges`).
# Both are live links a reader is sent to follow, and breaking either left the suite green — proven
# by mutation.
#
# A BARE basename is deliberately NOT matched here, and that is not an oversight to fix later. The
# run artifacts are part of the reason but NOT the blocking one, so do not read this as "skip-list
# three names and the widening works" — that was tried and it still fails. Precisely:
#
#   * `brief.md` and `deferred.md` do occur bare (arbitrating-findings/SKILL.md:156,
#     posting-review-comments/SKILL.md:14 and :142, reviewing-a-pull-request/SKILL.md:40 and :182).
#     They name paths under `.guardtower/<run>/` that exist only at runtime and have no counterpart
#     on disk, so matching them would FAIL against a correct tree. `approved.md` never occurs bare
#     at all — only ever as `.guardtower/<run>/approved.md`, which the leading `/` already excludes.
#
#   * The case that still fails with all three skip-listed is a SHORTHAND BACK-REFERENCE.
#     arbitrating-findings/SKILL.md:166 reads "Inventing scoring criteria instead of applying
#     `scoring-rubric.md` as written" — a deliberately short second mention of the document whose
#     authoritative full path the SAME file already gives at :63
#     (`../reviewing-a-pull-request/references/scoring-rubric.md`). It resolves for a human reader
#     via that earlier line, and it cannot resolve in-dir, because the file lives in another skill's
#     directory. No skip list fixes that; the only way to make a global bare-basename match pass
#     would be to lengthen correct prose to satisfy a test.
#
# Where a bare basename IS the natural and correct relative form — a sibling citation between two
# files in the same references/ directory — it is checked separately and scoped to that directory,
# where no shorthand back-reference of the kind above occurs. See "reference documents: sibling
# citations exist" below.
check_links() {  # check_links <file> <label prefix>
  _dir=$(dirname "$1")
  missing=""
  for r in $(grep -Eo '(\.\./)*([a-z0-9-]+/)*(references/[a-z0-9-]+|SKILL)\.md' "$1" | sort -u); do
    [ -f "$_dir/$r" ] || missing="$missing $r"
  done
  [ -z "$missing" ]; check $? "$2: all referenced files exist (missing:$missing)"
}

check_skill() {
  d="$PLUGIN/skills/$1"
  f="$d/SKILL.md"

  [ -s "$f" ]; check $? "skill $1: SKILL.md exists"
  [ -s "$f" ] || return 0

  # Frontmatter must open on line 1 and carry exactly name + description.
  head -1 "$f" | grep -q '^---$'; check $? "skill $1: frontmatter opens on line 1"

  fm=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f{print}' "$f")

  n=$(printf '%s\n' "$fm" | sed -n 's/^name: *//p' | head -1)
  [ "$n" = "$1" ]; check $? "skill $1: frontmatter name matches directory (got '$n')"

  printf '%s\n' "$fm" | grep -q '^description: '
  check $? "skill $1: frontmatter has a description"

  # [a-zA-Z0-9_-] on purpose, not [a-z_]: a hyphenated key such as allowed-tools or
  # argument-hint — exactly the extra frontmatter fields a Claude Code skill author reaches for —
  # would otherwise not match the old narrower class at all, silently vanish from $keys, and let a
  # three-key frontmatter pass this as if it carried only name+description.
  keys=$(printf '%s\n' "$fm" | sed -n 's/^\([a-zA-Z0-9_-]*\): .*/\1/p' | sort -u | tr '\n' ' ')
  [ "$keys" = "description name " ]; check $? "skill $1: frontmatter has only name+description (got '$keys')"

  # Every document this skill cites must exist. Discovered by Task 4: an analyst skill legitimately
  # cites a reference file that lives in the conductor's directory, not its own, so the citation has
  # to resolve against $d rather than being truncated to its last two components and checked against
  # the wrong directory. See check_links above for the pattern and for why a bare basename is
  # excluded from it.
  check_links "$f" "skill $1"

  # House style: every skill ends with a "Red flags — STOP" section. Anchored to the heading
  # itself (line start, level-2, exact phrase) rather than a bare "Red flags" substring search —
  # the phrase could otherwise be satisfied by a stray mention in body prose with the actual
  # section deleted.
  grep -q '^## Red flags — STOP' "$f"; check $? "skill $1: has a 'Red flags — STOP' section"
}

check_skill reviewing-a-pull-request

# $CONDUCTOR was defined by Task 2's block, which runs above this one.
for ref in brief-template; do
  [ -s "$CONDUCTOR/references/$ref.md" ]; check $? "reference $ref.md exists"
done

# The conductor must carry the invariants that make the design hold. Each check is anchored to
# the concrete, load-bearing artifact the invariant produces — an exact command, an exact path, or
# a distinctive sentence — rather than a single common word ("worktree", "receipt", ".guardtower/")
# that section headers, JSON snippets, and ordinary prose could satisfy coincidentally in a
# document this size, with the section the word actually names deleted entirely.
C="$CONDUCTOR/SKILL.md"
if [ -s "$C" ]; then
  grep_flat "$C" 'git worktree add --detach'
  check $? "conductor: uses a worktree"

  grep_flat "$C" 'git diff --numstat HEAD'
  check $? "conductor: snapshots with numstat"

  # Anchored to the exact bolded sentence, not a bare case-insensitive "auto-revert" substring —
  # the Red flags list separately says "Auto-reverting a reconciliation violation...", a different
  # phrasing that would keep an unanchored search passing even with this sentence, and the whole
  # rule it belongs to, deleted.
  grep_flat "$C" '**Never auto-revert.**'
  check $? "conductor: forbids auto-revert"

  # The full one-liner, not just "/dev/urandom" — LC_ALL=C and | head -c 6 are both load-bearing
  # (byte-safe character class, and the six-character minimum) and a shortened grep would still
  # pass with either dropped from the actual command.
  grep_flat "$C" "LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6"
  check $? "conductor: run id generation is the full urandom one-liner"

  grep_flat "$C" '<YYYY-MM-DD>-<pr-number>-<suffix>'
  check $? "conductor: run id format is specified"

  # Two separate claims, honestly labeled: this one is the stated *consequence* of an analyst
  # returning a finding instead of a receipt, not the receipt format itself — see the next check.
  grep_flat "$C" 'the firewall has already failed'
  check $? "conductor: states the firewall-failure consequence of reading a finding"

  # The actual receipt contract analysts return. Previously unchecked — this could have been
  # deleted with nothing in the suite noticing.
  grep_flat "$C" 'wrote <N> findings to <output_path>'
  check $? "conductor: names the analyst receipt format"

  # Three specific paths from the artifact layout, not a bare '\.guardtower/' substring search —
  # that matched the JSON dispatch-brief line, a Red-flags bullet, and three other unrelated
  # sentences, so the entire Disk layout could be deleted while any one surviving mention of the
  # bare word ".guardtower/" kept a single check green.
  grep_flat "$C" '.guardtower/<run>/findings/<lens>.json'
  check $? "conductor: names the findings path in the artifact layout"

  grep_flat "$C" '.guardtower/<run>/approved.md'
  check $? "conductor: names approved.md in the artifact layout"

  grep_flat "$C" '.guardtower/<run>/deferred.md'
  check $? "conductor: names deferred.md in the artifact layout"

  # Three dispatch sites, three payloads, one uniform anchor each. The poster's is checked further
  # down (it was added with Task 9); these two close the other two. Every one of them was written
  # after the same bug: a dispatch site handing over a subset of the fields the dispatched skill
  # declares it receives, so the skill is told to consult fields it was never given, and nothing in
  # the suite noticed because no single task's diff contained both ends.
  #
  # The analysts', from **The pass**. Anchored as ONE contiguous span — from `worktree` through the
  # opening of `output_path` — and asserted against the conductor AND all three analyst skills with
  # the same string, because this is the one payload that has to agree in four places at once: the
  # conductor renders it, and each analyst declares it under "What you receive". Four independent
  # per-file anchors would each prove its own file says something; only a shared span proves the
  # four say the same thing, which is the drift this suite has been bitten by before.
  #
  # The span starts at `worktree` and stops inside `output_path`'s value because those are the
  # boundaries of what is genuinely common: `lens` carries the three-way alternation in the
  # conductor and a single literal in each analyst, and `output_path` ends in `<lens>.json` versus
  # `reuse.json`/`security.json`/`smell.json`. Being contiguous, it catches insertion as well as
  # deletion — a field added anywhere between `worktree` and `output_path` breaks the match in
  # whichever document gained it.
  BRIEF_SPAN='"worktree": "<absolute path to the detached worktree>", "base_sha": "<PR base sha>", "head_sha": "<PR head sha>", "changed_paths": ["<repo-relative path>", ...], "output_path": "<absolute path to .guardtower/<run>/findings/'
  miss=""
  for doc in "$C" \
             "$PLUGIN/skills/surveying-for-reuse/SKILL.md" \
             "$PLUGIN/skills/reviewing-for-security/SKILL.md" \
             "$PLUGIN/skills/detecting-code-smell/SKILL.md"; do
    [ -s "$doc" ] && grep_flat "$doc" "$BRIEF_SPAN" || miss="$miss ${doc#"$PLUGIN"/}"
  done
  [ -z "$miss" ]
  check $? "the analyst dispatch brief agrees field-for-field across the conductor and all three analysts (mismatched:$miss)"

  # The brief's TAIL, added after the first live run and asserted the same way and across the same
  # four documents. BRIEF_SPAN above deliberately stops inside `output_path`'s value, because that
  # value is the one thing that legitimately differs between the conductor (`<lens>.json`) and each
  # analyst (`reuse.json`, `security.json`, `smell.json`) — so the two fields AFTER it cannot join
  # that span and need one of their own. They are byte-identical in all four documents by design,
  # which is what makes a shared span possible at all.
  #
  # What they close: the brief carried a `lens` and no path to that lens's SKILL.md, and told the
  # analyst to write "the shape finding-schema.md defines" with no path to that document either. The
  # live conductor supplied both in prose at dispatch time — the right instinct, the wrong
  # mechanism, since an improvised sentence does not survive to the next run.
  #
  # `schema_path`'s value is deliberately the BARE basename, not `references/finding-schema.md`:
  # check_links resolves any `references/<name>.md` it finds against the file's own directory, and
  # an analyst skill is not in the conductor's directory, so the pathier form makes four correct
  # documents fail a link check over a placeholder that was never a link.
  #
  # The span begins at `.json>", ` — the TAIL of output_path's value — and not at `"skill_path"`,
  # which is where it was first written. Proven by mutation: deleting both tail lines from the
  # conductor's ANALYST BRIEF left this check green, because the conductor's ARBITRATOR payload
  # ends in the same two lines verbatim and satisfied the search on its own. Starting inside
  # output_path's value pins the span to the analyst brief in every one of the four documents,
  # while staying byte-identical across them — the value's differing head (`<lens>.json` versus
  # `reuse.json`) is left outside the anchor, exactly as BRIEF_SPAN leaves it. Being contiguous
  # from there, it also catches a field inserted between output_path and skill_path.
  BRIEF_TAIL='.json>", "skill_path": "<absolute path to the SKILL.md this dispatch names>", "schema_path": "<absolute path to finding-schema.md>"'
  miss=""
  for doc in "$C" \
             "$PLUGIN/skills/surveying-for-reuse/SKILL.md" \
             "$PLUGIN/skills/reviewing-for-security/SKILL.md" \
             "$PLUGIN/skills/detecting-code-smell/SKILL.md"; do
    [ -s "$doc" ] && grep_flat "$doc" "$BRIEF_TAIL" || miss="$miss ${doc#"$PLUGIN"/}"
  done
  [ -z "$miss" ]
  check $? "the analyst dispatch brief names the skill and the schema in all four documents (mismatched:$miss)"

  # …and the shared prose that tells an analyst what to DO with them, asserted across the three
  # analysts. The span above proves the fields are handed over; nothing in it proves any analyst was
  # told to open the contract, and an analyst that never opens it writes to a shape reconstructed
  # from memory. Identical wording in all three on purpose, for the same reason the payload is.
  ANALYST_PATHS='`skill_path` is this document and `schema_path` is the finding contract you write to — open the contract before you write anything'
  miss=""
  for doc in "$PLUGIN/skills/surveying-for-reuse/SKILL.md" \
             "$PLUGIN/skills/reviewing-for-security/SKILL.md" \
             "$PLUGIN/skills/detecting-code-smell/SKILL.md"; do
    [ -s "$doc" ] && grep_flat "$doc" "$ANALYST_PATHS" || miss="$miss ${doc#"$PLUGIN"/}"
  done
  [ -z "$miss" ]
  check $? "every analyst is told to open the contract skill_path and schema_path name (mismatched:$miss)"

  # And that every analyst knows the dependency tree is reachable. This is the half of the vendor
  # fix that lives on the reading side: the conductor can link `vendor/` in, but a lens that still
  # believes an installed package is a black box goes on declining to assert anything about it —
  # which is exactly what the live security analyst did, at the cost of a candidate finding.
  DEP_REACH='The worktree also carries the repository'"'"'s **installed dependency tree**'
  miss=""
  for doc in "$PLUGIN/skills/surveying-for-reuse/SKILL.md" \
             "$PLUGIN/skills/reviewing-for-security/SKILL.md" \
             "$PLUGIN/skills/detecting-code-smell/SKILL.md"; do
    [ -s "$doc" ] && grep_flat "$doc" "$DEP_REACH" || miss="$miss ${doc#"$PLUGIN"/}"
  done
  [ -z "$miss" ]
  check $? "every analyst is told the installed dependency tree is reachable in the worktree (mismatched:$miss)"

  # The dispatch set the conductor declares exhaustive. Anchored to the sentence that enumerates
  # it, because that list is the only place a run's five dispatches are named together — and it is
  # the surface a deleted lens leaves an orphan on. A bare `surveying-for-reuse` search would be
  # satisfied by the `The pass` section naming the same skill for a different purpose, with this
  # sentence and its "nothing else is dispatched" guarantee gone. Two clauses: the enumeration and
  # the exhaustiveness claim, which are separately deletable and each incomplete alone.
  grep_flat "$C" 'Five named skills get dispatched over the course of a run: one of `surveying-for-reuse`, `reviewing-for-security`, `detecting-code-smell` per selected lens; then `arbitrating-findings`; then, only after triage, `posting-review-comments`.' \
    && grep_flat "$C" 'That list is exhaustive: every dispatch a run makes follows one of those named skills, and nothing else is dispatched.'
  check $? "conductor: names the five dispatched skills and calls the list exhaustive"

  # The conductor's own copy of the lens set, in the brief it renders. The BRIEF_SPAN above
  # deliberately starts AFTER `lens` (its value differs between conductor and analyst), so nothing
  # asserted the alternation itself — re-adding a fourth lens here, or dropping one, left the suite
  # green. Anchored to the rendered line.
  # grep_flat collapses runs of whitespace, so the brief's column alignment is normalised away
  # before the match — which is what lets this anchor survive a future realignment of that JSON
  # block without weakening what it asserts.
  grep_flat "$C" '"lens": "reuse | security | smell",'
  check $? "conductor: the dispatch brief offers exactly the three lenses"

  # The arbitrator's. `threshold` and `worktree` are the load-bearing two: without the first, the
  # gate the user agreed at preflight step 7 is silently discarded and the arbitrator falls back to
  # its own example value; without the second, evidence is verified against the user's checked-out
  # tree instead of the detached worktree — a silent wrong answer from the step the whole design
  # rests on. Anchored to the paragraph that names them, not to the field names, which also appear
  # in the JSON block and would survive its deletion — the same shape as the poster's check below.
  grep_flat "$C" 'Name every field. `threshold` is not optional decoration'
  check $? "conductor: names the arbitrator payload, not just the finding paths"

  # …and the payload the prose is ABOUT. The check above anchors only the justifying prose, on the
  # deliberate reasoning that the field names also appear in the JSON block and would survive its
  # deletion. That reasoning is right for what it covers and covers only one of two halves: deleting
  # the `threshold` and `lenses_run` lines FROM the JSON block, leaving the prose untouched, left the
  # whole suite at PASS, exit 0 — proven by mutation. `threshold` is the one that matters most: it is
  # the gate the user agreed at preflight step 7, and losing it from the rendered payload is exactly
  # the silent discard the prose above exists to prevent, with the sentence forbidding it still on
  # the page. Two clauses, one per field, since each line is separately deletable.
  #
  # The `lenses_run` anchor carries the block's closing brace because that same line, verbatim,
  # also appears in the poster dispatch payload further down; without the brace this check would
  # stay green on the poster's copy with the arbitrator's deleted.
  # The `lenses_run` clause used to carry the block's closing brace, because that line verbatim also
  # appears in the POSTER payload further down and would otherwise stay green on the poster's copy
  # with the arbitrator's deleted. The arbitrator block no longer ends there — `skill_path` and
  # `schema_path` follow it — so the disambiguator moves to the field that follows: `lenses_run`
  # immediately followed by `skill_path` occurs only here, since the poster's `lenses_run` is
  # followed by `lenses_skipped`.
  grep_flat "$C" '"threshold": "<the value agreed in preflight step 7>",' \
    && grep_flat "$C" '"lenses_run": ["<lens>", "..."], "skill_path":'
  check $? "conductor: the arbitrator dispatch payload carries threshold and lenses_run"

  # …and the remaining four, anchored as ONE contiguous span rather than per field. Per-field
  # clauses were tried first and two of them did not bind: `"base_sha": "<from preflight step 3>",`
  # and the `head_sha` line are byte-identical to lines in the POSTER payload block further down,
  # so deleting them from the arbitrator block left a matching copy behind and the suite stayed
  # green. The span starts at `finding_paths`, which appears in no other block, so removing any
  # field in it breaks the match. The cost is that a failure names the block rather than the field;
  # the comment above says which fields are load-bearing and why, which is what a reader needs.
  #
  # Widened from six fields to eight after the first live run: `skill_path` and `schema_path` were
  # added because the payload named a job and no document defining it, so the arbitrator was told to
  # score against `scoring-rubric.md` with no way to resolve a relative citation from a directory
  # nothing told it it was standing in. They sit at the end of the same contiguous span for the same
  # reason the other six do — insertion breaks the match as surely as deletion.
  grep_flat "$C" '"finding_paths": ["<each dispatched analyst'"'"'s output_path>"], "worktree": "<absolute path from preflight step 5>", "base_sha": "<from preflight step 3>", "head_sha": "<from preflight step 3>", "threshold": "<the value agreed in preflight step 7>", "lenses_run": ["<lens>", "..."], "skill_path": "<absolute path to the SKILL.md this dispatch names>", "schema_path": "<absolute path to finding-schema.md>"'
  check $? "conductor: the arbitrator dispatch payload carries all eight fields"

  # `repo` was the one poster-payload field with a shape but no source: no preflight step produced
  # it, since step 1 read the origin URL only to detect the forge and step 3's `gh pr view` does
  # not request it. Anchored to the sentence in step 1 that makes the origin URL its provenance.
  grep_flat "$C" 'The path portion is the only place `repo` comes from'
  check $? "conductor: preflight step 1 is where repo comes from"

  # …and the OTHER half of step 1, added after the first live run: the origin URL's HOST, exported
  # as GITLAB_HOST before any glab call. Unset, every glab call targets gitlab.com, so step 2's
  # `glab auth status` reports unauthenticated against a host the user has no account on and
  # PREFLIGHT HALTS ON A CORRECTLY-CONFIGURED MACHINE. The word GITLAB_HOST appeared nowhere in the
  # plugin before this. Two clauses: the export line itself (the only place the derivation is
  # written down) and the consequence sentence, which is what stops a future editor deleting the
  # line as redundant. The export is anchored on the sed pipeline, not on the bare variable name,
  # which also appears in the surrounding prose.
  grep_flat "$C" "export GITLAB_HOST=\$(printf '%s' \"\$ORIGIN\" | sed -e 's|^[a-z+]*://||' -e 's|^[^@]*@||' -e 's|[:/].*\$||')" \
    && grep_flat "$C" 'preflight halts on a correctly-configured machine'
  check $? "conductor: exports GITLAB_HOST from the origin host before any glab call"

  # Preflight's cwd, and where .guardtower/ is rooted. The live conductor ran preflight in the
  # PLUGIN repo, whose origin is a different remote entirely — so forge detection and PR resolution
  # both answered about the wrong project without erroring. Anchored to the bolded sentence and to
  # the artifact-root half, which is separately deletable and is what keeps run artifacts inside the
  # tree Reconcile actually measures.
  grep_flat "$C" '**Every step below runs with the working directory inside the repository under review**' \
    && grep_flat "$C" '`.guardtower/<run>/` is rooted at that same repository'"'"'s root'
  check $? "conductor: preflight runs in the repo under review, and roots .guardtower/ there"

  # Step 3's resolve commands. `glab mr view <n>` returns title, state, author, labels, url and a
  # comment count — none of the three shas, none of the changed paths — so the step named a command
  # that cannot answer it. Three clauses: the GitLab API call that can, the diff_refs extraction
  # that keeps the response out of this context, and the explicit statement that `glab mr view` is
  # not the command. The third is what stops the first being "simplified" back.
  grep_flat "$C" 'glab api "projects/$ENC_REPO/merge_requests/<n>"' \
    && grep_flat "$C" 'json.load(sys.stdin)["diff_refs"]; print(r["base_sha"], r["start_sha"], r["head_sha"])' \
    && grep_flat "$C" '**`glab mr view <n>` is not the command for this step**'
  check $? "conductor: resolves the MR through the API that returns diff_refs, not glab mr view"

  # start_sha's provenance and the reason it is not base_sha. Measured live: base_sha e2c4753,
  # start_sha cdc22db, and start_sha changes on every push. Anchored to the sentence carrying the
  # measured values — a bare `start_sha` search would be satisfied by the payload block, the
  # command, or the Red flags item with this whole justification deleted, and the justification is
  # precisely what stops a future editor collapsing the two fields back into one.
  grep_flat "$C" '**`start_sha` comes from `diff_refs`, and it is not `base_sha`.**' \
    && grep_flat "$C" 'a position built with `start_sha` set to `base_sha` matches no version at all and every inline comment is rejected'
  check $? "conductor: resolves start_sha and says why it is not base_sha"

  # Rule two's newest breach: `glab mr view` prints the entire MR description — ~2,500 words of
  # architecture narrative on the live MR — into the very step that says the conductor never reads
  # diff contents. Anchored to the bolded prohibition and to the reason, which is the half that
  # distinguishes this from an arbitrary rule: it is not a diff, but it primes every downstream
  # judgement all the same.
  grep_flat "$C" '**The MR title and description must not enter this context.**' \
    && grep_flat "$C" 'reading it primes every downstream judgement the conductor is supposed to make on the arbitrator'"'"'s numbers alone'
  check $? "conductor: keeps the MR title and description out of its own context"

  # The dependency link. A detached worktree is a clean checkout, so every gitignored dependency
  # tree is absent — and both lenses that needed one lost findings to it on the live run. Three
  # clauses: the symlink loop (the mechanism), the consequence sentence (why it is not optional),
  # and the safety argument (why read-only reuse of the main checkout is allowed at all, which is
  # the objection a future editor will raise before deleting it).
  grep_flat "$C" 'ln -s "$MAIN/$dep" "$WORKTREE/$dep"' \
    && grep_flat "$C" '**Without this, two lenses silently shrink.**' \
    && grep_flat "$C" 'Read-only reuse of the main checkout'"'"'s dependency tree is safe: nothing in a run writes through the link.'
  check $? "conductor: links the dependency tree into the worktree, read-only"
fi

# --- the conductor's dispatched reference document -----------------------------
#
# brief-template.md had an existence check and nothing else: reducing it to the single character "x"
# on a scratch copy left the suite reporting 105 ok, PASS. That is not a small gap — it is the render
# contract between the arbitrator's return and the human doing triage, so a placeholder missing from
# it is a column missing from the only document the human decides on.

BRIEF="$CONDUCTOR/references/brief-template.md"
if [ -s "$BRIEF" ]; then
  # The three-outcome summary. All three rows together, because the whole point of the table is
  # that dropped and discarded are reported separately from each other and from passed.
  grep_flat "$BRIEF" '| Passed the gate | {{PASSED_COUNT}} |' \
    && grep_flat "$BRIEF" '| Dropped on evidence | {{DROPPED_COUNT}} |' \
    && grep_flat "$BRIEF" '| Discarded by gate | {{DISCARDED_COUNT}} |'
  check $? "brief-template.md: renders all three outcome counts"

  grep_flat "$BRIEF" '**Threshold:** {{THRESHOLD}}' \
    && grep_flat "$BRIEF" '**Lenses skipped:** {{LENSES_SKIPPED}}'
  check $? "brief-template.md: names the threshold and the lenses that were skipped"

  grep_flat "$BRIEF" '### {{ID}} — {{TARGET_FILE}}:{{TARGET_LINE}}'
  check $? "brief-template.md: heads each finding with its id and location"

  # The composite alone is not the contract — the brief must show the two numbers it was computed
  # from, or a reader cannot tell a 93 built from value 95 from a 93 built from urgency 95.
  grep_flat "$BRIEF" '- **Composite:** {{COMPOSITE}} (value {{VALUE}} / urgency {{URGENCY}})'
  check $? "brief-template.md: breaks the composite out into value and urgency"

  # also_at is produced by every analyst and was consumed by neither output surface: this template
  # had no slot for it and the poster's comment body had none either, so for an `extract` finding —
  # which "usually spans several files" — every location but one was silently dropped at both.
  # Anchored to the line and to the omit-when-empty instruction that makes it renderable.
  grep_flat "$BRIEF" '- **Also at:** {{ALSO_AT}}' \
    && grep_flat "$BRIEF" 'The Also at line exists only on a finding whose also_at array is non-empty'
  check $? "brief-template.md: renders also_at, omitted when empty"

  # The reuse-conditional lines, whose conditions are no longer uniform: Kind is on every reuse
  # finding, Tier and Existing solution on every reuse finding EXCEPT extract. A template that
  # still says "the Kind, Tier, and Existing solution lines exist only on a reuse finding" renders
  # an empty Tier and Existing solution on every extract finding, which is the drift this check
  # exists for. Anchored to both halves of the instruction, since each is separately deletable.
  # Each clause is confined to a single comment line: grep_flat normalises the wrap, but the
  # `-->`/`<!--` delimiters between lines are real characters that survive the flattening, so an
  # anchor spanning two lines of an HTML comment block can never match.
  grep_flat "$BRIEF" 'The Kind line exists on every reuse finding, whatever its kind' \
    && grep_flat "$BRIEF" 'reimplements, duplicates or diverges, and NOT on one whose kind is'
  check $? "brief-template.md: scopes Kind to every reuse finding and Tier/Existing solution off extract"

  # The arbitrator's dedup produces corroboration, and the brief is where it has to land: dedup that
  # reports one entry and renders nothing about the other lenses is indistinguishable, to the
  # reader, from dedup that threw them away. Two clauses for the same reason as the `Also at` pair
  # above — the placeholder without the rule renders an empty label on every uncorroborated finding,
  # and the rule without the placeholder governs a line the template does not have.
  grep_flat "$BRIEF" '- **Corroborated by:** {{CORROBORATED_BY}}' \
    && grep_flat "$BRIEF" 'The Corroborated by line exists only on a finding whose corroborated_by array is non-empty'
  check $? "brief-template.md: renders corroborated_by, omitted when empty"
fi

# The reference documents' OWN cross-references, which check_skill never sees: it is called once per
# skill and reads only that skill's SKILL.md, so a link written inside references/ was unvalidated
# no matter how it was spelled. finding-schema.md's `kind` row is the live case — it sends the
# reader to `../../surveying-for-reuse/SKILL.md` for the definitions of the three values that row
# admits, and the definitions genuinely live only there. Proven by mutation: repointing that link at
# a file that does not exist left the whole suite green.
for ref in "$CONDUCTOR"/references/*.md; do
  [ -f "$ref" ] && check_links "$ref" "reference $(basename "$ref")"
done

# The one citation shape check_links cannot match globally: a BARE basename. Between two files in
# the same references/ directory that is the natural relative form, and finding-schema.md:68 uses
# it — the "What the arbitrator owns" section sends the reader to `scoring-rubric.md` for the bands
# `value` and `urgency` are scored against. It was the last cross-reference in the plugin with
# nothing asserting its target exists: proven by mutation, misspelling it to `scoring-rubrik.md`
# left the whole suite at PASS, exit 0.
#
# Scoped to references/*.md on purpose. That directory is exactly where a bare basename is correct
# and where the shorthand back-reference that blocks the same widening in skills/ does not occur —
# see check_links' comment above for that case. The three runtime artifacts are still excluded by
# name, for the reason given there; two of them never appear in this directory at all, but the
# exclusion travels with the pattern so a future reference document may name them freely.
missing=""
for ref in "$CONDUCTOR"/references/*.md; do
  [ -f "$ref" ] || continue
  # `sed 's/^/ /'` is load-bearing, not cosmetic: the delimiter class below must match SOMETHING,
  # and writing it optional as `(^|[^...])` is not available — BSD grep -Eo, which is what macOS
  # ships, silently matches nothing when `^` appears inside an alternation. Prefixing every line
  # with a space guarantees a line-initial citation still has a delimiter to consume. The trailing
  # sed then strips back to the last character that cannot be part of a basename, which is
  # byte-safe and so survives a multi-byte delimiter such as an em dash.
  for r in $(sed 's/^/ /' "$ref" \
             | grep -Eo '[^/A-Za-z0-9._-][a-z0-9-]+\.md' \
             | sed 's/.*[^a-z0-9.-]//' | sort -u); do
    case " brief.md approved.md deferred.md " in *" $r "*) continue ;; esac
    [ -f "$(dirname "$ref")/$r" ] || missing="$missing $(basename "$ref"):$r"
  done
done
[ -z "$missing" ]; check $? "reference documents: sibling citations exist (missing:$missing)"

# --- the reuse analyst -------------------------------------------------------

check_skill surveying-for-reuse

R="$PLUGIN/skills/surveying-for-reuse/SKILL.md"
if [ -s "$R" ]; then
  # Each finding kind is anchored to its own verbatim spec definition sentence, not the bare kind
  # name — even backtick-quoted, the bare name is insufficient: "reimplements" and "duplicates"
  # both recur backtick-quoted in the Scoring input section's urgency-anchor callout ("every
  # `reimplements` or `duplicates` finding"), so a bare-name search (proven by mutation) still
  # passes with the entire "Three kinds of finding" section deleted. Each definition's own
  # sentence, by contrast, appears nowhere else in the file.
  grep_flat "$R" 'the PR builds a capability that already exists whole'
  check $? "reuse: names the 'reimplements' finding kind"
  grep_flat "$R" 'specific logic repeated from an existing local implementation'
  check $? "reuse: names the 'duplicates' finding kind"
  grep_flat "$R" 'leaving two patterns where there was one'
  check $? "reuse: names the 'diverges' finding kind"

  # Anchored to the tier table's own row labels, not the bare phrases "tier 1"/"tier 2" — those
  # also occur inside "tier 2 only" (the adoption_cost field's own description) and in the Red
  # flags item about a tier-2 finding, so a bare search would still pass with the tier table
  # itself deleted.
  grep_flat "$R" '1 — already reachable' && grep_flat "$R" '2 — not yet installed'
  check $? "reuse: defines both tiers"

  # Anchored to the specific normative sentence, not a bare "adoption_cost" search — that field
  # name necessarily also appears in the Return format JSON schema and in the Red flags list
  # regardless of whether the tier-2 requirement is ever actually stated in prose.
  grep_flat "$R" 'Set `adoption_cost` whenever `tier` is `2`'
  check $? "reuse: requires adoption_cost for tier 2"

  # And that the analyst is told to WRITE tier as a number, since the requirement above is only
  # enforceable if the arbitrator's `tier: 2` comparison actually matches. The type was previously
  # string-shaped here and integer-shaped in the plan's arbitrator interface; nothing tied them.
  grep_flat "$R" 'Write `tier` as **a JSON number, `1` or `2` — never the string `"2"`**' \
    && grep_flat "$R" '"tier": 1,'
  check $? "reuse: writes tier as a JSON number"

  # Anchored to the sentence naming both evidence fields together, not a bare "existing_evidence"
  # search — that field name also appears standalone in the Return format JSON schema.
  grep_flat "$R" '`existing_solution` and `existing_evidence`'
  check $? "reuse: requires the second half of evidence"

  # Exact-cased, punctuated match on the spec's own bolded sentence — not case-insensitive on the
  # bare phrase, which a much weaker sentence ("silence is not a substitute for looking") could
  # also satisfy without carrying the spec's actual wording.
  grep_flat "$R" 'Silence is not a null answer.'
  check $? "reuse: silence is not a null answer"

  # The distinctive half of the spec's own counter-example sentence — "lodash" alone would also
  # match a stray mention in unrelated prose (e.g. an adoption_cost example), so this anchors to
  # the actual worked example rather than the word appearing anywhere.
  grep_flat "$R" 'Import lodash for a three-line'
  check $? "reuse: carries the concrete tier-2 counter-example"

  # --- the extract half of the lens, absorbed from the deleted abstraction analyst -------------
  #
  # Everything below covers content that used to live in
  # skills/simplifying-through-abstraction/SKILL.md and had its own validator block. That skill was
  # deleted and its content merged here, so these anchors are retargeted at $R rather than dropped:
  # a merge that loses the absorbed document's load-bearing rules is the failure mode the whole
  # exercise is exposed to, and an anchor that moved with the prose is the only thing that catches
  # it.

  # The fourth kind, anchored to its own definition sentence for the same reason as the three
  # above: the bare word "extract" recurs (the branch is named in the decision tree, the precedence
  # rule, the scoring section and the Red flags), so only this sentence proves the taxonomy entry
  # itself survives.
  grep_flat "$R" 'nothing already solves this, and the PR'"'"'s own shape repeats often enough to have earned an abstraction that does not exist yet'
  check $? "reuse: names the 'extract' finding kind"

  # `kind` on EVERY finding, which is the claim the scoring anchor rests on. Without it the field
  # drifts back to a reuse-branch decoration and identical duplication scores two ways again —
  # the exact live-run defect. Anchored to the normative sentence, not the field name, which
  # necessarily appears in the Return format JSON regardless.
  grep_flat "$R" 'Set `kind` to exactly one of these four values, on **every** finding this lens emits.'
  check $? "reuse: sets kind on every finding, not just the reuse branch"

  # The precedence rule that makes one lens out of two. Deleting it leaves a lens that can answer
  # a duplication with either remedy at random — which is what two lenses did, and the reason
  # there is now one. Two clauses: the bolded rule and the decision tree's own branch lines, which
  # are separately deletable and each incomplete alone (the rule without the tree states an order
  # with no procedure; the tree without the rule shows two branches with nothing saying which wins).
  grep_flat "$R" '**Existing beats new, always.**' \
    && grep_flat "$R" 'does something already solve this? yes → reuse finding — the remedy is to use it no → does the shape repeat enough to earn an abstraction?'
  check $? "reuse: existing-beats-new precedence, stated as a rule and as a tree"

  # The absorbed defining rule. The abstraction skill's own check anchored only the speculative
  # sentence; the coincidence line beside it is separately deletable and is the half that carries
  # the actual threshold, so both are asserted. The brief's original literal check here was
  # `grep -qi 'premature\\|speculative'` — a bare case-insensitive word search that would pass on any
  # stray use of the word with the rule itself gone.
  grep_flat "$R" 'An abstraction proposed for a case that has not happened yet is speculative, and speculative abstraction costs more than the duplication it prevents.' \
    && grep_flat "$R" '*Two occurrences is a coincidence; three is a pattern.*'
  check $? "reuse: abstraction is earned, never anticipated"

  # The six complexity shapes, each paired with the pattern that tames it. Anchored on all six
  # rather than the first and last, because top-and-bottom would catch the list being deleted
  # wholesale but not gutted down to its middle — the same failure mode the rubric band tables are
  # anchored against, and here it matters more: each shape is independently useful and the list is
  # the lens's entire "what to look for" surface. Each clause carries the shape AND its remedy, so
  # a bullet stripped back to a bare symptom with no pattern to reach for is caught too.
  grep_flat "$R" 'chain that keeps growing as new cases arrive → a table or strategy map' \
    && grep_flat "$R" 'copied at each call site → one policy object the call sites share' \
    && grep_flat "$R" 'implicit in the call graph → an explicit pipeline' \
    && grep_flat "$R" 'no shared record of which transitions are legal → a state machine' \
    && grep_flat "$R" 'rebuilt with slightly different constants at each call site → one retry policy' \
    && grep_flat "$R" 'every switch already written over it → polymorphism or one dispatch table'
  check $? "reuse: carries all six complexity shapes with the pattern that tames each"

  # The cost rule. Without it the lens proposes indirection with only its upside stated, which is
  # how a review acquires abstractions nobody asked for. Anchored to the normative sentence; the
  # word "indirection" alone recurs in the same section's opening clause and in Red flags.
  grep_flat "$R" 'Each `extract` finding'"'"'s `proposal` must state what the reader gains against what the indirection costs. A finding that only names the gain is incomplete.'
  check $? "reuse: requires an extract finding to state its indirection cost"

  # Multi-file handling, retargeted from the abstraction block. The brief's original literal check
  # was `grep -q 'also_at'` — known-bad: that field name necessarily also appears in the Return
  # format JSON, so it passed with the whole section deleted. Second clause anchors the
  # `in_diff: false` expectation, which the first does not cover and which is what stops a correct
  # multi-file finding being read as a routing failure.
  grep_flat "$R" 'Put the clearest occurrence in `target_file`/`target_line` and every other in `also_at`.' \
    && grep_flat "$R" 'Expect `in_diff` to be `false` often, which routes the finding to the summary comment rather than an inline one; that is correct, not a failure.'
  check $? "reuse: uses also_at for multi-file findings, and expects in_diff false"

  # The field split between the two branches. An extract finding that carries `existing_solution`
  # is a contradiction, and one the arbitrator drops for; an extract finding the skill tells to set
  # `tier` produces the same drop from the other direction. Anchored to the bolded instruction.
  grep_flat "$R" '**Set none of those four on an `extract` finding**'
  check $? "reuse: an extract finding sets no tier or existing-solution fields"

  # --- what the first live posting run exposed in this lens --------------------------------------
  #
  # The null-answer record. This skill calls it "load-bearing, not a footnote" and then gave it
  # nowhere to live: the return format allowed one receipt line and the finding schema had no slot,
  # so the live analyst returned its null candidates BY NAME to the conductor — breaching the
  # context firewall to obey a rule this document had made mandatory. A record required to be
  # produced and then structurally discarded guarantees that breach. Three clauses: the array
  # itself in the return shape, the instruction to write it, and the prohibition on returning it
  # instead, which is the half that names the failure it replaces.
  grep_flat "$R" '"unanswered": [' \
    && grep_flat "$R" '**The record has a place to go: the `unanswered` array in your output file.**' \
    && grep_flat "$R" 'Do not put it in your receipt, and do not name a null candidate in your reply'
  check $? "reuse: keeps the null-answer record in an unanswered array, not in its reply"

  # …and that `unanswered` is a sibling of `findings`, not a finding. Without this the arbitrator's
  # matching skip rule has nothing on this side agreeing with it, and an analyst that writes the
  # array inside `findings` gets every entry scored or dropped as a claim it never made.
  grep_flat "$R" '**`unanswered` is a sibling of `findings`, not a finding.**'
  check $? "reuse: states that unanswered is a sibling of findings, never scored"

  # The existing_solution red flag, amended. As written — "a finding whose existing_solution you
  # have not opened and read" — it was UNSATISFIABLE BY CONSTRUCTION for an installed package on the
  # live run, where the detached worktree contained no dependency tree at all and 3 of this lens's 4
  # findings cited one; a compliant arbitrator would have dropped all three. Two clauses: the
  # amended flag, and the body rule that keeps the allowance narrow now that the conductor links the
  # dependency tree in — an installed package IS openable, and "documented signature" must not
  # become the easy way out of reading it.
  grep_flat "$R" 'A finding whose `existing_solution` you have neither opened and read, nor — where it has no source to open at all — cited a documented signature for.' \
    && grep_flat "$R" '**Open the source wherever there is source to open**'
  check $? "reuse: admits a documented signature only where nothing can be opened"
fi

# --- the security analyst ----------------------------------------------------

check_skill reviewing-for-security

S="$PLUGIN/skills/reviewing-for-security/SKILL.md"
if [ -s "$S" ]; then
  # Anchored to the skill's own bolded rule sentence, not a bare case-insensitive 'exploitable'
  # search. The skill states this rule using the brief's own vocabulary — "exploitation path" —
  # never the bare word "exploitable", so the literal brief grep would not even pass against
  # correctly-written prose; and even loosened to match, a bare word search would still be
  # satisfied by an unrelated stray use of the word with this exact rule sentence deleted.
  # grep_flat rather than a plain grep -qF: the anchor must survive prose being re-wrapped, since
  # nothing about the sentence's meaning depends on which column the source happens to break at.
  grep_flat "$S" 'A finding you cannot write an exploitation path for is not a finding.'
  check $? "security: requires a stated exploitation path"

  # Anchored to the skill's own worked-example sentence, not a bare case-insensitive 'theoretical'
  # search. The section heading itself ("Theoretical findings are out of scope") already contains
  # the bare word, so an unanchored search would still pass with the substantive rule sentence
  # beneath that heading deleted and only the heading left standing. grep_flat for the same reason
  # as above — this sentence is long enough that it wraps across two source lines in the file's
  # normal prose width, and the check must hold regardless of exactly where that wrap falls.
  grep_flat "$S" 'is not a finding unless you can name the path by which untrusted input reaches it'
  check $? "security: rules out theoretical findings"
fi

# --- the code smell analyst ---------------------------------------------------

check_skill detecting-code-smell

M="$PLUGIN/skills/detecting-code-smell/SKILL.md"
if [ -s "$M" ]; then
  # The brief's own literal check here is `grep -qi 'style'` — known-bad: "style" recurs in
  # ordinary prose all over a document like this (the "Style is out of scope" heading, "quote
  # style" in that same section's first sentence), so an unanchored search would still pass with
  # the entire "smell is a predicted failure, not a preference" section deleted. Anchored instead
  # to that section's own defining-rule sentence, which appears nowhere else in the file.
  # grep_flat because the sentence is long enough to wrap across two source lines at the file's
  # normal prose width, and the check must hold regardless of exactly where that wrap falls.
  grep_flat "$M" 'If the only thing you can say is that you would have written it differently, it is not a finding.'
  check $? "smell: separates smells from style preferences"

  # The brief's own literal check here is `grep -qi 'formatter\|linter'` — also known-bad: both
  # words recur standalone outside the "Style is out of scope" section (e.g. "What you receive"
  # instructs reading the repo's linter and formatter configuration, and the Red flags item names
  # both again), so an unanchored search would still pass with the section's substantive deferral
  # rule deleted and only those other, unrelated mentions left standing. Anchored instead to the
  # section's own normative sentence naming both tools together.
  grep_flat "$M" 'already enforced by a linter or formatter belong to that tool, not to guardtower'
  check $? "smell: defers to the project's existing formatter/linter"
fi

# --- the arbitrator -----------------------------------------------------------

check_skill arbitrating-findings

B="$PLUGIN/skills/arbitrating-findings/SKILL.md"
if [ -s "$B" ]; then
  # Task 8 review, Important #2: the original suite anchored only the *consequence* of the
  # verification rule (below) and never the rule itself — deleting the whole "open target_file at
  # target_line inside the worktree and compare it against evidence" instruction left the suite
  # green, i.e. the arbitrator's entire reason for existing was deletable undetected. Anchored to
  # the rule sentence itself, which appears nowhere else in the file.
  grep_flat "$B" 'open `target_file` at `target_line` **inside the worktree** and compare it against `evidence`'
  check $? "arbitrator: verifies cited evidence against the worktree before scoring"

  # The brief's own literal check here is `grep -qi 'drop'` — known-bad per the STANDING RULING:
  # "drop"/"dropped" recurs throughout a document whose whole subject is dropping findings (the
  # outcome name itself, the Red flags item, the return-format JSON's "dropped" key), so an
  # unanchored search would still pass with the entire "do not score it low" rule deleted.
  # Anchored instead to that rule's own sentence, which appears nowhere else in the file.
  # grep_flat because the sentence is long enough to wrap across two source lines at the file's
  # normal prose width, and the check must hold regardless of exactly where that wrap falls.
  grep_flat "$B" 'Do not score it low; dropping and low-scoring are different outcomes and the report distinguishes them.'
  check $? "arbitrator: drops findings whose evidence fails, never scores it low"

  # The brief's own literal check here is `grep -q 'composite'` — known-bad, called out
  # explicitly in the STANDING RULING: `composite` is a field name that necessarily recurs in the
  # return-format JSON and the Three outcomes / Gate and rank prose regardless of whether the
  # arbitrator's own formula sentence survives. Anchored instead to the sentence that actually
  # computes it.
  grep_flat "$B" 'compute `composite` as `round(0.6 × value + 0.4 × urgency)`'
  check $? "arbitrator: computes the composite per the rubric's formula"

  # The brief's own literal check here is `grep -qi 'total order'` — weaker than it looks: the
  # bare phrase could survive as a lone mention (e.g. a cross-reference aside) with the actual
  # ranking rule it's meant to test deleted. Anchored instead to the full ranking sentence itself.
  grep_flat "$B" 'Sort `passed` by the total order the rubric defines: `composite` descending, then `value` descending, then `target_file` ascending, then `id` ascending.'
  check $? "arbitrator: ranks passed findings with the total order"

  # The brief's own literal check here is `grep -q 'existing_evidence'` — known-bad: that field
  # name necessarily also appears in finding-schema.md's own vocabulary and could appear in a
  # passing mention here regardless of whether the "second half of evidence" rule itself survives.
  # Anchored to the sentence that states the rule, AND (Task 8 review, Minor #3) to the tier-2
  # adoption_cost sentence right after it — the first check alone left that second rule deletable
  # with the suite still green.
  grep_flat "$B" 'Also open `existing_solution` and confirm `existing_evidence` shows it genuinely covers the claim.' \
    && grep_flat "$B" 'For `tier: 2`, additionally require a non-empty `adoption_cost`; a tier 2 finding that omits it drops as well, because a dependency proposed with no stated cost is not a finding you can score.'
  check $? "arbitrator: verifies both halves of reuse evidence, including the tier-2 adoption_cost requirement"

  # …and the OTHER branch of the same rule, which the two clauses above do not reach. An `extract`
  # finding carries no `existing_solution` by construction, so an arbitrator holding only the rule
  # above drops every one of them — a lens that emits findings nothing can ever verify. This is the
  # single most consequential piece of drift the merge could produce, and it is invisible to every
  # other check in this suite. Three clauses: the do-not-drop instruction, the occurrence
  # verification that replaces it, and the indirection-cost drop condition, each separately
  # deletable and each wrong alone.
  grep_flat "$B" '**must not be dropped for lacking one**' \
    && grep_flat "$B" 'Open every location in `also_at` instead and confirm the claimed shape is actually at each' \
    && grep_flat "$B" 'Drop it as well if its `proposal` states no indirection cost'
  check $? "arbitrator: verifies an extract finding by its occurrence list, never dropping it for having no existing_solution"

  # The urgency anchor's application, which is where the live-run defect actually landed. The
  # rubric publishes the anchor; this file is what applies it, and an arbitrator still applying it
  # to only two of the three kinds reproduces 81-versus-74 with the rubric correct. Second clause
  # anchors the keys-off-`kind` rule that forbids re-deriving eligibility from the remedy.
  grep_flat "$B" 'Apply the rubric'"'"'s merged-duplicate urgency anchor to every `reimplements`, `duplicates`, or `extract` finding' \
    && grep_flat "$B" 'The anchor keys off `kind` and nothing else — never on which remedy the finding proposes'
  check $? "arbitrator: applies the urgency anchor to extract too, keyed off kind"

  # The brief's own literal check here is `grep -qi 'discarded' && grep -qi 'dropped'` —
  # known-bad, named explicitly in the STANDING RULING: both words are the outcome names used
  # throughout the whole document (return-format JSON, Three outcomes list, Red flags), so both
  # bare searches pass even with the sentence that actually distinguishes them deleted. Anchored
  # to that distinguishing sentence itself, AND (Task 8 review, Minor #3) to the `dropped` bullet's
  # negative-field-carriage line — the first check alone left the three-outcome bullet definitions
  # themselves deletable with the suite still green. The `discarded` and `passed` bullets were left
  # unanchored by that round (deferred out of Task 8) and are added here: with only the `dropped`
  # bullet anchored, the other two definitions — the ones that say a discarded finding WAS verified
  # and scored, which is the whole distinction between it and a dropped one — were still deletable
  # with the suite green.
  grep_flat "$B" 'Returning a dropped finding as discarded would tell the user a fabricated claim was merely low-priority.' \
    && grep_flat "$B" 'Carries `reason`, never `value`, `urgency`, or `composite`.' \
    && grep_flat "$B" 'verified, scored, and `composite` fell short of `threshold`.' \
    && grep_flat "$B" 'verified, scored, and cleared the gate.'
  check $? "arbitrator: keeps dropped and discarded distinct, including by field carriage"

  # --- cross-lens dedup, added after the first live run ----------------------------------------
  #
  # That run's top two brief entries were security-003 at 92 and smell-006 at 90 — ONE defect, a
  # migration whose resumability guard keys off a column type the DDL in the same file had already
  # changed. A third case had three lenses on one thing. A reviewer who reads the same defect twice
  # under two ids stops trusting the ranking, and the ranking is the only thing the gate is built on.
  #
  # The grouping rule itself, anchored to the sentence that defines the test. A bare "overlap" or
  # "dedup" search would be satisfied by the section heading, the Red flags items, or the return
  # shape with the rule deleted. Second clause pins the RANGE half — `target_line` is often a range,
  # and a dedup implementation comparing single numbers silently never groups anything, which fails
  # green.
  grep_flat "$B" 'Two findings belong to the same group when their evidence covers the **same `target_file`** and their line spans **overlap**' \
    && grep_flat "$B" 'a bare line is a span of one, and two spans overlap when each one'"'"'s start is at or before the other'"'"'s end'
  check $? "arbitrator: groups findings by overlapping evidence spans, ranges included"

  # The negative half of the definition, which is the half that keeps dedup honest. Without it the
  # rule reads as "merge things that are near each other", and two unrelated defects in one file
  # merge — after which only the representative is ever reported, so the other is gone for good.
  # Two clauses: the worked counter-example and the bolded statement of what the test actually is.
  grep_flat "$B" 'Two findings in the same file at unrelated lines are **two findings**' \
    && grep_flat "$B" '**Overlap of the evidence spans is the test** — not proximity, not a shared file, not a shared theme'
  check $? "arbitrator: says plainly what dedup is not"

  # Fold, never discard. This is what turns a duplicate into evidence instead of noise, and it is
  # the step most likely to be "simplified" into keeping the top score and dropping the rest — which
  # would look identical in the return shape and lose the whole point. Three clauses: the
  # representative rule, the fold instruction with the fields it carries, and the statement that a
  # folded member is neither dropped nor discarded, which is what stops it being mislabelled.
  grep_flat "$B" '**Keep the highest composite.** That finding represents the group' \
    && grep_flat "$B" 'Each remaining member becomes an entry in the representative'"'"'s `corroborated_by`, carrying its `lens`, `id`, `target_line`, and its `claim` in its own words.' \
    && grep_flat "$B" 'Folding a member in is neither dropping nor discarding it'
  check $? "arbitrator: folds duplicates in as corroboration rather than discarding them"

  # Where dedup sits in the order. Run it before scoring and there are no composites to choose a
  # representative with; run it after the gate and one defect has already been counted twice on the
  # way through, which is the failure it exists to prevent.
  grep_flat "$B" 'Dedup runs after scoring because it needs composites to choose a representative, and before the gate'
  check $? "arbitrator: runs dedup after scoring and before the gate"

  # The fourth outcome. "Three outcomes, never conflated" was exhaustive and is no longer: a folded
  # member was verified and scored, so calling it dropped or discarded is a lie in a different
  # direction each time. Anchored to the bullet's own definition sentence.
  grep_flat "$B" '**`corroborating`** — verified, scored, and folded into another finding'"'"'s group'
  check $? "arbitrator: names corroborating as a fourth outcome, not a dropped or discarded one"

  # The return shape's slot for it. The prose above could all survive with the field missing from
  # the JSON, in which case the arbitrator has been told to fold findings into a field its own
  # return format does not have — and the brief and the poster both read it from there.
  grep_flat "$B" '"corroborated_by": [' \
    && grep_flat "$B" '"claim": "<its claim, in its own words>"'
  check $? "arbitrator: the return shape carries corroborated_by"

  # The reuse lens's `unanswered` array is in the finding files this skill opens, and is not
  # findings. Without this the arbitrator meets an array of search records where it expects
  # findings and scores or drops them — either way inventing outcomes for things that were never
  # claims.
  grep_flat "$B" 'A finding file may also carry an `unanswered` array alongside `findings`' \
    && grep_flat "$B" 'Those are **not findings**: do not verify, score, gate, or return them.'
  check $? "arbitrator: skips the unanswered array instead of scoring it"

  # The documented-signature allowance, the arbitrator's half of the vendor fix. Its verification
  # rule says to open `existing_solution` — but a stdlib call, a platform API, and an uninstalled
  # tier 2 package have no file to open, so the rule as written drops findings for being the kind of
  # finding the reuse lens is explicitly allowed to make. Second clause keeps the allowance narrow:
  # now that the conductor links the dependency tree in, an installed package IS openable and
  # "documented signature" must not become the easy way out of reading it.
  grep_flat "$B" 'Where `existing_solution` names something with **no file to open**' \
    && grep_flat "$B" 'That allowance is narrow and does not extend to an installed dependency'
  check $? "arbitrator: accepts a documented signature only where nothing can be opened"
fi

# --- the forge poster ---------------------------------------------------------

check_skill posting-review-comments

P="$PLUGIN/skills/posting-review-comments/SKILL.md"
if [ -s "$P" ]; then
  # The brief's literal checks here are `grep -q 'gh api'` and `grep -q 'glab'`. Both are bare
  # substring searches of the kind the STANDING RULING rejects, and the gh one demonstrably leaks:
  # deleting the whole gh api code example while leaving the descriptive sentence "GitHub, via
  # `gh api` with a JSON body built in a heredoc" intact still passes it. It proves two words
  # survive somewhere, not that the command the brief asked for is present. Anchored to the actual
  # invocations instead.
  grep_flat "$P" 'gh api "repos/$REPO/pulls/$PR/reviews"'
  check $? "poster: uses gh api for GitHub"
  grep_flat "$P" 'glab api "projects/$ENC_REPO/merge_requests/$MR/discussions"'
  check $? "poster: uses glab for GitLab"

  # …and that it addresses the project EXPLICITLY. `projects/:id` resolves from the git remote of
  # whatever directory the process is standing in, and a dispatched subagent's cwd is not guaranteed
  # to be the repository under review — so `:id` can silently post this run's review onto a
  # different project. The positive anchor above proves the encoded form is present; this negative
  # one proves the old form is gone, which is the half a future "simplification" would undo. Both
  # are needed: the encoded call could be added while a stray `:id` call survives elsewhere in the
  # document.
  #
  # The negative is anchored on `api "projects/:id`, the INVOCATION, not on the bare path. Written
  # bare it FAILS against a correct tree, which is how it was first written here and what running it
  # caught: this skill names `projects/:id` twice in prose — once in the rule that forbids it and
  # once in the Red flags list — because a plugin that may not describe the error it warns about is
  # the same absurdity the jq check below rejects. Quoting the command form tests the command and
  # leaves the prose free to explain it.
  ! grep_flat "$P" 'api "projects/:id'
  check $? "poster: never addresses the project as projects/:id"

  grep_flat "$P" 'glab mr note "$MR" -R "$REPO"'
  check $? "poster: passes -R to glab mr note, which has the same cwd dependency"

  grep_flat "$P" '**`repo` must be URL-encoded**' \
    && grep_flat "$P" '`oro/wastequip` is `oro%2Fwastequip`'
  check $? "poster: states that repo must be URL-encoded, with the worked example"

  # The third sha. The poster sent `position[start_sha]=$BASE_SHA`; measured live those are
  # different values (e2c4753 against cdc22db) and start_sha changes on every push, so the position
  # triple matched no stored diff version and EVERY inline comment was rejected — after which this
  # skill's own no-fallback rule correctly killed the whole inline set. Three clauses: the position
  # line as it must now read, the bolded rule, and the negative that the old wrong value is gone.
  grep_flat "$P" '-f "position[start_sha]=$START_SHA"' \
    && grep_flat "$P" '**`position[start_sha]` is `start_sha`, never `base_sha`.**'
  check $? "poster: sends start_sha in the position triple, and says why it is not base_sha"

  ! grep_flat "$P" 'position[start_sha]=$BASE_SHA'
  check $? "poster: does not send base_sha as start_sha"

  # The brief's own literal check here is `grep -qi 'pending' "$P" || grep -qi 'single review'` —
  # and as written it carries a bug the plan already flagged: the second branch's grep has no file
  # argument, so on a $P that doesn't contain "pending" it reads from stdin instead of testing $P
  # at all (hanging, or matching whatever happens to be on stdin). Beyond the bug, a bare
  # case-insensitive word search is exactly the STANDING RULING's known-fragile shape: "pending" or
  # "single review" could each survive as an unrelated stray mention with the actual one-review
  # rule deleted. Anchored instead to the skill's own rule sentence, which appears nowhere else in
  # the file. grep_flat because the sentence is long enough to wrap across two source lines at the
  # file's normal prose width.
  grep_flat "$P" 'so the reviewer gets one notification rather than one per comment'
  check $? "poster: posts one review, not one comment per finding"

  # The brief's own literal check here is `grep -q 'in_diff'` — known-bad: that field name
  # necessarily also appears in the dispatch JSON (What you receive) and in the arbitrator's return
  # shape this file cites, regardless of whether the routing rule itself survives. Anchored instead
  # to the sentence that actually states the routing rule.
  grep_flat "$P" '`in_diff: true` becomes an inline comment at `target_file`:`target_line`; `in_diff: false` becomes a line in the one summary comment.'
  check $? "poster: routes on in_diff"

  # The poster's half of also_at. brief-template.md's half is anchored above; only that half got a
  # check when the field was implemented, so this surface was deletable while green — proven by
  # mutation: removing the `Also at:` line from the Comment body format left the suite at 129 ok /
  # PASS, and removing it together with the whole omission rule did too. That is the exact gap the
  # template check exists to close, sitting on the output surface for `extract` findings, which
  # usually span several files while `target_file`/`target_line` names only the clearest.
  # Two clauses because either half is separately deletable and separately wrong on its own: the
  # format line without the rule renders an empty `Also at:` on every single-location finding, and
  # the rule without the format line governs a line the template no longer has.
  grep_flat "$P" 'Also at: <also_at, comma-joined>' \
    && grep_flat "$P" 'The `Also at` line appears only when `also_at` is non-empty'
  check $? "poster: renders also_at in the comment body, omitted when empty"

  # The brief's own literal check here is `grep -qi 'never post'` — a bare case-insensitive
  # substring the STANDING RULING calls out by name as too weak: those two words could survive in
  # unrelated phrasing with the actual unconditional rule deleted. Anchored instead to the skill's
  # own bolded rule sentence.
  grep_flat "$P" 'Never post a finding the user did not approve.'
  check $? "poster: refuses to post anything not approved"

  # The two checks that used to live here asserted the OPPOSITE of what is now correct, and they
  # were right about the wrong thing. The gh review body was built in a heredoc with an unquoted
  # delimiter so the shell would substitute `$HEAD_SHA` — and it does, but the same expansion also
  # empties `$data` out of a rationale. The first live run's rationales contained `$data`,
  # `$settings`, `$e`, `$connection`, backticks and double quotes, every one an ordinary identifier
  # quoted in prose about the code: `$data` expands to nothing and deletes itself from the posted
  # comment, and one `"` ends the JSON string and breaks the request. No delimiter choice serves
  # both the sha and the text, so the two are separated — the text goes in as data through a QUOTED
  # heredoc, the sha comes in through the environment inside python3, and `json.dumps` does the
  # escaping. That keeps the no-jq property intact: python3 is already this plugin's stdlib JSON
  # tool.
  #
  # Three positives — the quoted body heredoc, the python3 build, and json.dumps — because each is
  # separately deletable and each is wrong alone: the quoted heredoc without python3 leaves the JSON
  # hand-assembled and still breakable by a quote; python3 without the quoted heredoc leaves the
  # shell to mangle the text before Python ever sees it.
  grep_flat "$P" "BODY_1=\$(cat <<'GT_BODY'" \
    && grep_flat "$P" "python3 - <<'GT_JSON' | gh api" \
    && grep_flat "$P" 'print(json.dumps({'
  check $? "poster: builds the review JSON with python3 from quoted heredocs"

  # …and the negative that the unquoted form has not come back. Anchored to `--input - <<JSON`, the
  # actual command line, not to a bare `<<JSON`: the prose above the block describes the bug it
  # replaced, and a plugin that may not name the mistake it warns about is the same absurdity the jq
  # check below rejects. Anchoring on the invocation tests the command and leaves the prose free.
  ! grep_flat "$P" '--input - <<JSON'
  check $? "poster: the review body is never built in an unquoted heredoc"

  # The rule the mechanism serves, stated once so a future editor knows what the machinery is for.
  # Without it the three positives above read as an arbitrary style, and the next person adding a
  # second inline comment writes it the convenient way.
  grep_flat "$P" '**Every body — inline or summary — is assembled into a shell variable from a quoted heredoc, and reaches a command only as `"$VAR"`.**'
  check $? "poster: states the rule that finding text never reaches the shell as text"

  # The poster's own half of the dispatch contract: the paragraph that separates the five fields
  # this skill DECLARES as its interface from the four it is additionally handed, and says why each
  # of the four is needed. The conductor's half is anchored twice below (prose and payload); this
  # half had nothing, and deleting the whole paragraph left the suite at PASS, exit 0 — proven by
  # mutation. Without it a maintainer reading only this file sees nine fields arrive in the What you
  # receive block with no statement of which are contractual, and trimming the payload back to the
  # declared five silently removes `base_sha` (GitLab cannot anchor a diff position without it) and
  # `run_id`/`lenses_run`/`lenses_skipped` (the summary comment cannot name the run or admit what
  # was skipped).
  #
  # Two clauses, because the two sentences are separately deletable and each is wrong alone: the
  # declared-five sentence without the justification invites deleting the other four as unexplained
  # extras, and the justification without the declared-five sentence no longer distinguishes them
  # from the interface.
  grep_flat "$P" '`forge`, `pr_number`, `repo`, `approved`, and `head_sha` are this task'"'"'s declared interface.' \
    && grep_flat "$P" 'are included alongside them because requirements below cannot be met without them'
  check $? "poster: distinguishes its declared interface from the fields carried alongside"

  # The poster's own half of the two fields the conductor's Post payload gained. The conductor's
  # half is anchored below; this half is what makes the poster expect them, and without it a
  # maintainer reading only this file sees eleven fields arrive with no statement of which are
  # contractual. `start_sha` is the one that decides whether the inline set posts at all.
  grep_flat "$P" '"start_sha": "<GitLab diff-version anchor — never equal to base_sha>",' \
    && grep_flat "$P" '"skill_path": "<absolute path to the SKILL.md this dispatch names>",'
  check $? "poster: declares start_sha and skill_path in what it receives"

  # The corroboration the arbitrator's dedup produces has to survive all the way to the comment, or
  # dedup silently becomes "report the highest and bin the rest". Two clauses: the body-format line
  # and the omit-when-empty rule, the same two-sided shape the `Also at` check uses and for the same
  # reason — the line without the rule renders an empty label on every uncorroborated finding, and
  # the rule without the line governs something the template no longer has.
  grep_flat "$P" 'Corroborated by: <corroborated_by, one "<lens> (<id>): <claim>" per entry, comma-joined>' \
    && grep_flat "$P" 'The `Corroborated by` line appears only when `corroborated_by` is non-empty'
  check $? "poster: renders corroborated_by in the comment body, omitted when empty"

  # …and that the field is on the authoritative list this skill copies from the arbitrator. The
  # render lines above are satisfied by prose; only the list decides whether the poster believes the
  # field exists, and this file says outright that a field not on it "doesn't exist yet".
  grep_flat "$P" '`in_diff`, `also_at`, `corroborated_by`, `value`, `urgency`, `composite`'
  check $? "poster: lists corroborated_by among the fields the arbitrator assigns"
fi

# The poster reads base_sha, run_id, lenses_run and lenses_skipped, none of which are in its
# declared interface. The conductor must therefore name them at the dispatch site, or the poster is
# told to consult fields it was never given - the same gap the arbitrator's dispatch had. Anchored
# to the sentence that makes the requirement explicit, not to the field names, which also appear in
# the JSON block and would survive its deletion.
grep_flat "$CONDUCTOR/SKILL.md" 'Name every field. `base_sha` is not optional decoration'
check $? "conductor: names the poster payload, not just the approved set"

# …and the payload itself, for the same two-clause reason as the arbitrator dispatch above. The
# check immediately above anchors only the justifying prose, deliberately so; the consequence is
# that the ENTIRE poster dispatch JSON block could be deleted with the suite still at PASS, exit 0
# — proven by mutation. A conductor whose prose says "name every field" over a block that no longer
# exists dispatches the poster with nothing, and the poster's own instructions then send it to
# consult eight fields it was never handed.
#
# Three clauses: the opening field, the contiguous run of the four fields the prose above declares
# load-bearing, and the closing one. Top-and-bottom alone would catch the block being deleted
# wholesale but not gutted down to its middle, which is the same failure mode the rubric band-table
# checks are anchored against.
#
# The middle run now carries `start_sha` and `skill_path` as well, both added after the first live
# run. `start_sha` is the load-bearing one and cannot be re-derived anywhere downstream: it is not
# `base_sha` (measured live at e2c4753 against cdc22db), it changes on every push, and without it
# the poster has no correct value to send, so every inline comment is rejected and the poster's own
# no-fallback rule then kills the whole inline set — a run that posts nothing inline from findings
# the user already approved. Keeping them inside the contiguous span is what makes deletion of
# either one break the match.
grep_flat "$CONDUCTOR/SKILL.md" '"forge": "github | gitlab",' \
  && grep_flat "$CONDUCTOR/SKILL.md" '"base_sha": "<from preflight step 3>", "head_sha": "<from preflight step 3>", "start_sha": "<from preflight step 3 — GitLab'"'"'s diff-version anchor, never base_sha>", "run_id": "<this run'"'"'s id>", "lenses_run": ["<lens>", "..."], "lenses_skipped": ["<lens>", "..."], "skill_path": "<absolute path to the SKILL.md this dispatch names>",' \
  && grep_flat "$CONDUCTOR/SKILL.md" '"approved": ["<the in-scope subset of the arbitrator'"'"'s passed array>"]'
check $? "conductor: the poster dispatch payload block is present and complete"

# …and the prose that says why start_sha in particular cannot be left out. The span above proves the
# line is in the payload; nothing in it explains the field, and an unexplained field is the one a
# future editor trims as duplication of base_sha — which is precisely the bug this closes.
grep_flat "$CONDUCTOR/SKILL.md" '**`start_sha` is the third of GitLab'"'"'s three and the one nothing else can supply.**'
check $? "conductor: says why start_sha cannot be re-derived downstream"

# --- one authority for the numbers every document repeats ---------------------
#
# The composite formula appears in four documents and the rubric's total order in three, and until
# now each was asserted independently — the formula at two separate call sites in this file with
# nothing tying them. Independent assertions prove each document says SOMETHING; they never prove
# the documents agree. Reweight the formula in one place only and every independent check still
# passes while the plugin scores two different ways depending on which document a reader followed —
# and reproducibility across runs is the entire reason the rubric is published.
#
# So: extract the string from scoring-rubric.md, which is the published authority both the analysts
# and the arbitrator are told to work to, and assert the others carry it verbatim. The extraction
# doubles as an anchor on the rubric itself — delete the line there and the variable comes back
# empty, which is tested before it is used, so an empty string can never trivially "match"
# everywhere. README.md's mermaid node states the same weights in an ASCII, unrounded form that a
# diagram renderer requires (`0.6 x value + 0.4 x urgency`) and is deliberately NOT included here:
# forcing it to carry the prose string verbatim would mean breaking the diagram to satisfy a test.
if [ -s "$RUBRIC" ]; then
  flat_rubric=$(tr '\n' ' ' < "$RUBRIC" | tr -s ' ')

  formula=$(printf '%s\n' "$flat_rubric" | sed -n 's/.*\*\*Composite:\*\* `\([^`]*\)`.*/\1/p')
  [ -n "$formula" ]; check $? "scoring-rubric.md is the one authority for the composite formula"

  miss=""
  if [ -n "$formula" ]; then
    for doc in "$PLUGIN/skills/arbitrating-findings/SKILL.md" \
               "$CONDUCTOR/references/finding-schema.md" \
               "$PLUGIN/README.md"; do
      grep_flat "$doc" "$formula" || miss="$miss ${doc#"$PLUGIN"/}"
    done
  else
    miss=" (formula not extracted)"
  fi
  [ -z "$miss" ]; check $? "every document repeats the rubric's composite formula verbatim (mismatched:$miss)"

  order=$(printf '%s\n' "$flat_rubric" | sed -n 's/.*\*\*Tie-break\.\*\* Rank by \(.*\) — a total order.*/\1/p')
  [ -n "$order" ]; check $? "scoring-rubric.md is the one authority for the total order"

  miss=""
  if [ -n "$order" ]; then
    for doc in "$PLUGIN/skills/arbitrating-findings/SKILL.md" \
               "$CONDUCTOR/references/brief-template.md"; do
      grep_flat "$doc" "$order" || miss="$miss ${doc#"$PLUGIN"/}"
    done
  else
    miss=" (order not extracted)"
  fi
  [ -z "$miss" ]; check $? "every document repeats the rubric's total order verbatim (mismatched:$miss)"
fi

# --- no skill or command shells out to jq -------------------------------------
#
# The brief's own literal check here is:
#   ! grep -rqw jq "$PLUGIN/skills" "$PLUGIN/commands" 2>/dev/null
# Run against the current tree this FAILS: three skills legitimately contain the word "jq", four
# times between them — arbitrating-findings/SKILL.md's Red flags bullet forbidding a shell-out to
# jq, posting-review-comments/SKILL.md's Red flags bullet forbidding the same thing (twice, across
# the two lines it wraps to), and reviewing-a-pull-request/SKILL.md's aside comparing a missing jq
# to a missing gh/glab. All are correct and desirable prose; a plugin that may not even name the
# tool it forbids is absurd. A bare `grep -w jq` cannot tell "names jq" from "invokes jq", so the
# literal check is rejected outright rather than merely re-anchored. This checks for actual
# invocation instead: jq appearing anywhere inside a fenced sh/bash/shell/zsh block, or jq preceded
# by a pipe, semicolon, `&&`, or an opening backtick and followed by whitespace or a quoted
# argument — never a bare backtick-quoted mention like `jq` on its own with nothing after it.
# Proven by mutation in the task report: a real invocation added to a scratch fixture (piped,
# fenced, and inline-code forms) is caught; all four of the real bare mentions counted above are
# not.
python3 - "$PLUGIN/skills" "$PLUGIN/commands" <<'PY'
import re, sys, pathlib

roots = [pathlib.Path(p) for p in sys.argv[1:] if pathlib.Path(p).is_dir()]
shell_langs = {"sh", "bash", "shell", "zsh"}

def strip_shell_comment(line):
    """Return `line` up to its first UNQUOTED '#'. Quote state is tracked so a '#' inside a
    single- or double-quoted string is not mistaken for a comment start."""
    sq = dq = False
    for i, ch in enumerate(line):
        if ch == "'" and not dq:
            sq = not sq
        elif ch == '"' and not sq:
            dq = not dq
        elif ch == '#' and not sq and not dq:
            return line[:i]
    return line

# Two independent signals of an actual invocation, because either alone leaks:
#   1. jq at a command position - line start, or after a pipe, semicolon, && or backtick.
#   2. jq followed by something that can only be an argument - a flag, a filter starting
#      with '.', or a quote. This catches a mid-prose "run jq .x file.json" that signal 1
#      misses, and was added after a positive-control mutation proved signal 1 alone let it
#      through.
# A bare backtick-quoted mention (`jq`) matches neither: the char after jq is a backtick,
# which is not whitespace, a quote, or an argument opener. That exemption is what lets a
# skill name the tool it forbids.
invoked_re = re.compile(r'''(?:(?:^|[|;]|&&|`)\s*jq(?=[\s'"]|$))|(?:\bjq\s+(?:-[A-Za-z]|[.'"(]))''')

hits = []
for root in roots:
    for f in sorted(root.rglob('*.md')):
        in_shell_fence = False
        for line in f.read_text().splitlines():
            stripped = line.strip()
            if stripped.startswith('```'):
                if in_shell_fence:
                    in_shell_fence = False
                else:
                    lang = stripped[3:].strip().lower()
                    in_shell_fence = lang in shell_langs
                continue
            if in_shell_fence:
                # Inside a shell fence every non-comment line is command text, so a bare `jq` word
                # is an invocation. But a COMMENT inside a fence is prose - "# guardtower forbids
                # jq" is exactly the naming-not-invoking case the whole check exists to permit, and
                # flagging it would forbid documenting the rule in the one place it belongs.
                #
                # Strip the comment, but find its start QUOTE-AWARE. A naive line.split('#')[0]
                # truncates at a '#' inside a quoted argument, and a real invocation after one then
                # goes unseen - `curl "http://x/y#frag" | jq .z` is an everyday shell line, not an
                # adversarial one, and it slipped through an earlier version of this check.
                if re.search(r'\bjq\b', strip_shell_comment(line)):
                    hits.append(f"{f}: {line.strip()}")
            elif invoked_re.search(line):
                hits.append(f"{f}: {line.strip()}")

if hits:
    sys.stderr.write("jq invocation(s) found:\n" + "\n".join(hits) + "\n")
    sys.exit(1)
sys.exit(0)
PY
check $? "no skill shells out to jq"

# --- command ----------------------------------------------------------------

CMD="$PLUGIN/commands/review.md"
[ -s "$CMD" ]; check $? "commands/review.md exists"

if [ -s "$CMD" ]; then
  head -1 "$CMD" | grep -q '^---$'
  check $? "command: frontmatter opens on line 1"
  grep -q '^description: ' "$CMD"
  check $? "command: frontmatter has a description"

  # The brief's own literal check here is `grep -q 'reviewing-a-pull-request'` — a bare substring
  # search of the whole file, the shape the STANDING RULING rejects: the skill name is exactly the
  # kind of string that could survive in a stray comment or cross-reference with the actual
  # dispatch instruction deleted. Anchored instead to the command's own dispatch sentence, which
  # appears nowhere else in the file. grep_flat so the anchor survives a future prose rewrap.
  grep_flat "$CMD" 'Otherwise invoke the `reviewing-a-pull-request` skill with that reference and follow it exactly.'
  check $? "command: invokes the conductor skill"
fi

# --- the expected skill set, exactly ---------------------------------------

expected="arbitrating-findings detecting-code-smell posting-review-comments reviewing-a-pull-request reviewing-for-security surveying-for-reuse"
actual=$(ls "$PLUGIN/skills" | sort | tr '\n' ' ' | sed 's/ $//')
[ "$actual" = "$expected" ]; check $? "skill set is exactly the six planned skills"

# --- no orphaned reference to the deleted abstraction analyst -----------------
#
# The skill-set check above catches the directory coming back. It says nothing about the far more
# likely residue: a document still naming a skill that no longer exists — the conductor's dispatch
# list, the poster's lens vocabulary, the README's flow diagram. check_links cannot see these,
# because the plugin's prose names skills bare (`simplifying-through-abstraction`) rather than by
# path, and a bare name matches none of its two target shapes. A dangling name is worse than a
# broken link here: it tells a model at dispatch time to invoke a skill that will not resolve.
#
# The needle is assembled from two halves rather than written whole, because this file lives under
# $PLUGIN and a literal would match itself the moment tests/ is ever included in the sweep. The
# sweep is scoped to the documents a run actually reads: skills, commands, and the README.
orphan_needle="simplifying-through""-abstraction"
orphans=$(grep -rl "$orphan_needle" "$PLUGIN/skills" "$PLUGIN/commands" "$PLUGIN/README.md" 2>/dev/null | tr '\n' ' ')
[ -z "$orphans" ]; check $? "no plugin document names the deleted abstraction skill (found:$orphans)"

# The same sweep for the retired lens VALUE. `abstraction` as an English word is legitimate and
# expected — the reuse lens's extract half is built on it — so a bare word search would fail
# against a correct tree. What must not survive is the lens NAME in a machine-read position: a
# `"lens": "abstraction"` field, an `abstraction.json` findings path, or the value inside a lens
# alternation. Those three shapes are searched; prose is left alone.
lens_orphans=$(grep -rlE '"lens": *"abstraction"|abstraction\.json|smell \| abstraction' \
  "$PLUGIN/skills" "$PLUGIN/commands" "$PLUGIN/README.md" 2>/dev/null | tr '\n' ' ')
[ -z "$lens_orphans" ]; check $? "no plugin document still uses abstraction as a lens value (found:$lens_orphans)"

# --- the finished plugin is frozen, as signal and verity are ----------------
#
# Asserted from inside the plugin's own suite so the freeze is a property the plugin tests, not a
# convention someone has to remember. The deny rules live in .claude/settings.json, which IS
# committed (see .gitignore's note) precisely so they travel with the repo; a checkout that has
# guardtower but not the rules is an unfrozen guardtower, and this check is what says so.
#
# `deny` is read as a set and tested for containment rather than compared to a literal list: signal
# and verity's entries are already there, an `allow` list sits alongside it, and neither is this
# check's business. Anchored to the two exact patterns, though — a `deny` that merely mentions
# guardtower under some other pattern would not actually stop an Edit.

python3 - "$ROOT/.claude/settings.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
deny=set(d["permissions"]["deny"])
need={"Edit(./guardtower/**)","Write(./guardtower/**)"}
missing=need-deny
assert not missing, f"settings.json deny list missing: {sorted(missing)}"
PY
check $? "guardtower is frozen in .claude/settings.json"

# Anchored to a whole line, not a substring: `.guardtower/` appearing inside a comment — and this
# .gitignore carries several explanatory comments — must not satisfy a check that the pattern is
# actually in force.
grep -q '^\.guardtower/$' "$ROOT/.gitignore"
check $? ".guardtower/ run artifacts are gitignored"

printf '\n'
if [ "$fail" -eq 0 ]; then printf 'PASS\n'; else printf 'FAILURES PRESENT\n'; fi
exit "$fail"
