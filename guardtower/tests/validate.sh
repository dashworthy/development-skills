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
  grep_flat "$CONDUCTOR/references/finding-schema.md" '`tier` is the one reuse-only field that is **a JSON number, not a string**' \
    && grep_flat "$CONDUCTOR/references/finding-schema.md" '"tier": 1,'
  check $? "finding-schema.md pins tier to a JSON number"
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
# A BARE basename is deliberately NOT matched, and that is not an oversight to fix later: the run
# artifacts `brief.md`, `approved.md` and `deferred.md` have exactly that shape, are named in these
# documents as paths under `.guardtower/<run>/` that exist only at runtime, and have no counterpart
# on disk in this repository. Matching them would make this check FAIL against a correct tree.
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
for ref in mapping-the-repo brief-template; do
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
  # The mapper's, from preflight step 7. Both clauses, not just one: the payload clause alone can
  # be deleted while the explanation survives and vice versa, and each was separately green before
  # this check existed.
  grep_flat "$C" 'together with its payload: `worktree` — the absolute path from step 5 — and `head_sha` — from step 3.' \
    && grep_flat "$C" 'dispatching it without this payload leaves it nothing to read'
  check $? "conductor: names the mapper payload, not just the reference document"

  # The arbitrator's. `threshold` and `worktree` are the load-bearing two: without the first, the
  # gate the user agreed at preflight step 8 is silently discarded and the arbitrator falls back to
  # its own example value; without the second, evidence is verified against the user's checked-out
  # tree instead of the detached worktree — a silent wrong answer from the step the whole design
  # rests on. Anchored to the paragraph that names them, not to the field names, which also appear
  # in the JSON block and would survive its deletion — the same shape as the poster's check below.
  grep_flat "$C" 'Name every field. `threshold` is not optional decoration'
  check $? "conductor: names the arbitrator payload, not just the finding paths"

  # `repo` was the one poster-payload field with a shape but no source: no preflight step produced
  # it, since step 1 read the origin URL only to detect the forge and step 3's `gh pr view` does
  # not request it. Anchored to the sentence in step 1 that makes the origin URL its provenance.
  grep_flat "$C" 'it is the only place `repo` comes from'
  check $? "conductor: preflight step 1 is where repo comes from"
fi

# --- the two conductor reference documents ------------------------------------
#
# Both had existence checks and nothing else: reducing either file to the single character "x" on a
# scratch copy left the suite reporting 105 ok, PASS. That is not a small gap in either case.
# mapping-the-repo.md is the mapper's COMPLETE brief — it is handed to a subagent with no other
# instructions, so every rule in it (read only in the worktree, map at head_sha, return a structured
# map, write nothing) is the only thing standing between the mapper and reading the user's checked-out
# tree at the wrong commit. brief-template.md is the render contract between the arbitrator's return
# and the human doing triage; a placeholder missing from it is a column missing from the only
# document the human decides on.

MAP="$CONDUCTOR/references/mapping-the-repo.md"
if [ -s "$MAP" ]; then
  grep_flat "$MAP" 'Read only **inside the worktree path** your dispatch brief names'
  check $? "mapping-the-repo.md: reads only inside the worktree it was given"

  grep_flat "$MAP" 'The dispatch brief also names `head_sha`; map the tree **at that commit**'
  check $? "mapping-the-repo.md: maps at head_sha, not at whatever is checked out"

  grep_flat "$MAP" 'Return a **structured map**, never a raw tree listing.'
  check $? "mapping-the-repo.md: returns a structured map, never a tree dump"

  grep_flat "$MAP" 'You do not write anything — not a report, not a cache, not a scratch note.'
  check $? "mapping-the-repo.md: writes no files"

  # Line-anchored on purpose, exactly as check_skill's equivalent is: this asserts the heading and
  # therefore the section, and a flattened search would also be satisfied by the phrase appearing in
  # body prose with the stop list itself deleted.
  grep -q '^## Red flags — STOP' "$MAP"
  check $? "mapping-the-repo.md: has a 'Red flags — STOP' section"
fi

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
  # had no slot for it and the poster's comment body had none either, so for the abstraction lens —
  # whose findings "usually span several files" — every location but one was silently dropped at
  # both. Anchored to the line and to the omit-when-empty instruction that makes it renderable.
  grep_flat "$BRIEF" '- **Also at:** {{ALSO_AT}}' \
    && grep_flat "$BRIEF" 'The Also at line exists only on a finding whose also_at array is non-empty'
  check $? "brief-template.md: renders also_at, omitted when empty"
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
  # instructs reading repo_map for a configured linter or formatter, and the Red flags item names
  # both again), so an unanchored search would still pass with the section's substantive deferral
  # rule deleted and only those other, unrelated mentions left standing. Anchored instead to the
  # section's own normative sentence naming both tools together.
  grep_flat "$M" 'already enforced by a linter or formatter belong to that tool, not to guardtower'
  check $? "smell: defers to the project's existing formatter/linter"
