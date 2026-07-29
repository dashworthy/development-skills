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
  grep -qF 'never set by an analyst' "$CONDUCTOR/references/finding-schema.md"
  check $? "finding-schema.md states which fields the arbitrator assigns"
fi

# The rubric must carry the composite formula, the gate, and the migration anchor. Each is
# anchored to its own specific line/phrase, not a bare substring search — see the FAIL evidence
# in the fix report for why "80" and "migration" alone are satisfied by unrelated text elsewhere
# in this file even after the line they're meant to test is deleted.
if [ -s "$CONDUCTOR/references/scoring-rubric.md" ]; then
  grep -qF '0.6 × value + 0.4 × urgency' "$CONDUCTOR/references/scoring-rubric.md"
  check $? "scoring-rubric.md carries the composite weights"

  grep -qF 'Default gate: **80**' "$CONDUCTOR/references/scoring-rubric.md"
  check $? "scoring-rubric.md carries the default gate"

  grep -qF 'Anchor — a merged duplicate is a migration' "$CONDUCTOR/references/scoring-rubric.md"
  check $? "scoring-rubric.md carries the merged-duplicate urgency anchor"
fi

# --- skills: frontmatter, naming, and cross-references -----------------------

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

  # Every references/*.md the skill mentions must exist. The pattern also captures a leading
  # chain of ../<dirname>/ components (extended regex, not the old bare 'references/...'), so a
  # cross-skill citation like "../reviewing-a-pull-request/references/scoring-rubric.md" resolves
  # against $d correctly instead of being truncated to "references/scoring-rubric.md" and checked
  # against the wrong directory. `[ -f "$d/$r" ]` handles the embedded ".." itself — no realpath
  # needed. Discovered by Task 4: an analyst skill legitimately cites a reference file that lives
  # in the conductor's directory, not its own.
  missing=""
  for r in $(grep -Eo '(\.\./[a-z0-9-]+/)*references/[a-z0-9-]+\.md' "$f" | sort -u); do
    [ -f "$d/$r" ] || missing="$missing $r"
  done
  [ -z "$missing" ]; check $? "skill $1: all referenced files exist (missing:$missing)"

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
  grep -qF 'git worktree add --detach' "$C"
  check $? "conductor: uses a worktree"

  grep -qF 'git diff --numstat HEAD' "$C"
  check $? "conductor: snapshots with numstat"

  # Anchored to the exact bolded sentence, not a bare case-insensitive "auto-revert" substring —
  # the Red flags list separately says "Auto-reverting a reconciliation violation...", a different
  # phrasing that would keep an unanchored search passing even with this sentence, and the whole
  # rule it belongs to, deleted.
  grep -qF '**Never auto-revert.**' "$C"
  check $? "conductor: forbids auto-revert"

  # The full one-liner, not just "/dev/urandom" — LC_ALL=C and | head -c 6 are both load-bearing
  # (byte-safe character class, and the six-character minimum) and a shortened grep would still
  # pass with either dropped from the actual command.
  grep -qF "LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6" "$C"
  check $? "conductor: run id generation is the full urandom one-liner"

  grep -qF '<YYYY-MM-DD>-<pr-number>-<suffix>' "$C"
  check $? "conductor: run id format is specified"

  # Two separate claims, honestly labeled: this one is the stated *consequence* of an analyst
  # returning a finding instead of a receipt, not the receipt format itself — see the next check.
  grep -qF 'the firewall has already failed' "$C"
  check $? "conductor: states the firewall-failure consequence of reading a finding"

  # The actual receipt contract analysts return. Previously unchecked — this could have been
  # deleted with nothing in the suite noticing.
  grep -qF 'wrote <N> findings to <output_path>' "$C"
  check $? "conductor: names the analyst receipt format"

  # Three specific paths from the artifact layout, not a bare '\.guardtower/' substring search —
  # that matched the JSON dispatch-brief line, a Red-flags bullet, and three other unrelated
  # sentences, so the entire Disk layout could be deleted while any one surviving mention of the
  # bare word ".guardtower/" kept a single check green.
  grep -qF '.guardtower/<run>/findings/<lens>.json' "$C"
  check $? "conductor: names the findings path in the artifact layout"

  grep -qF '.guardtower/<run>/approved.md' "$C"
  check $? "conductor: names approved.md in the artifact layout"

  grep -qF '.guardtower/<run>/deferred.md' "$C"
  check $? "conductor: names deferred.md in the artifact layout"
fi

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
  grep -qF 'the PR builds a capability that already exists whole' "$R"
  check $? "reuse: names the 'reimplements' finding kind"
  grep -qF 'specific logic repeated from an existing local implementation' "$R"
  check $? "reuse: names the 'duplicates' finding kind"
  grep -qF 'leaving two patterns where there was one' "$R"
  check $? "reuse: names the 'diverges' finding kind"

  # Anchored to the tier table's own row labels, not the bare phrases "tier 1"/"tier 2" — those
  # also occur inside "tier 2 only" (the adoption_cost field's own description) and in the Red
  # flags item about a tier-2 finding, so a bare search would still pass with the tier table
  # itself deleted.
  grep -qF '1 — already reachable' "$R" && grep -qF '2 — not yet installed' "$R"
  check $? "reuse: defines both tiers"

  # Anchored to the specific normative sentence, not a bare "adoption_cost" search — that field
  # name necessarily also appears in the Return format JSON schema and in the Red flags list
  # regardless of whether the tier-2 requirement is ever actually stated in prose.
  grep -qF 'Set `adoption_cost` whenever `tier` is `2`' "$R"
  check $? "reuse: requires adoption_cost for tier 2"

  # Anchored to the sentence naming both evidence fields together, not a bare "existing_evidence"
  # search — that field name also appears standalone in the Return format JSON schema.
  grep -qF '`existing_solution` and `existing_evidence`' "$R"
  check $? "reuse: requires the second half of evidence"

  # Exact-cased, punctuated match on the spec's own bolded sentence — not case-insensitive on the
  # bare phrase, which a much weaker sentence ("silence is not a substitute for looking") could
  # also satisfy without carrying the spec's actual wording.
  grep -qF 'Silence is not a null answer.' "$R"
  check $? "reuse: silence is not a null answer"

  # The distinctive half of the spec's own counter-example sentence — "lodash" alone would also
  # match a stray mention in unrelated prose (e.g. an adoption_cost example), so this anchors to
  # the actual worked example rather than the word appearing anywhere.
  grep -qF 'Import lodash for a three-line' "$R"
  check $? "reuse: carries the concrete tier-2 counter-example"
fi

printf '\n'
if [ "$fail" -eq 0 ]; then printf 'PASS\n'; else printf 'FAILURES PRESENT\n'; fi
exit "$fail"
