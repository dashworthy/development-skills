# Guardtower Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `guardtower` Claude Code plugin — one command, `/guardtower:review <url|number>`, that reviews a GitHub PR or GitLab MR through four analyst subagents, scores their findings via an arbitrator, and posts the ones you approve back to the forge.

**Architecture:** A plugin is a directory of markdown documents plus one JSON manifest. There is no runtime code to compile: the deliverables are a command file, seven skill documents, four reference documents, and a manifest. Correctness is therefore *structural* (does it parse, load, and resolve its own cross-references?) and *behavioural* (does an installed instance actually stop where the spec says it stops?). Both are tested by `guardtower/tests/validate.sh`, which every task extends and re-runs.

**Tech Stack:** Markdown with YAML frontmatter; POSIX `sh` and `python3` (stdlib only) for the validator; `gh` / `glab` at runtime. No build step, no package manager, no new dependencies.

**Source spec:** `docs/superpowers/specs/2026-07-29-guardtower-design.md`. Where this plan says "copy verbatim from spec §X", it means exactly that — the spec is the authority for rubric tables, excuse tables, and field lists.

## Global Constraints

Every task's requirements implicitly include these. They come from the spec; the exact values are copied verbatim.

- **Plugin metadata** matches the sibling plugins: `"version": "0.1.0"`, `"author": { "name": "Andrew Leach", "email": "7387639+andyleach@users.noreply.github.com" }`, `"license": "MIT"`.
- **Skill frontmatter carries exactly two keys**, `name` and `description`, delimited by `---` lines — matching `verity/skills/*/SKILL.md`. `name` MUST equal the containing directory name.
- **No `hooks/` directory.** Guardtower is command-only. The validator asserts its absence.
- **No config file.** Nothing is written for a later run to read. Threshold and lens selection are asked fresh every run.
- **No loop.** One pass per run.
- **Run id format:** `<YYYY-MM-DD>-<pr-number>-<suffix>`, `suffix` from `LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6` (minimum six characters, lowercase alphanumeric).
- **Artifact root:** `.guardtower/<run>/` containing `findings/<lens>.json`, `brief.md`, `approved.md`, `deferred.md`.
- **Composite score:** `round(0.6 × value + 0.4 × urgency)`. Default gate: `80`.
- **Lens names** are exactly `reuse`, `security`, `smell`, `abstraction`.
- **`gh` or `glab` is required**; `jq` is NOT required and no skill may shell out to it.
- **Guardtower never modifies the repository under review and never switches the checked-out branch.** All reading of PR content happens inside a detached `git worktree` in a temp directory, removed on every exit path.
- **The conductor reads the arbitrator's brief and nothing else** — never a diff body, never an analyst's finding.
- **Write style:** these documents are read by a model under pressure to skip steps. Follow verity's conventions — an imperative rule stated once and plainly, a "Red flags — STOP" list at the end of every skill, and rationalization tables that answer the excuse rather than merely forbidding it.

---

## File Structure

| Path | Responsibility |
|---|---|
| `guardtower/.claude-plugin/plugin.json` | Plugin manifest |
| `guardtower/README.md` | What it is, how to run it, what it does not guarantee |
| `guardtower/commands/review.md` | Thin entry point; parses the PR ref, invokes the conductor |
| `guardtower/skills/reviewing-a-pull-request/SKILL.md` | Conductor: preflight, worktree, dispatch, reconcile, triage |
| `guardtower/skills/reviewing-a-pull-request/references/finding-schema.md` | Finding fields + return shape, shared by all four analysts |
| `guardtower/skills/reviewing-a-pull-request/references/scoring-rubric.md` | Value/urgency anchors, composite, tie-break |
| `guardtower/skills/reviewing-a-pull-request/references/brief-template.md` | Rendering template for `brief.md` |
| `guardtower/skills/surveying-for-reuse/SKILL.md` | Reuse analyst — the aggressive build-vs-reuse challenge |
| `guardtower/skills/reviewing-for-security/SKILL.md` | Security analyst |
| `guardtower/skills/detecting-code-smell/SKILL.md` | Code smell analyst |
| `guardtower/skills/simplifying-through-abstraction/SKILL.md` | Abstraction analyst |
| `guardtower/skills/arbitrating-findings/SKILL.md` | Verifies evidence, scores, ranks, gates |
| `guardtower/skills/posting-review-comments/SKILL.md` | Forge posting via `gh` / `glab` |
| `guardtower/tests/validate.sh` | Structural + behavioural validator, extended by every task |
| `.claude-plugin/marketplace.json` | **Modify** — add the `guardtower` entry |

Splitting rationale: the four analysts are separate documents because their domain guidance shares nothing but shape, and a reviewer can reject one lens's criteria while accepting another's. Everything they *do* share — return shape, evidence rules, read-only rule — lives once in `finding-schema.md` so it cannot drift four ways.

---

## Task 1: Plugin skeleton and the validation harness

**Files:**
- Create: `guardtower/tests/validate.sh`
- Create: `guardtower/.claude-plugin/plugin.json`
- Create: `guardtower/README.md`
- Modify: `.claude-plugin/marketplace.json`

**Interfaces:**
- Consumes: nothing.
- Produces: `guardtower/tests/validate.sh`, runnable as `sh guardtower/tests/validate.sh` from the repo root, exiting `0` when every check passes and `1` otherwise. Every later task appends checks to it and re-runs it.

- [ ] **Step 1: Write the failing test**

Create `guardtower/tests/validate.sh`:

```sh
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

printf '\n'
if [ "$fail" -eq 0 ]; then printf 'PASS\n'; else printf 'FAILURES PRESENT\n'; fi
exit "$fail"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh guardtower/tests/validate.sh`
Expected: FAIL — `plugin.json exists`, `marketplace.json lists guardtower`, and `README.md exists and is non-empty` report `FAIL`; exit status `1`. Only `no hooks/ directory` passes.

Note that `plugin.json is valid and complete` does **not** appear yet: it sits inside an `if [ -f … ]` guard, so a missing manifest skips it rather than failing it. It appears from Step 4 onward. The `marketplace.json` check prints a Python `AssertionError` naming what is missing above its `FAIL` line — that is the intended diagnostic, not a crash.

- [ ] **Step 3: Write minimal implementation**

Create `guardtower/.claude-plugin/plugin.json`:

```json
{
  "name": "guardtower",
  "description": "PR-scoped advisory review: four analysts (reuse, security, code smell, abstraction) audit a pull request, an arbitrator verifies their evidence and scores it, and the findings you approve are posted back as review comments. Never modifies the code under review.",
  "version": "0.1.0",
  "author": { "name": "Andrew Leach", "email": "7387639+andyleach@users.noreply.github.com" },
  "license": "MIT",
  "keywords": ["code-review", "pull-request", "security", "reuse", "refactoring", "subagents"]
}
```