fi

# --- the abstraction analyst --------------------------------------------------

check_skill simplifying-through-abstraction

A="$PLUGIN/skills/simplifying-through-abstraction/SKILL.md"
if [ -s "$A" ]; then
  # The brief's own literal check here is `grep -q 'also_at'` — known-bad: that field name
  # necessarily also appears in the Return format JSON schema below, regardless of whether the
  # multi-file guidance survives, so an unanchored search would still pass with the entire
  # "Multi-file findings" section deleted. Anchored instead to that section's own normative
  # sentence, which appears nowhere else in the file. grep_flat because the sentence is long
  # enough to wrap across two source lines at the file's normal prose width, and the check must
  # hold regardless of exactly where that wrap falls.
  grep_flat "$A" 'Put the clearest occurrence in `target_file`/`target_line` and every other in `also_at`.'
  check $? "abstraction: uses also_at for multi-file findings"

  # The brief's own literal check here is `grep -qi 'premature\|speculative'` — also known-bad,
  # for the same class of reason as above: a bare case-insensitive word search is satisfied by
  # any stray use of "speculative" anywhere in the file, so it is fragile by construction — it
  # would pass unchanged if the defining-rule sentence below were reworded to drop the word while
  # keeping the rule, and would equally pass if the word turned up in unrelated prose elsewhere
  # while the rule itself went missing. Anchored instead to the defining-rule section's own
  # sentence, so the check exercises the rule itself, not the presence of one word.
  grep_flat "$A" 'An abstraction proposed for a case that has not happened yet is speculative, and speculative abstraction costs more than the duplication it prevents.'
  check $? "abstraction: rules out speculative abstraction"
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
  grep_flat "$P" 'glab api "projects/:id/merge_requests/$MR/discussions"'
  check $? "poster: uses glab for GitLab"

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
  # template check exists to close, sitting on the output surface for the abstraction lens, whose
  # findings usually span several files while `target_file`/`target_line` names only the clearest.
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

  # The gh heredoc delimiter is UNQUOTED on purpose: `<<'JSON'` suppresses every expansion inside
  # the body, so `$HEAD_SHA` would post as that literal nine-character string and the review would
  # attach to nothing. A future editor "fixing" the delimiter to the quoted form reintroduces that
  # bug with every other check in this suite still green, so it gets both a positive and a negative
  # assertion.
  #
  # Both are anchored to `--input - <<JSON`, the actual command line, NOT to a bare `<<JSON`. That
  # matters in both directions here. The bare positive would be satisfied by the prose sentence
  # above the code block, which names the delimiter to explain the rule — so the whole gh code block
  # could be deleted and the check would still pass. And the bare negative would FAIL against a
  # correct tree, because that same explanatory sentence contains the string `<<'JSON'` verbatim as
  # the thing it forbids; a plugin that may not spell out the mistake it is warning about is the
  # same absurdity the jq check below rejects. Anchoring both to the invocation tests the command
  # and leaves the prose free to describe it.
  grep_flat "$P" '--input - <<JSON'
  check $? "poster: the gh api heredoc delimiter is unquoted"

  ! grep_flat "$P" "--input - <<'JSON'"
  check $? "poster: the gh api heredoc delimiter is not the quoted form"
fi

# The poster reads base_sha, run_id, lenses_run and lenses_skipped, none of which are in its
# declared interface. The conductor must therefore name them at the dispatch site, or the poster is
# told to consult fields it was never given - the same gap the mapper dispatch had. Anchored to the
# sentence that makes the requirement explicit, not to the field names, which also appear in the
# JSON block and would survive its deletion.
grep_flat "$CONDUCTOR/SKILL.md" 'Name every field. `base_sha` is not optional decoration'
check $? "conductor: names the poster payload, not just the approved set"

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

expected="arbitrating-findings detecting-code-smell posting-review-comments reviewing-a-pull-request reviewing-for-security simplifying-through-abstraction surveying-for-reuse"
actual=$(ls "$PLUGIN/skills" | sort | tr '\n' ' ' | sed 's/ $//')
[ "$actual" = "$expected" ]; check $? "skill set is exactly the seven planned skills"

printf '\n'
if [ "$fail" -eq 0 ]; then printf 'PASS\n'; else printf 'FAILURES PRESENT\n'; fi
exit "$fail"
