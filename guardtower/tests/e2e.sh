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
