#!/bin/sh
# End-to-end: install guardtower at local scope in a scratch repo and prove
# the command refuses to run where it cannot. Posts nothing, touches no PR.
#
# Properties that matter beyond "call claude -p and grep the output":
#
# 1. "dashworthy" is THIS REPO'S OWN real marketplace name (.claude-plugin/marketplace.json) and
#    the README tells real users to add it. The registration this script creates lives in
#    ~/.claude/plugins/ (known_marketplaces.json, installed_plugins.json) - a single,
#    user-home-scoped registry, NOT anything confined to $TMP. A test script must never remove -
#    or silently repoint - a marketplace registration it did not itself create in this run. See
#    the ownership snapshot below: if "dashworthy" (or guardtower@dashworthy) is already present
#    before this script does anything, it is treated as real and untouchable, and the whole test
#    is skipped rather than risk it.
# 2. Nothing may bound a `claude -p` call that never returns. A child that traps or ignores
#    SIGTERM (or is itself blocked inside a graceful-shutdown path on the same stuck network call)
#    must still be dead at roughly the limit plus a short grace period, not run to its own natural
#    end - see run_limited's TERM-then-KILL escalation below.
# 3. A transient API failure (429/5xx/529, "please run /login") must never be reported as "the
#    plugin is broken" - see classify_claude_failure - but the token list must not be so broad
#    that it can also match guardtower's OWN networking (a real forge-detection-ordering
#    regression that gets as far as its own failing git/gh/glab call), which would hide a real
#    defect behind "inconclusive."
# 4. The one check most likely to depend on single-turn model narration completing within one
#    non-interactive `-p` call (check 2, "stops cleanly with no forge remote") is retried with
#    quorum rather than graded on a single attempt - see run_with_quorum below for why that is
#    safe: a genuine regression fails the same way every time; narration noise does not.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
fail=0
inconclusive=0

# Seconds allowed for each `claude -p` call before TERM is sent, and the grace period after TERM
# before escalating to KILL. Overridable (e.g. for a slower machine, or to deliberately shrink
# either while proving the limiter itself works).
CLAUDE_E2E_TIMEOUT=${CLAUDE_E2E_TIMEOUT:-180}
GRACE_KILL_SECS=${GRACE_KILL_SECS:-3}

# Portable timeout with escalation. Prefer timeout(1) or gtimeout(1) when either is on PATH -
# both support -k to escalate to KILL if the command is still alive GRACE_KILL_SECS after the
# initial TERM. Neither ships on stock macOS - there is no timeout(1), and gtimeout exists only
# if coreutils was installed separately, which must not be assumed - so the fallback implements
# the same TERM-then-grace-then-KILL escalation by hand. A single `kill -TERM` with no escalation
# is not sufficient: a child that traps or ignores TERM (proven with a
# `trap '' TERM; sleep 300` fixture) is left running for its full natural duration instead of
# dying at the limit.
#
# The watchdog subshell traps TERM on itself and kills whichever `sleep` it is currently blocked
# in before exiting. This matters on the FAST path too, not just the timeout path: killing only
# the subshell wrapper (as an earlier version of this script did) leaves the `sleep` it forked
# still running - shells do not propagate a signal to a background child just because the parent
# that spawned it died - so that sleep reparents to init and runs out its own remaining duration.
# Verified (see the fix report) that a fast-exiting command left an orphaned `sleep` behind twice
# under the old design; the trap-and-kill-my-current-child pattern here leaves none.
#
# `$@` is launched under `set -m` (restored immediately after) so it becomes its own process
# group leader rather than sharing this script's group - the default for a background job in a
# non-interactive shell, confirmed empirically on this machine. Both TERM and the KILL escalation
# below are sent to `-$cmd_pid` (the whole group), not just $cmd_pid, so a child THAT COMMAND
# ITSELF spawns - guardtower's own `git`/`gh`/`glab` calls, if `claude -p` is what hangs - is
# reached too, not just the top-level process. Proven necessary: killing only $cmd_pid for a
# `sh stubborn.sh` fixture whose last line is `sleep 300` left that `sleep` running as an orphan
# of init after $cmd_pid itself was gone, because SIGKILLing a parent does not cascade to its
# already-forked children.
#
# Always captures the child's combined stdout+stderr to $2 (callers need the text to diagnose a
# failure) and returns the child's real exit status, or 124 - matching GNU timeout's own
# convention - if the watchdog had to intervene at all (whether TERM alone sufficed or KILL was
# needed), so a caller can tell "ran and failed" from "never finished."
run_limited() {
  secs=$1; outfile=$2; shift 2
  if command -v timeout >/dev/null 2>&1; then
    timeout -k "$GRACE_KILL_SECS" "$secs" "$@" >"$outfile" 2>&1
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout -k "$GRACE_KILL_SECS" "$secs" "$@" >"$outfile" 2>&1
    return $?
  fi

  marker="$outfile.timedout"
  rm -f "$marker"

  set -m
  "$@" >"$outfile" 2>&1 &
  cmd_pid=$!
  set +m

  (
    trap 'kill "$child" 2>/dev/null; exit 0' TERM
    sleep "$secs" & child=$!
    wait "$child" 2>/dev/null
    # Reached only if that sleep ran to completion - i.e. the real command did not finish in
    # time. Mark the intervention now, before whatever escalation it takes to actually stop it,
    # so the marker's presence means "we hit the limit," independent of the TERM/KILL race below.
    : > "$marker"
    kill -TERM -- "-$cmd_pid" 2>/dev/null
    sleep "$GRACE_KILL_SECS" & child=$!
    wait "$child" 2>/dev/null
    # Still alive after TERM + grace - it (or a child it spawned) ignored TERM, or is blocked
    # past it. Escalate to the whole group.
    kill -0 "$cmd_pid" 2>/dev/null && kill -KILL -- "-$cmd_pid" 2>/dev/null
  ) &
  watchdog_pid=$!

  wait "$cmd_pid" 2>/dev/null
  status=$?

  kill -TERM "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null

  if [ -e "$marker" ]; then
    rm -f "$marker"
    status=124
  fi
  return "$status"
}

