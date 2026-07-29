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
grep_flat() {  # grep_flat <file> <literal phrase>
  tr '\n' ' ' < "$1" | tr -s ' ' | grep -qF "$2"
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
  # themselves deletable with the suite still green.
  grep_flat "$B" 'Returning a dropped finding as discarded would tell the user a fabricated claim was merely low-priority.' \
    && grep_flat "$B" 'Carries `reason`, never `value`, `urgency`, or `composite`.'
  check $? "arbitrator: keeps dropped and discarded distinct, including by field carriage"
fi

printf '\n'
if [ "$fail" -eq 0 ]; then printf 'PASS\n'; else printf 'FAILURES PRESENT\n'; fi
exit "$fail"
