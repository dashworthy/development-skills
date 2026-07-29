---
name: sequencing-requirements
description: Stage 2 of the signal discovery pipeline, invoked by signal:conducting-discovery once stage 1 has written sections 1 to 6 of brief.md with every expansion candidate adjudicated — appends section 7, the body of the work ordered by dependency (what must be understood or built before what, and why), and section 8, the handoff pointer. It appends only; it never edits stage 1's sections, does not split work into separable units, and does not design or build. Runs only as part of the signal pipeline, dispatched by the conductor; it does not self-trigger on general feature or build requests.
---

# Sequencing Requirements

## Overview

You are dispatched with one input: the path to `brief.md`. It already exists. Stage 1 wrote **§1–§6** into it — the requirements across all six coverage dimensions, with every expansion candidate the user adjudicated already placed: accepted ones written in as requirements, rejected ones in §5's non-goals with the user's reason.

**Your job is to append §7 and §8. That is all of it.** Read §1–§6 to understand the work; then write two new sections onto the end of the file. There is no separate requirements artifact, nothing to transcribe, and no restatement to author. You do not design a solution and you do not plan an implementation.

## The Two-Writer Boundary

`brief.md` has two writers and they do not overlap:

| Sections | Written by | You may |
|---|---|---|
| §1–§6 | stage 1, in the main thread, with the user in the room | **read only** |
| §7–§8 | you | write, and on a re-dispatch, replace |

**Never edit, re-word, reorder, condense, retitle or delete anything in §1–§6.** Not to improve the prose, not to fix a typo, not to make the voice consistent with yours, not to "tighten" a success criterion. Those sections are the record of an interrogation you were not present for, and the reader receives them as the user left them. The brief reading in two voices is expected and is not a defect.

If you believe a requirement section is genuinely wrong — §3 carries a criterion that cannot be measured, §4 contradicts §5, a section is empty — **that is a `BLOCKED` return with the reason**, not a fix. The conductor routes it back to the user, who is the only one who can answer it. Silently correcting it means the user never learns their requirements were contradictory, and the brief ships an answer nobody gave.

If you are re-dispatched against a brief that already carries a §7 and §8, replace your own two sections with fresh ones. Leave §1–§6 exactly as you found them — if they changed, stage 1 changed them with the user, before you were re-dispatched.

## You Are Not Decomposing Work

**You are ordering the body of one document. You are not splitting work into independently-buildable units.**

That distinction is easy to lose, because "sequence the work" sounds like the first step of breaking a feature into buildable pieces. It is not. Splitting work into separately-estimable, separately-buildable units serves a build loop that consumes them one at a time. **signal has no build loop.** It hands off one document and stops. There is nothing downstream for such units to feed, so producing them is work with no consumer — and it changes §7 from a description of the problem's shape into a plan of attack, which is a claim signal does not get to make.

Concretely, do not reach for any of this:

- deciding whether a component is "small enough" and recursing until it is
- an atomic / not-atomic flag on a component
- a cap on how many components there may be
- an iteration limit on repeated splitting

None of it applies. If you catch yourself asking "is this one small enough to build?" — stop. That is a question for whoever picks the brief up, and answering it here is designing, which is out of scope.

## The Eight Sections

The finished `brief.md` has eight top-level headings, in this order:

| § | Contents | Writer |
|---|---|---|
| 1 | **Problem** — the problem in one sentence, and who feels it today | stage 1 |
| 2 | **Users & Stakeholders** — who uses it, who's affected, who signs off | stage 1 |
| 3 | **Success Criteria** — measurable or observable only; no aspirational prose | stage 1 |
| 4 | **Constraints** — stack, timeline, budget, compliance, integrations, non-negotiables | stage 1 |
| 5 | **Scope** — what's in; and **non-goals**, each with the user's reason | stage 1 |
| 6 | **Existing Context** — prior art, current workarounds, systems this must fit into | stage 1 |
| 7 | **The Work, In Dependency Order** — the body of the brief | **you** |
| 8 | **How to Consume This Brief** — explicit handoff pointer | **you** |

The first six already exist when you are dispatched. Append yours with exactly these headings:

