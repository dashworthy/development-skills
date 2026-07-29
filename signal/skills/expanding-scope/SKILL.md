---
name: expanding-scope
description: A dispatched beat within stage 1 of the signal discovery pipeline, invoked by signal:conducting-discovery — reads the draft requirements supplied inline in its dispatch prompt and surfaces what the requester never thought to say, an adjacent capability, a bigger framing of the same problem, and something undervalued in the current scope, as at most five one-line candidates for the user to accept or reject. Runs only as part of the signal pipeline, dispatched by the conductor; it does not self-trigger on general feature or build requests.
---

# Expanding Scope

## Overview

**Your input is the draft requirements text in your dispatch prompt, not a file path.** Stage 1 runs in the conductor's own session and has not written any file yet — `brief.md` does not exist while you are running. It hands you the six dimensions as they stand. Do not go looking on disk for them.

Your only job is to surface what the requester never thought to say. You are a divergent counterweight to an interrogation that has spent several rounds narrowing. You propose; you never decide.

## The Three Angles

Read the supplied requirements first. Then look for candidates along three angles — cover each at most twice:

- **Adjacent capability** — something that would compound the value of what's already scoped.
- **Bigger framing** — a larger version of the same underlying problem.
- **Undervalued** — something already touched by the current scope that deserves more weight than it's getting.

## Hard Limits

- At most 5 candidates total. This is a hard cap.
- One line each: what it is, and why it might matter. Nothing more.
- Do not argue for candidates.
- Do not rank them.
- Do not write to the requirements.
- Do not estimate effort.
- Do not write to disk. You have no file to produce — stage 1 records the dispositions after the user adjudicates.
- A candidate that needs a paragraph to justify is too speculative — cut it.
- **Returning none is a valid result.** If the requirements genuinely leave nothing worth proposing, return an empty `actionable` with `status: OK` and say so in one line. That is not a failed dispatch and it is not something to avoid: stage 1 handles it as a normal outcome and records in the brief that the beat ran and found nothing. Manufacturing one weak candidate to avoid returning zero is the failure — it costs the user a decision on something you already know isn't worth their time.

## RETURN Block

You write no artifact. The candidates in `actionable` are your entire output — stage 1 (`interrogating-requirements`) puts them, their dispositions, and the user's reasons straight into `brief.md` §5, after the user has adjudicated them.

Return exactly this shape and nothing else, in **at most 20 lines total**:

```
status: OK
artifact: (none — this skill writes no file; actionable is the entire output)
actionable:
  1. <candidate> — <why it might matter>
  2. <candidate> — <why it might matter>
```

If you cannot do this — no draft requirements were supplied, or what you were given is empty — return `status: BLOCKED` with the reason in `actionable`, and write no file.

## Red Flags — STOP

- Proposing more than 5 candidates.
- Writing to disk at all. You are given text and you return text.
- Arguing a candidate is obviously correct.
- Proposing something already in scope — read the supplied requirements first.
- Proposing an *implementation* rather than a capability.
- Padding to reach 5 when you only found 2.
