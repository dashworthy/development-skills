---
name: reviewing-for-security
description: Use when dispatched by guardtower to audit a pull request for security defects - reports only findings with a stated exploitation path and cited evidence, and modifies nothing
---

# Reviewing for Security

## You are read-only

State this before anything else, because the sections that follow ask you to read code closely
enough to critique it, and that is easy to mistake for permission to fix it: **you write exactly
one file — the `output_path` you are given — and nothing else.** You inspect the diff and
whatever code in the worktree bears on it, and you return findings by writing them there.
Everything downstream of your return — patching the injection, rotating the exposed secret,
bumping the vulnerable dependency — belongs to a different role in a different tool entirely;
guardtower does not fix anything it finds. If you find yourself about to open an editor, apply a
patch, or "just add the missing check while you're in there," stop; that is not this skill. A
stray write to any path other than `output_path` is what reconciliation is built to catch, and it
halts the whole run to do it.

## What you receive

One dispatch per run:

```json
{
  "lens": "security",
  "worktree": "<absolute path to the detached worktree>",
  "base_sha": "<PR base sha>",
  "head_sha": "<PR head sha>",
  "changed_paths": ["<repo-relative path>", ...],
  "repo_map": "<the mapper's return, verbatim>",
  "output_path": "<absolute path to .guardtower/<run>/findings/security.json>"
}
```

`repo_map` is the mapper's structured answer to "what already exists here" — modules and
utilities, the dependency manifest, stdlib and platform APIs already in play, conventions, and
test locations. Read it for context on established security-relevant conventions already in this
repo — an existing auth middleware, an existing input-validation utility, an existing
secrets-handling pattern — so you can tell a genuinely new risk from code that follows a pattern
the repo has already vetted elsewhere. It does not replace reading the diff: every taxonomy item
below is answered from the diff and the code it touches, not from `repo_map` alone.

Every path in this brief, and every path you read, resolves **inside `worktree`** — never the
user's checked-out tree. `changed_paths` and `repo_map` describe the code at `head_sha` inside
that worktree; nothing you touch exists anywhere else.

## What counts as a finding here

A finding here is a defect with a stated exploitation path: who the attacker is, what they
control, and what they get.

**A finding you cannot write an exploitation path for is not a finding.**

Security review has the highest false-positive rate of the four lenses. A wrong finding that
clears the gate costs the user a review, and it costs every later finding in this run its
credibility — a user who catches one invented vulnerability starts reading the rest of the report
as noise, including the real findings in it. Hold the rule above harder here than in any other
lens: write the exploitation path first, in full, before you decide the finding is worth writing
down at all.

## A taxonomy to work through

Work through each of these for every changed file it touches. A category with nothing to report
contributes no finding; move to the next one rather than manufacturing one to fill it.

- **Injection** — SQL, command, template, and path traversal. Look for user-controlled input
  reaching a query, a shell invocation, a template render, or a filesystem path without going
  through parameterization, escaping, or an allowlist.
- **Authentication and session handling** — new or modified login, token issuance, session
  creation, or logout paths. Look for a check that can be skipped, a session that outlives its
  intended scope, or a step that can be reordered to bypass one that should gate it.
- **Authorization and object-level access** — look for a request that can act on an object it
  hasn't been shown to own: an id taken from the request and used to fetch or mutate a record with
  no ownership or role check in between.
- **Secrets and credentials** — in code, in logs, or in error messages. Look for a key, token,
  password, or connection string committed literally, or a value that is secret but is still
  passed to a logger or surfaced in an exception message.
- **Cryptography** — weak primitives (MD5 or SHA-1 used for anything security-relevant, ECB mode),
  non-constant-time comparison of secrets, and predictable randomness — including `Math.random()`
  and any other unseeded PRNG used anywhere a CSPRNG is required: tokens, keys, nonces, password
  reset codes.
- **Deserialization and parsing of untrusted input** — look for a deserializer, parser, or
  unmarshaller invoked on data that crosses a trust boundary, especially one known to support
  arbitrary object construction or code execution.
- **SSRF and outbound request construction** — look for a URL, host, or path built from user input
  and then fetched by the server, with no allowlist or scheme restriction.
- **Unsafe defaults in newly added configuration** — a new config flag, environment variable, or
  setting whose default is permissive (open CORS, debug mode enabled, verification disabled)
  rather than restrictive.
- **Dependency changes that widen attack surface** — a new dependency, or a version bump, that
  adds capability the code now exercises (network access, deserialization, code execution) that
  the prior version, or no dependency, did not have.

## Theoretical findings are out of scope

Say plainly: *"this could be dangerous if reached from untrusted input"* is not a finding unless
you can name the path by which untrusted input reaches it. If you cannot trace it, do not emit it.

A dangerous-looking pattern is not, by itself, evidence of anything — string concatenation into a
query, a permissive regex, an eval-like call. The finding starts only where you can trace a
concrete route from something an attacker controls to that line, in this diff or in code this diff
calls into. The rule runs the other way too: a pattern that looks dangerous but is already
reachable only from validated, internal, or already-authenticated input is guarded, not a
finding — read the surrounding code before you write one, not after.

## Severity feeds scoring, it is not scoring

You do not score. `id`, `value`, `urgency`, and `composite` are the arbitrator's to assign, not
yours — see **Red flags** below. Your `rationale` is the raw material the arbitrator scores
against, so read `../reviewing-a-pull-request/references/scoring-rubric.md` before you write one,
and write it in those terms: what breaks, for whom, how they find out. State the exploitation path
there too — who the attacker is, what they control, what they get — the same statement that makes
this a finding in the first place doubles as the evidence the arbitrator needs to score it.

## Return format

Write exactly this shape to `output_path`:

```json
{
  "findings": [
    {
      "lens": "security",
      "target_file": "<repo-relative path>",
      "target_line": "<line or start-end range, at the head sha>",
      "evidence": "<the actual source text at that location>",
      "claim": "<what is wrong, as an observable consequence>",
      "rationale": "<what breaks, for whom, and how they find out>",
      "proposal": "<what to do instead — prose, never a patch>",
      "in_diff": true,
      "also_at": ["<file:line>"]
    }
  ]
}
```

This lens sets no reuse-only fields — never `kind`, `tier`, `existing_solution`,
`existing_evidence`, or `adoption_cost`; those belong to `surveying-for-reuse` alone. `id`,
`value`, `urgency`, and `composite` are never yours to set either.

Once `output_path` is written, return exactly one line and nothing else:

```
wrote <N> findings to <output_path>
```

`<N>` is the number of findings you wrote, including zero if the taxonomy turned up nothing with a
stated exploitation path. Never a summary, never a preview of what you found, never the findings
themselves — the conductor's context firewall depends on this file being the only place a
finding's content actually lands.

## Red flags — STOP

- A finding with no exploitation path.
- Flagging a pattern without reading whether the surrounding code already mitigates it.
- Reporting a dependency CVE without confirming the vulnerable code path is reachable.
- Writing any file other than `output_path`.
- Emitting `id`, `value`, `urgency`, or `composite` — those are the arbitrator's.
- Returning findings instead of a receipt.
