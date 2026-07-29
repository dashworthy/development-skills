#!/bin/sh
# SessionStart hook for verity.
#
# Puts verity's trigger rule in front of the model at the start of every
# conversation, since nothing mechanically forces the conducting-test-hardening
# skill to run. Does not block, does not touch git, does not read or write
# any file, does not depend on jq.

message='Verity applies once implementation work is finished: before opening a PR, before merging, before declaring work done - including when the user says to wrap up.\nIt is most often skipped because passing tests get mistaken for proof nothing more is needed.\nAt that point, invoke the `conducting-test-hardening` skill.'

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$message"

exit 0
