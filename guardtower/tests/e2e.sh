#!/bin/sh
# End-to-end: install guardtower at local scope in a scratch repo and prove
# the command refuses to run where it cannot. Posts nothing, touches no PR.
#
# Two properties matter beyond "call claude -p and grep the output":
#
# 1. The marketplace/plugin registration this script creates lives in
#    ~/.claude/plugins/ (known_marketplaces.json, installed_plugins.json) - a single,
#    user-home-scoped registry, NOT anything confined to $TMP. If cleanup never runs, the leak is
#    not a dangling reference to a deleted directory; it is a real, permanent registration the
#    user would see in `claude plugin marketplace list` from any project, forever.
# 2. Nothing bounds a `claude -p` call that never returns. Given this build has already lost
#    agents to 500/529 errors, an indefinite hang is a realistic occurrence, and a transient API
#    failure must never be reported as "the plugin is broken."

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
fail=0
inconclusive=0

# Seconds allowed for each `claude -p` call before it is killed. Overridable (e.g. for a slower
# machine, or to deliberately shrink it while proving the limiter itself works).
CLAUDE_E2E_TIMEOUT=${CLAUDE_E2E_TIMEOUT:-180}

# Portable timeout. Prefer timeout(1) or gtimeout(1) when either is on PATH. Neither ships on
# stock macOS - there is no timeout(1), and gtimeout exists only if coreutils was installed
# separately, which must not be assumed - so the fallback backgrounds the command, backgrounds a
# sleep-then-kill watchdog, waits on the command, then reaps the watchdog. Always captures the
# child's combined stdout+stderr to $2 (callers need the text to diagnose a failure) and returns
# the child's real exit status, or 124 - matching GNU timeout's own convention - if the watchdog
# had to kill it, so a caller can tell "ran and failed" from "never finished."
run_limited() {
  secs=$1; outfile=$2; shift 2
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@" >"$outfile" 2>&1
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@" >"$outfile" 2>&1
    return $?
  fi
  marker="$outfile.timedout"
  rm -f "$marker"
  "$@" >"$outfile" 2>&1 &
  cmd_pid=$!
  ( sleep "$secs"; kill -TERM "$cmd_pid" 2>/dev/null && : > "$marker" ) &
  watchdog_pid=$!
  wait "$cmd_pid" 2>/dev/null
  status=$?
  kill "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  if [ -e "$marker" ]; then
    rm -f "$marker"
    status=124
  fi
  return "$status"
}

# Distinguish "the API/network failed us" from "the plugin behaved wrongly," so a transient
# 500/529 is never reported as a behavioral regression. A run_limited timeout (124) is always
# classified as a timeout; otherwise a non-zero exit paired with a known API-failure signature in
# the captured output is an API failure; anything else is a real behavioral result to grade.
classify_claude_failure() {  # classify_claude_failure <exit_status> <output_text>
  st=$1; txt=$2
  if [ "$st" -eq 124 ]; then
    printf 'timeout\n'
    return
  fi
  if [ "$st" -ne 0 ] && printf '%s' "$txt" | grep -qiE '(^|[^0-9])(500|502|503|529)([^0-9]|$)|overloaded|rate.?limit|internal server error|service unavailable|econnreset|etimedout|fetch failed|network error|api error'; then
    printf 'api\n'
    return
  fi
  printf 'behavior\n'
}

# Idempotent: safe to call whether or not anything is currently installed (an uninstall/remove
# against a name that was never installed just fails silently, which is fine - nothing here
# inspects that exit status). Used both as a pre-clean, so a leak from a previous crashed run is
# removed rather than compounded, and by cleanup() at exit.
preclean() {
  claude plugin uninstall guardtower@dashworthy --scope local >/dev/null 2>&1
  claude plugin marketplace remove dashworthy >/dev/null 2>&1
}