`## 7. The Work, In Dependency Order`, `## 8. How to Consume This Brief`.

**Note for §8:** state plainly that signal's job is finished and that this brief is the input to whatever builds — `superpowers:brainstorming` per component, a human, or another pipeline — named as candidate consumers, not as a chosen one. Make **no claim about what happens next**: no recommended next step, no proposed approach, no effort estimate, no "start with §7.1". §8 is a pointer, not a plan. It is the last thing a downstream reader sees, and the only section that tells them what this document is for.

## Section 7 — The Dependency-Ordered Body

§7 orders the work so that nothing appears before what it requires. It is ordered from §1–§6, and in particular from §5's in-scope list and §6's existing context — a component that already half-exists as a workaround is a different component from one built from nothing, and §6 is where you find that out.

Each component states five fields:

- **What it is** — one cohesive concern, named plainly.
- **Depends on** — which earlier components it needs, by name.
- **Why it follows** — what specifically it needs from its prerequisites, not just that it needs them.
- **Inputs / outputs** — its interface, stated in a sentence.
- **Open risks** — what is still uncertain about it.

## Ordering Rules

- **No forward references.** If a component needs something later in the order, the order is wrong — fix the order, don't note the exception.
- **No circular dependencies.** A cycle means the boundaries between components are drawn wrong. Redraw them, and say so in the affected components' open risks.
- **Genuinely independent components are stated as independent.** Do not impose a false order on two components that don't actually depend on each other just to produce a single linear list.

## RETURN Block

Return exactly this, in **at most 20 lines total**:

```
status: OK
artifact: <path to brief.md>
actionable: sections_1_6_lines: <n>
```

`sections_1_6_lines` is **the number of lines of §1–§6 as you found them, counted before you write anything.** Count it first, before touching the file.

On a first dispatch that is simply the whole file: stage 1 writes from line 1 and stops at §6, ending with one trailing newline and no blank line after it, so what you open is §1–§6 and nothing else. Count the file.

On a **re-dispatch** — a resumed run where the user asked for stage 2 to run again against a brief that already carries a §7 and §8 — the file is not just §1–§6, so counting all of it would report a number that includes sections you are about to replace. Count up to but not including the existing `## 7.` heading instead. (The conductor has no baseline to compare against on that path and will say the check is unavailable, but report the honest number regardless; a field that means different things on different runs is worse than one that is sometimes unused.)

Either way, count before you write, never after. Counting afterwards means locating your own `## 7.` and subtracting, which invites an off-by-one over exactly the boundary this check exists to protect.

Report the number honestly even if you suspect it will not match. A mismatch you disclose is a bug someone can find; one you paper over is a corrupted brief the user reads as their own words.

This is the conductor's only check on the two-writer boundary. It never reads the brief, so it cannot see whether you edited §1–§6 — but it wrote those sections and knows how many lines it wrote. If your count differs, it halts. The check is deliberately coarse: it catches insertions and deletions, not a re-wording that happens to preserve the line count. It is a tripwire, not a guarantee, and it is not a reason to relax the rule above.

If you cannot append §7 and §8 (contradictory requirements, a requirement section that is actually empty, `brief.md` missing, unreadable, or missing §1–§6), return `status: BLOCKED` with the reason in `actionable`, and append nothing. Leave the file exactly as you found it — a half-written §7 on disk is worse than none, because the conductor cannot tell it apart from a finished one.

## Red Flags — STOP

- **Editing, re-wording, reordering or deleting anything in §1–§6.** You append. A requirement section you think is wrong is a `BLOCKED` return, not a fix.
- Restating §1–§6 in your own voice anywhere in §7 or §8. They are already in the document the reader is holding.
- Splitting the work into independently-buildable units — see **You Are Not Decomposing Work** above. §7 orders components; it does not carve out things to build one at a time.
- Reporting a `sections_1_6_lines` count you did not actually take, or adjusting it to match what you assume the conductor expects.
- Designing a solution or choosing an implementation.
- Ordering §7 by importance or by effort instead of by dependency.
- A §7 component with an empty "Depends on" when it plainly depends on something.
- Writing anything into §8 about what should happen next.