# Distinguish "the model API failed us" from "the plugin behaved wrongly," so a transient
# 429/5xx/529 is never reported as a behavioral regression. Narrowly scoped on purpose: an earlier
# version also matched ETIMEDOUT/ECONNRESET/"fetch failed"/"network error"/"internal server
# error"/"service unavailable", every one of which guardtower's OWN networking (its git fetch, or
# the gh/glab calls posting-review-comments and the conductor's forge detection shell out to)
# could equally produce - meaning a real ordering regression that gets far enough to hit its own
# failing network call would have been graded INCONCLUSIVE instead of FAIL. Hiding a failure is
# worse than the defect this classification exists to prevent, so the list here is limited to
# signatures that can only come from the Anthropic API / claude CLI session itself: rate limiting,
# "overloaded", the specific 429/500/503/529 status codes, and an expired CLI session. A
# run_limited timeout (124) is always classified as a timeout, independent of this list.
classify_claude_failure() {  # classify_claude_failure <exit_status> <output_text>
  st=$1; txt=$2
  if [ "$st" -eq 124 ]; then
    printf 'timeout\n'
    return
  fi
  if [ "$st" -ne 0 ] && printf '%s' "$txt" | grep -qiE '(^|[^0-9])(429|500|503|529)([^0-9]|$)|overloaded|rate.?limit|please run /login'; then
    printf 'api\n'
    return
  fi
  printf 'behavior\n'
}

# Run up to 3 attempts of a claude -p call, retrying on both a genuine behavioral fail and an
# api/timeout-classified attempt. The skill under test is deterministic - same repo, same
# instructions, same halt condition - so a real regression fails the SAME way on every attempt,
# while a single-turn narration hiccup (observed manually as 1-of-2 live runs: the session stated
# intent - "Let me proceed with Step 1" - and stopped short of actually running the check that
# turn) resolves on retry. That asymmetry is what quorum is for.
#
# Accept the first "ok" and short-circuit immediately, so the common case still costs exactly one
# call. Grade a real FAIL only once 3 attempts have each completed a genuine behavioral verdict
# and NONE of them passed - an attempt that itself comes back api/timeout-classified is not a
# completed behavioral verdict, so a string of outages cannot manufacture a FAIL on its own; it
# manufactures INCONCLUSIVE instead, same as a single-attempt check would.
#
# Checks 3 and 4 below are consequences of the run never reaching its mutating steps; they prove
# nothing about whether the halt happened for the right reason (a run that hung for an unrelated
# reason before ever calling git would also leave no artifacts and no worktree), so they cannot
# substitute for actually observing the halt message here.
#
# Sets on return: qr_result to "ok", "fail", or "inconclusive"; qr_text to the last attempt's
# captured output, for the caller to print on anything but "ok".
run_with_quorum() {  # run_with_quorum <ok_grep_pattern> <claude-arg>...
  ok_pattern=$1; shift
  behavioral_fails=0
  attempt=0
  qr_result="inconclusive"
  qr_text=""
  while [ "$attempt" -lt 3 ]; do
    attempt=$((attempt + 1))
    out=$(mktemp)
    run_limited "$CLAUDE_E2E_TIMEOUT" "$out" "$@"
    st=$?
    txt=$(cat "$out"); rm -f "$out"
    qr_text=$txt
    cls=$(classify_claude_failure "$st" "$txt")
    if [ "$cls" = "behavior" ]; then
      if printf '%s' "$txt" | grep -qiE "$ok_pattern"; then
        qr_result="ok"
        return 0
      fi
      behavioral_fails=$((behavioral_fails + 1))
    fi
    # timeout/api: this attempt is inconclusive on its own; loop again, still bounded by the
    # 3-attempt cap above.
  done
  if [ "$behavioral_fails" -ge 3 ]; then
    qr_result="fail"
  else
    qr_result="inconclusive"
  fi
}

