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

printf '\n'
if [ "$fail" -eq 0 ]; then printf 'PASS\n'; else printf 'FAILURES PRESENT\n'; fi
exit "$fail"