Create `guardtower/README.md` with these sections (prose written to match verity's README voice — direct, states limits as decisions rather than omissions):

1. **Title + one-paragraph summary.** One command, reviews a PR/MR, four analysts, an arbitrator, an 80 gate, comments posted only after you approve them.
2. **The two rules**, copied verbatim from spec §The two rules.
3. **How a run flows** — copy the mermaid diagram verbatim from spec §How a run flows.
4. **Installation** — marketplace add / plugin install, mirroring verity's README wording. State that `gh` or `glab` must be installed and authenticated, and that `jq` is *not* required.
5. **How to run it** — `/guardtower:review 482`, `/guardtower:review <url>`. State that it requires a PR reference and has no local-diff mode.
6. **What guardtower does not guarantee** — no enforcement hook; reconciliation catches a bad write after the fact and never auto-reverts; the 80 gate is deliberately narrow so most findings land in `deferred.md`; inline comment anchoring is limited by the forges to lines inside a diff hunk.
7. **Where it sits next to verity** — verity hardens tests on a diff before it becomes a PR; guardtower reviews the PR that results. Copy the framing from spec §Where it sits next to verity.

Add to `.claude-plugin/marketplace.json`, in the `plugins` array after the `verity` entry:

```json
    {
      "name": "guardtower",
      "description": "PR-scoped advisory review: four analysts audit a pull request, an arbitrator scores their findings, and the ones you approve are posted back as review comments.",
      "version": "0.1.0",
      "source": "./guardtower",
      "author": {
        "name": "Andrew Leach",
        "email": "7387639+andyleach@users.noreply.github.com"
      }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh guardtower/tests/validate.sh`
Expected: PASS — five `ok` lines, exit status `0`.

- [ ] **Step 5: Verify the plugin actually installs**

This is the check that structural validation cannot make. Run from the repo root:

```sh
TMP=$(mktemp -d) && mkdir -p "$TMP/proj" && cd "$TMP/proj" && git init -q
claude plugin marketplace add "$OLDPWD" --scope local
claude plugin install guardtower@dashworthy --scope local
claude plugin list | grep -A2 guardtower
```

Expected: `Successfully installed plugin: guardtower@dashworthy (scope: local)` and a `Status: ✔ enabled` line.

Then clean up so the scratch install does not linger:

```sh
claude plugin uninstall guardtower@dashworthy --scope local
claude plugin marketplace remove dashworthy
cd - && rm -rf "$TMP"
```

- [ ] **Step 6: Commit**

```bash
git add guardtower/.claude-plugin/plugin.json guardtower/README.md guardtower/tests/validate.sh .claude-plugin/marketplace.json
git commit -m "feat(guardtower): plugin skeleton and validation harness"
```

---

## Task 2: Shared references — finding schema and scoring rubric

Every analyst and the arbitrator depend on these two documents. They come first so the four analysts cannot each invent their own return shape.

**Files:**
- Create: `guardtower/skills/reviewing-a-pull-request/references/finding-schema.md`
- Create: `guardtower/skills/reviewing-a-pull-request/references/scoring-rubric.md`
- Modify: `guardtower/tests/validate.sh`

**Interfaces:**
- Consumes: Task 1's validator.
- Produces: the finding JSON contract every analyst emits and the arbitrator consumes:

```json
{
  "findings": [
    {
      "lens": "reuse | security | smell | abstraction",
      "target_file": "<repo-relative path>",
      "target_line": "<line or start-end range, at the head sha>",
      "evidence": "<the actual source text at that location>",
      "claim": "<what is wrong, as an observable consequence>",
      "rationale": "<what breaks, for whom, and how they find out>",
      "proposal": "<what to do instead — prose, never a patch>",
      "in_diff": true,
      "also_at": ["<file:line>"],

      "kind": "<reuse lens only: reimplements | duplicates | diverges>",
      "tier": 1,
      "existing_solution": "<reuse lens only>",
      "existing_evidence": "<reuse lens only>",
      "adoption_cost": "<reuse lens, tier 2 only>"
    }
  ]
}
```

`id`, `value`, `urgency`, and `composite` are **absent** from an analyst's output — the arbitrator assigns them.

- [ ] **Step 1: Write the failing test**

Append to `guardtower/tests/validate.sh`, immediately before the final `printf '\n'` block:

```sh
# --- shared references ------------------------------------------------------

# Defined here because this is the first appended block that needs it; later
# blocks reuse it rather than redefining it.
CONDUCTOR="$PLUGIN/skills/reviewing-a-pull-request"

for ref in finding-schema scoring-rubric; do
  [ -s "$CONDUCTOR/references/$ref.md" ]; check $? "reference $ref.md exists"
done

# The finding contract must name every field the arbitrator relies on.
if [ -s "$CONDUCTOR/references/finding-schema.md" ]; then
  miss=""
  for field in lens target_file target_line evidence claim rationale proposal \
               in_diff also_at kind tier existing_solution existing_evidence adoption_cost; do
    grep -q "$field" "$CONDUCTOR/references/finding-schema.md" || miss="$miss $field"
  done
  [ -z "$miss" ]; check $? "finding-schema.md documents every field (missing:$miss)"

  # Fields the arbitrator owns must be explicitly excluded from analyst output.
  grep -qi "arbitrator" "$CONDUCTOR/references/finding-schema.md"
  check $? "finding-schema.md states which fields the arbitrator assigns"
fi

# The rubric must carry the composite formula, the gate, and the migration anchor.
if [ -s "$CONDUCTOR/references/scoring-rubric.md" ]; then
  grep -q "0.6" "$CONDUCTOR/references/scoring-rubric.md" &&
  grep -q "0.4" "$CONDUCTOR/references/scoring-rubric.md"
  check $? "scoring-rubric.md carries the composite weights"

  grep -q "80" "$CONDUCTOR/references/scoring-rubric.md"
  check $? "scoring-rubric.md carries the default gate"

  grep -qi "migration" "$CONDUCTOR/references/scoring-rubric.md"
  check $? "scoring-rubric.md carries the merged-duplicate urgency anchor"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh guardtower/tests/validate.sh`
Expected: FAIL on `reference finding-schema.md exists` and `reference scoring-rubric.md exists`; exit status `1`.

- [ ] **Step 3: Write minimal implementation**

Create `finding-schema.md` containing, in this order:

1. **A one-line statement of purpose**: this is the contract every analyst writes and the arbitrator reads.
2. **The field table**, copied verbatim from spec §Findings, including the five reuse-only rows.
3. **The JSON return shape**, exactly as given in this task's Interfaces block above.
4. **"What the arbitrator owns"** — `id`, `value`, `urgency`, `composite` are never set by an analyst. State that emitting them is an error, not a helpful extra.
5. **"Evidence is not optional"** — `evidence` must be the actual source text at `target_line`, not a paraphrase, because the arbitrator re-reads that location and compares. A paraphrase fails verification and the finding is dropped.
6. **"Where you read"** — every path is relative to the **worktree** the dispatch brief names, never the user's checked-out tree.
7. **"You are read-only"** — the analyst writes exactly one file, its own `findings/<lens>.json`, and nothing else. Mirror the framing of `verity/skills/auditing-test-gaps/SKILL.md` §You are read-only.
8. **`in_diff`** — set `true` only when `target_line` falls inside a hunk of the `<base-sha>...<head-sha>` diff. It decides inline versus summary placement and a wrong value costs a misplaced comment.

Create `scoring-rubric.md` containing:

1. **Why the rubric is published** — a bare 0–100 is not reproducible across runs.
2. **The value table**, copied verbatim from spec §Scoring.
3. **The urgency table**, copied verbatim from spec §Scoring.
4. **The merged-duplicate anchor**, copied verbatim from spec §Scoring ("Anchor — a merged duplicate is a migration"), including the worked arithmetic showing that the intuitive reading composites to 75 and is discarded while the correct one reaches 83.
5. **The composite formula and the default gate.**
6. **The tie-break**, copied verbatim from spec §Scoring: composite desc, then value desc, then `target_file` asc, then `id` asc — a total order so two runs render identically.

- [ ] **Step 4: Run test to verify it passes**

Run: `sh guardtower/tests/validate.sh`
Expected: PASS — all checks `ok`, exit status `0`.

- [ ] **Step 5: Commit**

```bash
git add guardtower/skills/reviewing-a-pull-request/references guardtower/tests/validate.sh
git commit -m "feat(guardtower): finding schema and scoring rubric"
```

---

## Task 3: The conductor skill

**Files:**
- Create: `guardtower/skills/reviewing-a-pull-request/SKILL.md`
- Create: `guardtower/skills/reviewing-a-pull-request/references/brief-template.md`
- Modify: `guardtower/tests/validate.sh`

**Interfaces:**
- Consumes: `finding-schema.md`, `scoring-rubric.md` from Task 2.
- Produces: the **dispatch brief** every analyst receives —

```
{
  "lens":          "reuse | security | smell | abstraction",
  "worktree":      "<absolute path to the detached worktree>",
  "base_sha":      "<PR base sha>",
  "head_sha":      "<PR head sha>",
  "changed_paths": ["<repo-relative path>", ...],
  "output_path":   "<absolute path to .guardtower/<run>/findings/<lens>.json>"
}
```

  and the **analyst receipt** contract: an analyst returns only `wrote <N> findings to <output_path>` — never a finding, never a summary of one.

- [ ] **Step 1: Write the failing test**

Append to `guardtower/tests/validate.sh`, before the final `printf` block. This block also adds the generic frontmatter and cross-reference checks that every later task's skill will be measured by:

```sh
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

  keys=$(printf '%s\n' "$fm" | sed -n 's/^\([a-z_]*\): .*/\1/p' | sort -u | tr '\n' ' ')
  [ "$keys" = "description name " ]; check $? "skill $1: frontmatter has only name+description (got '$keys')"

  # Every references/*.md the skill mentions must exist.
  missing=""
  for r in $(grep -o 'references/[a-z0-9-]*\.md' "$f" | sort -u); do
    [ -f "$d/$r" ] || missing="$missing $r"
  done
  [ -z "$missing" ]; check $? "skill $1: all referenced files exist (missing:$missing)"

  # House style: every skill ends with a stop list.
  grep -q 'Red flags' "$f"; check $? "skill $1: has a 'Red flags — STOP' section"
}

check_skill reviewing-a-pull-request

# $CONDUCTOR was defined by Task 2's block, which runs above this one.
for ref in brief-template; do
  [ -s "$CONDUCTOR/references/$ref.md" ]; check $? "reference $ref.md exists"
done

# The conductor must carry the invariants that make the design hold.
C="$CONDUCTOR/SKILL.md"
if [ -s "$C" ]; then
  grep -q 'worktree' "$C";              check $? "conductor: uses a worktree"
  grep -q 'numstat' "$C";               check $? "conductor: snapshots with numstat"
  grep -qi 'never auto-revert' "$C";    check $? "conductor: forbids auto-revert"
  grep -q 'urandom' "$C";               check $? "conductor: run id uses /dev/urandom"
  grep -qi 'receipt' "$C";              check $? "conductor: analysts return receipts only"
  grep -q '\.guardtower/' "$C";         check $? "conductor: names the artifact root"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh guardtower/tests/validate.sh`
Expected: FAIL on `skill reviewing-a-pull-request: SKILL.md exists`, both `reference ... exists` checks, and every conductor invariant check; exit status `1`.

- [ ] **Step 3: Write minimal implementation**

Create `SKILL.md` with this exact frontmatter:

```markdown
---
name: reviewing-a-pull-request
description: Use when reviewing a GitHub pull request or GitLab merge request with guardtower - dispatches reuse, security, code smell and abstraction analysts against the PR in an isolated worktree, scores their findings through an arbitrator, and posts the ones the user approves. Never modifies the repository under review.
---
```

Body sections, in order:

1. **The two rules** — copied verbatim from spec §The two rules, stated before anything else, as verity states its Iron Rule first.
2. **Ask, don't configure** — threshold and lens selection are asked fresh every run; nothing is written for a later run to read. Name the concrete reason: verity's removed config layer accounted for ~15 of ~34 defects found during its build.
3. **Context discipline** — the conductor holds the run's brief, verdicts and numbers. It does not read diffs, source files, or analyst findings. Every step needing to read one is dispatched. State that the arbitrator's return is the single permitted exception, and that reading it is required.
4. **Preflight** — the seven numbered steps from spec §Preflight, verbatim in substance: detect forge; verify CLI; resolve PR (base sha, head sha, changed paths only); stop if nothing reviewable changed; fetch + `git worktree add --detach`; snapshot the main tree before the first subagent of the run, whichever subagent that is; agree threshold and lenses. Include the exact commands:
   - `git remote get-url origin`
   - `gh auth status` / `glab auth status`
   - `gh pr view <n> --json baseRefOid,headRefOid,files` / `glab mr view <n>`
   - `git fetch origin pull/<n>/head` (GitHub) or `git fetch origin merge-requests/<n>/head` (GitLab)
   - `git worktree add --detach <tempdir> <head-sha>`
   - `git diff --numstat HEAD` and `git status --porcelain`
5. **Run id** — the format and the `/dev/urandom` one-liner, verbatim from spec §Preflight. Include the note that this removes the last exception to "a run never looks at prior artifacts", so a future editor does not reintroduce a directory scan.
6. **The pass** — dispatch one analyst per selected lens in parallel per `superpowers:dispatching-parallel-agents`, each with the dispatch brief from this task's Interfaces block. State plainly: **an analyst returns a receipt; if you find yourself reading a finding, the firewall has already failed.** Then dispatch `arbitrating-findings` — with the **whole** payload Task 8 declares, not just the paths: `finding_paths`, `worktree`, `base_sha`, `head_sha`, `threshold` (the value agreed at preflight step 7), `lenses_run`. Spell every field's provenance out in prose the way **Post** does for the poster, and say what breaks without `threshold` (the user's gate is silently discarded and the arbitrator falls back to its own default) and without `worktree` (evidence is verified against the user's checked-out tree instead of the detached one).
7. **Reconcile** — spec §Reconciliation verbatim in substance: snapshot before the *first* subagent of the run, re-measure after the *last* (the arbitrator), compare counts not status entries, resolve symlinks with `readlink -f`, halt on anything outside `.guardtower/`, never auto-revert. State why the two ends are where they are: the check is a pair of measurements worth exactly what it encloses, so one snapshot and one re-measurement must bracket *every* subagent the run dispatches — today the first analyst through the arbitrator — rather than naming any one subagent as the boundary. Include the reason counts beat `git status`: a porcelain entry reads ` M path` identically before and after a write.
8. **Triage** — present every finding that cleared the gate with its scores and rationale; the user marks each in scope or out of scope; write `approved.md` and `deferred.md`. Nothing is posted before this.
9. **Post** — dispatch `posting-review-comments` with the approved set. Only on an explicit PR run, only after triage.
10. **Cleanup** — `git worktree remove --force <tempdir>` on **every** exit path, including a halt. Then `git worktree prune`.
11. **Reporting, always** — what was posted, what was dropped by evidence failure with reasons, what was discarded by the gate, and every lens the user chose not to run. Then invoke `superpowers:verification-before-completion`.
12. **Red flags — STOP** — at minimum: reading a diff or a finding in the conductor's own context; switching the user's branch; running `gh pr checkout`; posting anything not marked in scope; auto-reverting a reconciliation violation; leaving the worktree behind; writing a config file "to make this more reliable next time"; reporting a threshold met without the numbers that prove it.

Create `brief-template.md` — a `{{PLACEHOLDER}}` template mirroring `verity/skills/conducting-test-hardening/references/brief-template.md` in style. It must render: run id, PR reference, base and head sha, lenses run and lenses skipped, threshold; a summary count table (passed / dropped on evidence / discarded by gate); then one block per passed finding showing `{{ID}}`, lens, `{{COMPOSITE}}` with `{{VALUE}}`/`{{URGENCY}}` broken out, `{{TARGET_FILE}}:{{TARGET_LINE}}`, `in_diff`, `{{ALSO_AT}}`, claim, rationale, proposal, and — for reuse findings — `{{KIND}}`, `{{TIER}}`, `{{EXISTING_SOLUTION}}`, and `{{ADOPTION_COST}}`. Include HTML-comment instructions to omit reuse-only lines for non-reuse findings, as verity's template does, and to omit the Also at line for a finding whose `also_at` array is empty — an abstraction finding usually spans several files and `{{TARGET_FILE}}` names only the clearest, so a template with no `{{ALSO_AT}}` slot reports one occurrence of a problem found in five.

- [ ] **Step 4: Run test to verify it passes**

Run: `sh guardtower/tests/validate.sh`
Expected: PASS — all checks `ok`, exit status `0`.

- [ ] **Step 5: Commit**

```bash
git add guardtower/skills/reviewing-a-pull-request guardtower/tests/validate.sh
git commit -m "feat(guardtower): conductor skill and brief template"
```

---

## Task 4: The reuse analyst

The most specified of the four. Build it first so the remaining three can follow its shape.

**Files:**
- Create: `guardtower/skills/surveying-for-reuse/SKILL.md`
- Modify: `guardtower/tests/validate.sh`

**Interfaces:**
- Consumes: the dispatch brief from Task 3; the finding contract from Task 2.
- Produces: `findings/reuse.json` in the shape from Task 2, with `kind`, `tier`, `existing_solution`, `existing_evidence` always set and `adoption_cost` set whenever `tier` is `2`. Returns only `wrote <N> findings to <output_path>`.

- [ ] **Step 1: Write the failing test**

Append to `guardtower/tests/validate.sh`, before the final `printf` block:

```sh
check_skill surveying-for-reuse

R="$PLUGIN/skills/surveying-for-reuse/SKILL.md"
if [ -s "$R" ]; then
  for k in reimplements duplicates diverges; do
    grep -q "$k" "$R"; check $? "reuse: names the '$k' finding kind"
  done
  grep -qi 'tier 1' "$R" && grep -qi 'tier 2' "$R"
  check $? "reuse: defines both tiers"
  grep -qi 'adoption_cost' "$R";       check $? "reuse: requires adoption_cost for tier 2"
  grep -qi 'existing_evidence' "$R";   check $? "reuse: requires the second half of evidence"
  grep -qi 'silence is not' "$R";      check $? "reuse: silence is not a null answer"
  grep -qi 'lodash' "$R";              check $? "reuse: carries the concrete tier-2 counter-example"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh guardtower/tests/validate.sh`
Expected: FAIL on `skill surveying-for-reuse: SKILL.md exists` and every reuse-specific check; exit status `1`.

- [ ] **Step 3: Write minimal implementation**

Create `SKILL.md` with this exact frontmatter:

```markdown
---
name: surveying-for-reuse
description: Use when dispatched by guardtower to audit a pull request for code that reimplements what already exists - challenges the decision to build at all, cites what supersedes it, and modifies nothing
---
```

Body, in order:

1. **You are read-only** — first, before anything that reads code closely enough to be mistaken for permission to change it. Mirror `verity/skills/auditing-test-gaps/SKILL.md` §You are read-only. You write exactly one file: your `output_path`.
2. **What you receive** — the dispatch brief fields from Task 3, and the reminder that every path resolves inside `worktree`, never the user's checked-out tree.
3. **The mandatory question** — copied in substance from spec §The reuse lens: for every new file, module, class, exported function or utility the PR introduces, answer in writing *what already does this?* A null answer is acceptable **only** with the search that produced it — paths scanned, manifest entries checked, stdlib/platform APIs considered. **Silence is not a null answer.** State that this is a standing burden, not an occasional finding.
4. **Two tiers** — the tier table copied verbatim from spec §The reuse lens, followed by the asymmetry paragraph including both worked examples verbatim: *do not hand-roll JWT parsing when `jose` exists* is legitimate tier 2; *import lodash for a three-line `groupBy`* is not.
5. **Three kinds of finding** — `reimplements`, `duplicates`, `diverges`, defined verbatim from spec §The reuse lens, strongest first.
6. **Evidence has two halves** — `evidence` cites the new code; `existing_solution` + `existing_evidence` cite what supersedes it. State the failure this closes: a confident "library X already does this" where X does something merely adjacent. State that the arbitrator verifies both halves and drops the finding if the second fails.
7. **Rationalizations, and what they're worth** — the six-row excuse table copied verbatim from spec §The reuse lens. Add the framing sentence: these are arguments for triage, made by a human after the finding exists, never reasons to withhold it.
8. **Scoring input** — you do not score. Read `../reviewing-a-pull-request/references/scoring-rubric.md` so your `rationale` gives the arbitrator what it needs, in particular the merged-duplicate urgency anchor.
9. **Return format** — the JSON from Task 2's Interfaces, with the reuse-only fields required. State the receipt rule: return `wrote <N> findings to <output_path>` and nothing else.
10. **Red flags — STOP** — writing any file other than `output_path`; proposing a dependency that is not well-established; a tier 2 finding with no `adoption_cost`; a finding whose `existing_solution` you have not opened and read; answering the mandatory question with silence; emitting `id`, `value`, `urgency` or `composite`; returning findings in your reply instead of a receipt.

- [ ] **Step 4: Run test to verify it passes**

Run: `sh guardtower/tests/validate.sh`
Expected: PASS — all checks `ok`, exit status `0`.

- [ ] **Step 5: Commit**

```bash
git add guardtower/skills/surveying-for-reuse guardtower/tests/validate.sh
git commit -m "feat(guardtower): reuse analyst with tiered build-vs-reuse challenge"
```

---

## Task 5: The security analyst

**Files:**
- Create: `guardtower/skills/reviewing-for-security/SKILL.md`
- Modify: `guardtower/tests/validate.sh`

**Interfaces:**
- Consumes: the dispatch brief from Task 3; the finding contract from Task 2.
- Produces: `findings/security.json`; returns a receipt only. Sets no reuse-only fields.

- [ ] **Step 1: Write the failing test**

Append to `guardtower/tests/validate.sh`, before the final `printf` block:

```sh
check_skill reviewing-for-security

S="$PLUGIN/skills/reviewing-for-security/SKILL.md"
if [ -s "$S" ]; then
  grep -qi 'exploitable' "$S"
  check $? "security: requires a stated exploitation path"
  grep -qi 'theoretical' "$S"
  check $? "security: rules out theoretical findings"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh guardtower/tests/validate.sh`
Expected: FAIL on `skill reviewing-for-security: SKILL.md exists` and both security-specific checks; exit status `1`.

- [ ] **Step 3: Write minimal implementation**

Create `SKILL.md` with this exact frontmatter:

```markdown
---
name: reviewing-for-security
description: Use when dispatched by guardtower to audit a pull request for security defects - reports only findings with a stated exploitation path and cited evidence, and modifies nothing
---
```

Body, in order:

1. **You are read-only** — same framing as Task 4, stated first.
2. **What you receive** — the dispatch brief fields.
3. **What counts as a finding here** — a defect with a **stated exploitation path**: who the attacker is, what they control, what they get. State the rule directly: *a finding you cannot write an exploitation path for is not a finding.* Security review has the highest false-positive rate of the four lenses, and a wrong one that clears the gate costs the user a review and costs every later finding its credibility.
4. **A taxonomy to work through**, each with what to look for in a diff: injection (SQL, command, template, path traversal); authentication and session handling; authorization and object-level access; secrets and credentials in code, logs, or error messages; cryptography (weak primitives, non-constant-time comparison, predictable randomness — including `Math.random()` and unseeded PRNGs where a CSPRNG is required); deserialization and parsing of untrusted input; SSRF and outbound request construction; unsafe defaults in newly added configuration; dependency changes that widen attack surface.
5. **Theoretical findings are out of scope** — say plainly that "this could be dangerous if reached from untrusted input" is not a finding unless you can name the path by which untrusted input reaches it. If you cannot trace it, do not emit it.
6. **Severity feeds scoring, it is not scoring** — you set `rationale` so the arbitrator can score; you never set `value`, `urgency`, or `composite`. Read `../reviewing-a-pull-request/references/scoring-rubric.md`.
7. **Return format** — the JSON from Task 2; receipt only.
8. **Red flags — STOP** — a finding with no exploitation path; flagging a pattern without reading whether the surrounding code already mitigates it; reporting a dependency CVE without confirming the vulnerable code path is reachable; writing any file other than `output_path`; returning findings instead of a receipt.

- [ ] **Step 4: Run test to verify it passes**

Run: `sh guardtower/tests/validate.sh`
Expected: PASS — all checks `ok`, exit status `0`.

- [ ] **Step 5: Commit**

```bash
git add guardtower/skills/reviewing-for-security guardtower/tests/validate.sh
git commit -m "feat(guardtower): security analyst"
```

---

## Task 6: The code smell analyst

**Files:**
- Create: `guardtower/skills/detecting-code-smell/SKILL.md`
- Modify: `guardtower/tests/validate.sh`

**Interfaces:**
- Consumes: the dispatch brief from Task 3; the finding contract from Task 2.
- Produces: `findings/smell.json`; returns a receipt only. Sets no reuse-only fields.

- [ ] **Step 1: Write the failing test**

Append to `guardtower/tests/validate.sh`, before the final `printf` block:

```sh
check_skill detecting-code-smell

M="$PLUGIN/skills/detecting-code-smell/SKILL.md"
if [ -s "$M" ]; then
  grep -qi 'style' "$M"
  check $? "smell: separates smells from style preferences"
  grep -qi 'formatter\|linter' "$M"
  check $? "smell: defers to the project's existing formatter/linter"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh guardtower/tests/validate.sh`
Expected: FAIL on `skill detecting-code-smell: SKILL.md exists` and both smell-specific checks; exit status `1`.

- [ ] **Step 3: Write minimal implementation**

Create `SKILL.md` with this exact frontmatter:

```markdown
---
name: detecting-code-smell
description: Use when dispatched by guardtower to audit a pull request for maintainability defects - reports smells that name a concrete future failure, never style preferences, and modifies nothing
---
```

Body, in order:

1. **You are read-only** — same framing as Task 4, stated first.
2. **What you receive** — the dispatch brief fields.
3. **A smell is a predicted failure, not a preference** — the defining rule. Every finding must name the concrete way this bites someone later: the change that will be made wrong, the bug that will be introduced, the reader who will misunderstand. *If the only thing you can say is that you would have written it differently, it is not a finding.*
4. **Style is out of scope, and so is anything the project's own tooling owns** — formatting, import order, quote style, and naming conventions already enforced by a linter or formatter belong to that tool, not to guardtower. Open the repo's linter and formatter configuration and see what is actually configured before flagging anything such a tool would have caught. Duplicating a linter produces noise the user has already decided about.
5. **What to look for**, each with the failure it predicts: functions doing several unrelated things; parameter lists that encode a missing type; boolean flag parameters that split a function into two functions; deeply nested conditionals where a guard clause fits; primitive obsession where an invariant should be enforced by a type; mutable shared state across call boundaries; error handling that swallows the error or returns a sentinel a caller will forget to check; comments that describe *what* rather than *why*, and comments that no longer match the code; dead code and unreachable branches introduced by the diff; names that mislead about behaviour (a `get*` that mutates, an `is*` that returns a value).
6. **Scope is the diff** — a smell in untouched code is not this PR's finding unless the diff made it materially worse. Say so plainly; otherwise every review reports the whole codebase.
7. **Scoring input** — read `../reviewing-a-pull-request/references/scoring-rubric.md`. Note honestly that most smell findings score in the 40–69 value band and will not clear the gate, and that this is correct: the gate exists so a real defect is not buried under twelve preferences.
8. **Return format** — the JSON from Task 2; receipt only.
9. **Red flags — STOP** — a finding whose rationale is preference; flagging what the project's linter or formatter already owns; reporting untouched code the diff did not worsen; writing any file other than `output_path`; returning findings instead of a receipt.

- [ ] **Step 4: Run test to verify it passes**

Run: `sh guardtower/tests/validate.sh`
Expected: PASS — all checks `ok`, exit status `0`.

- [ ] **Step 5: Commit**

```bash
git add guardtower/skills/detecting-code-smell guardtower/tests/validate.sh
git commit -m "feat(guardtower): code smell analyst"
```

---

## Task 7: The abstraction analyst

**Files:**
- Create: `guardtower/skills/simplifying-through-abstraction/SKILL.md`
- Modify: `guardtower/tests/validate.sh`

**Interfaces:**
- Consumes: the dispatch brief from Task 3; the finding contract from Task 2.
- Produces: `findings/abstraction.json`; returns a receipt only. Sets no reuse-only fields. Uses `also_at` heavily, since findings here typically span several files.

- [ ] **Step 1: Write the failing test**

Append to `guardtower/tests/validate.sh`, before the final `printf` block:

```sh
check_skill simplifying-through-abstraction

A="$PLUGIN/skills/simplifying-through-abstraction/SKILL.md"
if [ -s "$A" ]; then
  grep -q 'also_at' "$A"
  check $? "abstraction: uses also_at for multi-file findings"
  grep -qi 'premature\|speculative' "$A"
  check $? "abstraction: rules out speculative abstraction"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh guardtower/tests/validate.sh`
Expected: FAIL on `skill simplifying-through-abstraction: SKILL.md exists` and both abstraction-specific checks; exit status `1`.

- [ ] **Step 3: Write minimal implementation**

Create `SKILL.md` with this exact frontmatter:

```markdown
---
name: simplifying-through-abstraction
description: Use when dispatched by guardtower to audit a pull request for structural complexity a higher-level pattern would tame - reports only abstractions justified by repetition that already exists, and modifies nothing
---
```

Body, in order:

1. **You are read-only** — same framing as Task 4, stated first.
2. **What you receive** — the dispatch brief fields.
3. **Abstraction is earned, never anticipated** — the defining rule. Propose an abstraction only where the repetition or branching it would collapse **already exists in the code**, and say how many occurrences and where. *Two occurrences is a coincidence; three is a pattern.* An abstraction proposed for a case that has not happened yet is speculative, and speculative abstraction costs more than the duplication it prevents.
4. **What to look for**, each with the pattern that tames it: sprawling hard-coded branching → a table or strategy map; a duplicated conditional ladder appearing in several places → one policy object; ad-hoc sequencing and orchestration → an explicit pipeline; scattered state transitions with no single place to read the machine → a state machine; repeated try/retry/backoff ladders → one retry policy; parallel `switch` statements over the same enum in different files → polymorphism or one dispatch table.
5. **Say what it costs** — every abstraction adds indirection, and indirection has a reader cost. Each finding's `proposal` must state what the reader gains against what the indirection costs. A finding that only names the gain is incomplete.
6. **Multi-file findings** — these usually span several files. Put the clearest occurrence in `target_file`/`target_line` and every other in `also_at`. Expect `in_diff` to be `false` often, which routes the finding to the summary comment rather than an inline one; that is correct, not a failure.
7. **Scope is the diff** — the repetition must be introduced or extended by this PR. Pre-existing repetition the diff did not touch is not this PR's finding.
8. **Scoring input** — read `../reviewing-a-pull-request/references/scoring-rubric.md`.
9. **Return format** — the JSON from Task 2; receipt only.
10. **Red flags — STOP** — proposing an abstraction for repetition that does not yet exist; proposing one without stating its indirection cost; counting two occurrences as a pattern; reporting pre-existing repetition the diff did not touch; writing any file other than `output_path`; returning findings instead of a receipt.

- [ ] **Step 4: Run test to verify it passes**

Run: `sh guardtower/tests/validate.sh`
Expected: PASS — all checks `ok`, exit status `0`.

- [ ] **Step 5: Commit**

```bash
git add guardtower/skills/simplifying-through-abstraction guardtower/tests/validate.sh
git commit -m "feat(guardtower): abstraction analyst"
```

---

## Task 8: The arbitrator

**Files:**
- Create: `guardtower/skills/arbitrating-findings/SKILL.md`
- Modify: `guardtower/tests/validate.sh`

**Interfaces:**
- Consumes: a dispatch payload of `finding_paths` (the `findings/<lens>.json` files by path, one per lens actually dispatched), `worktree`, `base_sha`, `head_sha`, `threshold`, and `lenses_run`; plus `finding-schema.md` and `scoring-rubric.md`. **The conductor must hand over all six** — `threshold` is the gate this skill applies (without it the value agreed at preflight step 7 is discarded and this skill falls back to its own default), and `worktree` is where `target_file` and `existing_solution` resolve (without it verification runs against the user's checked-out tree). Task 3's **The pass** is where that payload is written down.
- Produces: to the conductor, the passed set plus counts —

```json
{
  "passed": [
    {
      "id": "<lens>-<nnn>",
      "lens": "…", "target_file": "…", "target_line": "…",
      "claim": "…", "rationale": "…", "proposal": "…", "in_diff": true,
      "also_at": ["…"],
      "kind": "…", "tier": 1, "existing_solution": "…", "adoption_cost": "…",
      "value": 92, "urgency": 95, "composite": 93
    }
  ],
  "dropped":   [ { "lens": "…", "target_file": "…", "target_line": "…", "reason": "<why the evidence did not hold>" } ],
  "discarded": [ { "id": "…", "lens": "…", "claim": "…", "value": 84, "urgency": 41, "composite": 67 } ]
}
```

  `passed` is sorted by the total order. `dropped` are evidence failures, never scored. `discarded` cleared verification but not the gate.

- [ ] **Step 1: Write the failing test**

Append to `guardtower/tests/validate.sh`, before the final `printf` block:

```sh
check_skill arbitrating-findings

B="$PLUGIN/skills/arbitrating-findings/SKILL.md"
if [ -s "$B" ]; then
  grep -qi 'drop' "$B";        check $? "arbitrator: drops findings whose evidence fails"
  grep -q 'composite' "$B";    check $? "arbitrator: computes the composite"
  grep -qi 'total order' "$B"; check $? "arbitrator: ranks with a total order"
  grep -q 'existing_evidence' "$B"
  check $? "arbitrator: verifies both halves of reuse evidence"
  grep -qi 'discarded' "$B" && grep -qi 'dropped' "$B"
  check $? "arbitrator: keeps dropped and discarded distinct"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh guardtower/tests/validate.sh`
Expected: FAIL on `skill arbitrating-findings: SKILL.md exists` and every arbitrator-specific check; exit status `1`.

- [ ] **Step 3: Write minimal implementation**

Create `SKILL.md` with this exact frontmatter:

```markdown
---
name: arbitrating-findings
description: Use when dispatched by guardtower to verify and rank analyst findings - re-reads each finding's cited evidence against the source, drops what does not hold, scores value and urgency against the published rubric, and returns only what clears the gate
---
```

Body, in order:

1. **You read the finding files yourself** — first. You are handed *paths*, not findings. The conductor has not read them and must not: reading them is your job and yours alone. This is what the whole design's context firewall rests on.
2. **What you receive** — `{ finding_paths: [...], worktree, base_sha, head_sha, threshold, lenses_run }`.
3. **Verify before you score** — for each finding, open `target_file` at `target_line` **inside the worktree** and compare against `evidence`. The evidence holds only if the cited text is actually there. If the line moved, the text differs, or the cited code turns out to be a comment or a string literal, **drop the finding with a stated reason**. Do not score it low; dropping and low-scoring are different outcomes and the report distinguishes them.
4. **Reuse findings have two halves** — also open `existing_solution` and confirm `existing_evidence` shows it genuinely covers the claim. A superseding solution that does something merely adjacent fails verification and the finding drops. For `tier: 2`, additionally require a non-empty `adoption_cost`; a tier 2 finding without one drops.
5. **Score against the published rubric** — read `../reviewing-a-pull-request/references/scoring-rubric.md` and apply it as written. State that inventing your own criteria destroys reproducibility, which is the only reason the rubric is published at all. Apply the merged-duplicate urgency anchor to `reimplements` and `duplicates` findings.
6. **Assign ids** — `<lens>-<nnn>`, zero-padded to three digits, numbered per lens in the order findings appear in that lens's file. Ids are yours; analysts never set them.
7. **Gate and rank** — keep findings whose `composite` is at or above `threshold`. Sort `passed` by the total order: composite desc, value desc, `target_file` asc, `id` asc. State why the last two exist — two runs over the same findings must render an identical brief.
8. **Three outcomes, never conflated** — `dropped` (evidence failed, never scored), `discarded` (verified but below the gate, scored), `passed`. Returning a dropped finding as discarded would tell the user a fabricated claim was merely low-priority.
9. **Return format** — the JSON from this task's Interfaces block.
10. **Red flags — STOP** — scoring a finding without opening the file it cites; scoring a reuse finding without opening its `existing_solution`; inventing scoring criteria instead of applying the rubric; conflating dropped with discarded; writing any file; returning findings that did not clear the gate inside `passed`; letting an analyst-supplied `id`, `value`, `urgency` or `composite` through unchecked.

- [ ] **Step 4: Run test to verify it passes**

Run: `sh guardtower/tests/validate.sh`
Expected: PASS — all checks `ok`, exit status `0`.

- [ ] **Step 5: Commit**

```bash
git add guardtower/skills/arbitrating-findings guardtower/tests/validate.sh
git commit -m "feat(guardtower): arbitrator with evidence verification and gating"
```

---

## Task 9: The forge poster

**Files:**
- Create: `guardtower/skills/posting-review-comments/SKILL.md`
- Modify: `guardtower/tests/validate.sh`

**Interfaces:**
- Consumes: `{ forge: "github"|"gitlab", pr_number, repo, base_sha, head_sha, run_id, lenses_run, lenses_skipped, approved: [...] }` — `approved` being the in-scope subset of the arbitrator's `passed`. **The conductor must hand over all nine.** `forge`, `pr_number`, `repo`, `approved` and `head_sha` are this task's declared interface; the other four are carried alongside them because two requirements below cannot be met without them and the conductor already holds all four at zero extra cost — GitLab's discussion API needs `base_sha` alongside `head_sha` to anchor a diff position, and the summary comment cannot name the run or admit which lenses were skipped without `run_id`, `lenses_run` and `lenses_skipped`. Per spec §The pass, a dispatch that names a subset of what the dispatched skill reads is a bug even when nothing visibly breaks: the poster would be told by its own instructions to consult fields it was never given. Task 3's **Post** is where that payload is written down, and the skill itself documents the split between the declared five and the carried four so it is not silent.
- Produces: a single submitted review, and a return of `{ posted_inline: <n>, posted_summary: <n>, review_url: "<url>" }`.

- [ ] **Step 1: Write the failing test**

Append to `guardtower/tests/validate.sh`, before the final `printf` block:

```sh
check_skill posting-review-comments

P="$PLUGIN/skills/posting-review-comments/SKILL.md"
if [ -s "$P" ]; then
  grep -q 'gh api' "$P";   check $? "poster: uses gh api for GitHub"
  grep -q 'glab' "$P";     check $? "poster: uses glab for GitLab"
  grep -qi 'pending' "$P" || grep -qi 'single review' "$P"
  check $? "poster: posts one review, not one comment per finding"
  grep -q 'in_diff' "$P";  check $? "poster: routes on in_diff"
  grep -qi 'never post' "$P"
  check $? "poster: refuses to post anything not approved"
fi

# --- no skill may shell out to jq ------------------------------------------

! grep -rqw jq "$PLUGIN/skills" "$PLUGIN/commands" 2>/dev/null
check $? "no skill shells out to jq"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh guardtower/tests/validate.sh`
Expected: FAIL on `skill posting-review-comments: SKILL.md exists` and every poster-specific check; exit status `1`. The `jq` check passes already and must keep passing.

- [ ] **Step 3: Write minimal implementation**

Create `SKILL.md` with this exact frontmatter:

```markdown
---
name: posting-review-comments
description: Use when dispatched by guardtower to post approved review findings to a GitHub pull request or GitLab merge request - posts one review, never posts a finding the user did not approve, and writes nothing to the repository
---
```

Body, in order:

1. **You post only what you were given** — first and unconditionally. Every item in `approved` was marked in scope by a human. Anything not in that array does not exist as far as this skill is concerned: not a deferred finding, not one you think was cut in error, not one you notice yourself while reading. **Never post a finding the user did not approve.**
2. **What you receive** — the dispatch fields from this task's Interfaces block.
3. **One review, submitted once** — build the whole review and submit it as a single request so the reviewer gets one notification rather than one per comment. Give the exact commands.

   GitHub, via `gh api` with a JSON body built in a heredoc:

   ```sh
   gh api "repos/$REPO/pulls/$PR/reviews" \
     --method POST \
     --input - <<'JSON'
   {
     "commit_id": "<head_sha>",
     "event": "COMMENT",
     "body": "<summary markdown>",
     "comments": [
       { "path": "src/auth/token.js", "line": 31, "side": "RIGHT", "body": "**guardtower security-001** (93) …" }
     ]
   }
   JSON
   ```

   GitLab, one discussion per inline comment plus one note for the summary:

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

   glab mr note "$MR" --message "<summary markdown>"
   ```

4. **Routing** — `in_diff: true` becomes an inline comment at `target_file`:`target_line`; `in_diff: false` becomes a line in the one summary comment. Explain the constraint rather than treating it as a bug: GitHub and GitLab only accept an inline comment on a line present in the diff, so a finding whose evidence sits in untouched code — common for reuse findings, where the duplicated original is not part of the change — cannot be anchored inline. Relocating it to the summary is correct; relocating it *silently* is not, so the return names which findings were moved and why.
5. **Comment body format** — `**guardtower <id>** (<composite>) — <claim>`, then the rationale, then the proposal, then an `Also at: <also_at, comma-joined>` line, then a `value <n> · urgency <n>` footer so a reader can see how it scored. For reuse findings add a line naming `existing_solution`, and for tier 2 a line naming `adoption_cost`. The Also at line appears only when `also_at` is non-empty — omit it entirely for a single-location finding, and never omit it when it is populated, since an abstraction finding usually spans several files and `target_file`/`target_line` names only the clearest of them.
6. **Summary comment structure** — a `## guardtower` heading, the run id, the lenses run and any lenses skipped, then findings grouped by lens with their file:line. Where a lens was skipped, say so — a short comment must never read as a clean bill of health.
7. **Failure handling** — if the API call fails, report the failure with the response body and stop. Do not retry with a reduced payload, and do not fall back to posting a plain comment when an inline one was intended; both quietly change what the user approved.
8. **Return format** — `{ posted_inline, posted_summary, review_url }`.
9. **Red flags — STOP** — posting anything not in `approved`; posting one comment per finding instead of one review; silently relocating an inline comment to the summary without saying so; retrying with a reduced payload after a failure; writing any file in the repository; using `jq`.

- [ ] **Step 4: Run test to verify it passes**

Run: `sh guardtower/tests/validate.sh`
Expected: PASS — all checks `ok`, exit status `0`.

- [ ] **Step 5: Commit**

```bash
git add guardtower/skills/posting-review-comments guardtower/tests/validate.sh
git commit -m "feat(guardtower): forge poster for GitHub and GitLab"
```

---

## Task 10: The command, and the end-to-end behavioural test

The last task wires the entry point and proves an installed instance behaves — the check no amount of file inspection can make.

**Files:**
- Create: `guardtower/commands/review.md`
- Modify: `guardtower/tests/validate.sh`

**Interfaces:**
- Consumes: every skill from Tasks 3–9.
- Produces: `/guardtower:review <url|number>`.

- [ ] **Step 1: Write the failing test**

Append to `guardtower/tests/validate.sh`, before the final `printf` block:

```sh
# --- command ----------------------------------------------------------------

CMD="$PLUGIN/commands/review.md"
[ -s "$CMD" ]; check $? "commands/review.md exists"

if [ -s "$CMD" ]; then
  head -1 "$CMD" | grep -q '^---$'
  check $? "command: frontmatter opens on line 1"
  grep -q '^description: ' "$CMD"
  check $? "command: frontmatter has a description"
  grep -q 'reviewing-a-pull-request' "$CMD"
  check $? "command: invokes the conductor skill"
fi

# --- the expected skill set, exactly ---------------------------------------

expected="arbitrating-findings detecting-code-smell posting-review-comments reviewing-a-pull-request reviewing-for-security simplifying-through-abstraction surveying-for-reuse"
actual=$(ls "$PLUGIN/skills" | sort | tr '\n' ' ' | sed 's/ $//')
[ "$actual" = "$expected" ]; check $? "skill set is exactly the seven planned skills"
```

Then create `guardtower/tests/e2e.sh` — the behavioural test, kept separate because it installs the plugin and runs a real session:

```sh
#!/bin/sh
# End-to-end: install guardtower at local scope in a scratch repo and prove
# the command refuses to run where it cannot. Posts nothing, touches no PR.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
fail=0
cleanup() {
  cd "$TMP/proj" 2>/dev/null && {
    claude plugin uninstall guardtower@dashworthy --scope local >/dev/null 2>&1
    claude plugin marketplace remove dashworthy >/dev/null 2>&1
  }
  cd / && rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$TMP/proj" && cd "$TMP/proj" && git init -q
git config user.email t@example.com && git config user.name t
echo hello > a.txt && git add a.txt && git commit -qm init

claude plugin marketplace add "$ROOT" --scope local >/dev/null 2>&1
claude plugin install guardtower@dashworthy --scope local >/dev/null 2>&1

# 1. The command must be discoverable.
claude -p "List the slash commands available from the guardtower plugin. Names only." \
  --model claude-haiku-4-5-20251001 2>&1 | grep -q 'review' \
  && printf 'ok   - command is discoverable after install\n' \
  || { printf 'FAIL - command is discoverable after install\n'; fail=1; }

# 2. With no forge remote, the run must stop at forge detection and post nothing.
out=$(claude -p "/guardtower:review 1" --model claude-haiku-4-5-20251001 2>&1)
printf '%s' "$out" | grep -qiE "remote|forge|origin|no (github|gitlab)" \
  && printf 'ok   - stops cleanly with no forge remote\n' \
  || { printf 'FAIL - stops cleanly with no forge remote\n'; printf '%s\n' "$out"; fail=1; }

# 3. It must not have created artifacts on a run that never started.
[ ! -d "$TMP/proj/.guardtower" ] \
  && printf 'ok   - no artifacts written on a refused run\n' \
  || { printf 'FAIL - no artifacts written on a refused run\n'; fail=1; }

# 4. It must not have left a worktree behind.
[ -z "$(git worktree list | tail -n +2)" ] \
  && printf 'ok   - no worktree left behind\n' \
  || { printf 'FAIL - no worktree left behind\n'; fail=1; }

exit "$fail"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh guardtower/tests/validate.sh`
Expected: FAIL on `commands/review.md exists` and the three command frontmatter checks; exit status `1`.

- [ ] **Step 3: Write minimal implementation**

Create `guardtower/commands/review.md`:

```markdown
---
description: Review a GitHub pull request or GitLab merge request — four analysts, an arbitrator, and comments posted only after you approve them
---

Review the pull request or merge request identified by `$ARGUMENTS`.

`$ARGUMENTS` is either a number (`482`) or a full URL
(`https://github.com/org/repo/pull/482`,
`https://gitlab.com/org/repo/-/merge_requests/17`). A number resolves against the
`origin` remote of the current repository.

If `$ARGUMENTS` is empty, stop and say that guardtower requires a PR or MR
reference — it has no local-diff mode — then show both accepted forms above.

Otherwise invoke the `reviewing-a-pull-request` skill with that reference and
follow it exactly. Do not review the working tree, do not switch branches, and do
not post anything the user has not marked in scope.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `sh guardtower/tests/validate.sh`
Expected: PASS — every check `ok`, exit status `0`.

- [ ] **Step 5: Run the end-to-end test**

Run: `sh guardtower/tests/e2e.sh`
Expected: four `ok` lines, exit status `0`. If check 2 fails, read the printed session output: the usual cause is the conductor attempting forge detection before confirming a remote exists.

- [ ] **Step 6: Commit**

```bash
git add guardtower/commands guardtower/tests
git commit -m "feat(guardtower): review command and end-to-end behavioural test"
```

---

## Task 11: Freeze the plugin

**Files:**
- Modify: `.claude/settings.json`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: a complete plugin.
- Produces: nothing further depends on this.

- [ ] **Step 1: Write the failing test**

Append to `guardtower/tests/validate.sh`, before the final `printf` block:

```sh
# --- the finished plugin is frozen, as signal and verity are ----------------

python3 - "$ROOT/.claude/settings.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
deny=set(d["permissions"]["deny"])
need={"Edit(./guardtower/**)","Write(./guardtower/**)"}
missing=need-deny
assert not missing, f"settings.json deny list missing: {sorted(missing)}"
PY
check $? "guardtower is frozen in .claude/settings.json"

grep -q '^\.guardtower/$' "$ROOT/.gitignore"
check $? ".guardtower/ run artifacts are gitignored"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `sh guardtower/tests/validate.sh`
Expected: FAIL on both new checks; exit status `1`.

- [ ] **Step 3: Write minimal implementation**

In `.claude/settings.json`, extend the `permissions.deny` array to:

```json
    "deny": [
      "Edit(./signal/**)",
      "Edit(./verity/**)",
      "Edit(./guardtower/**)",
      "Write(./signal/**)",
      "Write(./verity/**)",
      "Write(./guardtower/**)"
    ]
```

In `.gitignore`, add `.guardtower/` beside the existing `.signal/` entry — run artifacts are per-run scratch, not source.

- [ ] **Step 4: Run test to verify it passes**

Run: `sh guardtower/tests/validate.sh`
Expected: PASS — every check `ok`, exit status `0`.

Then confirm the freeze is real by attempting an edit inside `guardtower/`; it must be denied.

- [ ] **Step 5: Commit**

```bash
git add .claude/settings.json .gitignore guardtower/tests/validate.sh
git commit -m "chore(guardtower): freeze the plugin directory and ignore run artifacts"
```

---

## Self-Review

**1. Spec coverage.**

| Spec section | Task |
|---|---|
| What it is; the two rules | 1 (README), 3 (conductor) |
| How a run flows (diagram) | 1 (README) |
| The worktree | 3 |
| Skills table | 3–9 |
| Preflight, run id | 3 |
| The pass; context firewall | 3 (dispatch + receipt), 8 (arbitrator reads the files) |
| Reconciliation | 3 |
| Findings (field table) | 2 |
| The reuse lens | 4 |
| Scoring (rubric, anchor, tie-break) | 2, applied in 8 |
| Triage and posting | 3 (triage), 9 (posting) |
| Disk layout | 3 |
| Repository layout | 1–10 |
| Prerequisites | 1 (README), 3 (preflight CLI check) |
| Where it sits next to verity | 1 (README) |
| Appendix — why there is no hook | 1 (README), asserted by the no-`hooks/` check in Task 1 |
| Post-build follow-ups | 11 |
| Explicit non-goals | 1 (README), enforced by checks in 1 and 9 |

No gaps.

**2. Placeholder scan.** No `TBD`, no "similar to Task N", no "add appropriate error handling". Every skill task enumerates its required sections and names the spec section to copy verbatim where the spec is the authority. Every shell and JSON block is complete and runnable as written.

**3. Type consistency.** Checked across tasks: lens names are `reuse`/`security`/`smell`/`abstraction` everywhere (Global Constraints, Task 2 schema, Task 3 dispatch brief, Task 10 skill-set check); the finding field list in Task 2's JSON matches the validator's field loop in Task 2 Step 1 and the spec's table exactly; `output_path` is the name used in the dispatch brief (Task 3) and in all four analysts' return rules (Tasks 4–7) and their red-flag lists; `passed`/`dropped`/`discarded` are used identically in Task 8's return shape, its body section 8, and its validator check; `in_diff` is set by analysts (Task 2), consumed by the poster (Task 9), and checked in both; `composite`/`value`/`urgency` are arbitrator-owned in Tasks 2, 4–8.

**4. The plan's own test code.** The validator is built by appending across ten tasks, so it was checked as one concatenated script rather than block by block. Three defects found and fixed inline:

- `$CONDUCTOR` was used by Task 2's block but assigned only in Task 3's — every Task 2 reference would have expanded to an empty string and silently checked the wrong path. The assignment now lives in Task 2, where it is first needed, and Task 3 reuses it.
- Task 9's `grep -qi 'single review'` had no file argument, so on the fallback branch it would have read stdin and hung the validator rather than failing it. Now takes `"$P"`.
- The `jq` check used `\b`, a GNU extension. Replaced with `grep -w`, which is portable and does the same job on the BSD grep macOS ships.

The first two would have produced a validator that passes while checking nothing — the exact false green this plugin exists to prevent, in its own test harness.

---

Plan complete and saved to `docs/superpowers/plans/2026-07-29-guardtower.md`. Two execution options:

**1. Subagent-Driven (recommended)** — a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