cleanup() {
  # preclean() acts on the user-scoped registry under ~/.claude/plugins/, not on anything inside
  # $TMP, so it runs unconditionally here - it is not gated on `cd "$TMP/proj"` succeeding. An
  # earlier version of this script guarded cleanup's uninstall/remove on that cd while the install
  # steps below carried no matching guard at all: a failed mkdir/cd would have run the install
  # from the original cwd while cleanup silently skipped removal, leaking the registration. cd is
  # still attempted, best-effort, in case some CLI version resolves --scope local partly against
  # the invoking directory - but preclean() itself does not depend on it.
  [ -d "$TMP/proj" ] && cd "$TMP/proj" 2>/dev/null
  preclean
  cd / && rm -rf "$TMP"
}
trap cleanup EXIT

# Defensive pre-clean: if a previous run of this script crashed or was killed before its own
# cleanup ran, remove that leak now rather than installing on top of it.
preclean

mkdir -p "$TMP/proj" && cd "$TMP/proj" && git init -q
git config user.email t@example.com && git config user.name t
echo hello > a.txt && git add a.txt && git commit -qm init

claude plugin marketplace add "$ROOT" --scope local >/dev/null 2>&1
claude plugin install guardtower@dashworthy --scope local >/dev/null 2>&1

# 1. The command must be discoverable.
out1=$(mktemp)
run_limited "$CLAUDE_E2E_TIMEOUT" "$out1" \
  claude -p "List the slash commands available from the guardtower plugin. Names only." \
  --model claude-haiku-4-5-20251001
status1=$?
text1=$(cat "$out1"); rm -f "$out1"
case $(classify_claude_failure "$status1" "$text1") in
  timeout)
    printf 'INCONCLUSIVE - command is discoverable after install (timed out after %ss - not a behavioral result)\n' "$CLAUDE_E2E_TIMEOUT"
    inconclusive=1
    ;;
  api)
    printf 'INCONCLUSIVE - command is discoverable after install (API error - not a behavioral result)\n%s\n' "$text1"
    inconclusive=1
    ;;
  *)
    printf '%s' "$text1" | grep -q 'review' \
      && printf 'ok   - command is discoverable after install\n' \
      || { printf 'FAIL - command is discoverable after install\n%s\n' "$text1"; fail=1; }
    ;;
esac

# 2. With no forge remote, the run must stop at forge detection and post nothing.
out2=$(mktemp)
run_limited "$CLAUDE_E2E_TIMEOUT" "$out2" \
  claude -p "/guardtower:review 1" --model claude-haiku-4-5-20251001
status2=$?
text2=$(cat "$out2"); rm -f "$out2"
case $(classify_claude_failure "$status2" "$text2") in
  timeout)
    printf 'INCONCLUSIVE - stops cleanly with no forge remote (timed out after %ss - not a behavioral result)\n' "$CLAUDE_E2E_TIMEOUT"
    inconclusive=1
    ;;
  api)
    printf 'INCONCLUSIVE - stops cleanly with no forge remote (API error - not a behavioral result)\n%s\n' "$text2"
    inconclusive=1
    ;;
  *)
    printf '%s' "$text2" | grep -qiE "remote|forge|origin|no (github|gitlab)" \
      && printf 'ok   - stops cleanly with no forge remote\n' \
      || { printf 'FAIL - stops cleanly with no forge remote\n'; printf '%s\n' "$text2"; fail=1; }
    ;;
esac

# 3. It must not have created artifacts on a run that never started.
[ ! -d "$TMP/proj/.guardtower" ] \
  && printf 'ok   - no artifacts written on a refused run\n' \
  || { printf 'FAIL - no artifacts written on a refused run\n'; fail=1; }

# 4. It must not have left a worktree behind.
[ -z "$(git worktree list | tail -n +2)" ] \
  && printf 'ok   - no worktree left behind\n' \
  || { printf 'FAIL - no worktree left behind\n'; fail=1; }

# A real behavioral failure (fail=1) always wins the exit code, even if some other check was also
# inconclusive - a definite failure is a stronger signal than "could not tell." Inconclusive alone
# (no real failure observed) exits 2, distinct from both a clean pass (0) and a real failure (1),
# so a caller - and a human reading the log - never mistakes "the API didn't answer" for "the
# plugin is broken."
if [ "$fail" -ne 0 ]; then
  exit 1
elif [ "$inconclusive" -ne 0 ]; then
  printf '\nINCONCLUSIVE - one or more checks could not reach a behavioral result (API error or timeout); this run does not confirm a regression.\n'
  exit 2
fi
exit 0