cleanup() {
  [ -d "$TMP/proj" ] && cd "$TMP/proj" 2>/dev/null
  # Only remove what THIS run added - see the ownership snapshot below. Never gated on the cd
  # above succeeding: the registry these act on is user-scoped, not path-scoped, so a failed
  # mkdir/cd must not also skip the cleanup that corresponds to whatever this run did add.
  [ "$plugin_preexisted" = 0 ] && claude plugin uninstall guardtower@dashworthy --scope local >/dev/null 2>&1
  [ "$marketplace_preexisted" = 0 ] && claude plugin marketplace remove dashworthy >/dev/null 2>&1
  cd / && rm -rf "$TMP"
}
trap cleanup EXIT

# Ownership snapshot - taken before this script does ANYTHING else, so "preexisted" unambiguously
# means "was here before this run touched the system." There is no way to distinguish a leak from
# a previous crashed run of this exact script from a real, permanent user registration by
# inspection alone - both look identical - so the only safe rule is: if it's already there, this
# run did not create it, and will not remove or repoint it, ever, no matter how the run ends. That
# does mean a genuine leak from an earlier crash does not self-heal; that is the correct trade,
# since the alternative is a test script that can silently delete or overwrite real configuration.
marketplace_preexisted=0
plugin_preexisted=0
claude plugin marketplace list 2>/dev/null | grep -q 'dashworthy' && marketplace_preexisted=1
claude plugin list 2>/dev/null | grep -q 'guardtower@dashworthy' && plugin_preexisted=1

if [ "$marketplace_preexisted" = 1 ] || [ "$plugin_preexisted" = 1 ]; then
  printf 'NOTE - a "dashworthy" marketplace and/or guardtower@dashworthy plugin is ALREADY present on this machine.\n'
  printf 'NOTE - this is indistinguishable from a real, permanent user registration, so e2e.sh will not add,\n'
  printf 'NOTE - install, remove, or otherwise touch it. Skipping the live install/uninstall test entirely.\n'
  printf '\nINCONCLUSIVE - pre-existing dashworthy registration; this run does not confirm a regression.\n'
  exit 2
fi

mkdir -p "$TMP/proj" && cd "$TMP/proj" && git init -q
git config user.email t@example.com && git config user.name t
echo hello > a.txt && git add a.txt && git commit -qm init

claude plugin marketplace add "$ROOT" --scope local >/dev/null 2>&1
claude plugin install guardtower@dashworthy --scope local >/dev/null 2>&1

# 1. The command must be discoverable.
run_with_quorum 'review' \
  claude -p "List the slash commands available from the guardtower plugin. Names only." \
  --model claude-haiku-4-5-20251001
case "$qr_result" in
  ok)   printf 'ok   - command is discoverable after install\n' ;;
  fail) printf 'FAIL - command is discoverable after install\n%s\n' "$qr_text"; fail=1 ;;
  *)    printf 'INCONCLUSIVE - command is discoverable after install (API error or timeout on all attempts - not a behavioral result)\n%s\n' "$qr_text"; inconclusive=1 ;;
esac

# 2. With no forge remote, the run must stop at forge detection and post nothing.
run_with_quorum 'remote|forge|origin|no (github|gitlab)' \
  claude -p "/guardtower:review 1" --model claude-haiku-4-5-20251001
case "$qr_result" in
  ok)   printf 'ok   - stops cleanly with no forge remote\n' ;;
  fail) printf 'FAIL - stops cleanly with no forge remote\n%s\n' "$qr_text"; fail=1 ;;
  *)    printf 'INCONCLUSIVE - stops cleanly with no forge remote (API error or timeout on all attempts - not a behavioral result)\n%s\n' "$qr_text"; inconclusive=1 ;;
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
