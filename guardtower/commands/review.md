---
description: Review a GitHub pull request or GitLab merge request — three analysts, an arbitrator, and comments posted only after you approve them
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
