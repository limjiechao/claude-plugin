---
name: authoring-adrs
description: >-
  Record an architecture decision as a short, durable ADR (Architecture Decision
  Record). Use when a decision is hard to reverse, constrains future work, picks
  one option among real alternatives, or would otherwise survive only in someone's
  head. Do NOT use for routine or easily-reversed choices.
---

# Authoring Architecture Decision Records

An ADR captures a decision whose RATIONALE would otherwise be lost — the kind a
future engineer will eventually question ("why on earth is it done this way?")
without the context to answer. The decision lives in the code; the *reasoning*
lives nowhere unless you write it down. An ADR is that durable record of the
reasoning, the alternatives, and the consequences.

A program's meaning is the theory its makers hold (Naur). ADRs externalize the
load-bearing parts of that theory — the parts too large to fit in a commit
message and too important to leave implicit. They are also the artifact a
conceptual-integrity check measures against: an ADR is the written form of the
"one mind's design" (Brooks) that the code is supposed to embody.

## When an ADR is warranted (and when it is NOT)

Write one when the decision is **significant** — at least one of:
- Hard or expensive to reverse (a one-way door).
- Constrains or shapes future work across more than one component.
- Chooses one option where credible alternatives existed and were rejected.
- Encodes a non-obvious trade-off a newcomer would otherwise relitigate.

Do **not** write one for routine, local, or trivially-reversible choices.
ADR inflation is its own failure: if every decision gets a record, none get
read, and the practice becomes ritual rather than memory. When unsure, ask the
human whether this rises to ADR-worthy rather than defaulting to yes.

## Procedure

1. Confirm significance against the criteria above. If it doesn't qualify, a
   commit-message body is the right home instead — say so and stop.
2. Find the next ADR number and the existing format in `docs/adr/` (or the
   project's location). Match the house style; do not impose a new one.
3. Draft the record (template below). Keep it short — one page is plenty.
4. ADRs are **append-only**. Never edit a decision into a past ADR or delete one.
   When a later decision overturns an earlier one, write a NEW ADR and mark the
   old one `Superseded by ADR-NNNN`. The history of reversals is itself signal.

## Template (Nygard style)

    # ADR-NNNN: <short decision title>

    - Status: Proposed | Accepted | Superseded by ADR-NNNN
    - Date: YYYY-MM-DD

    ## Context
    The forces at play: the problem, the constraints, the requirements, the
    things that are true regardless of the decision. State the tension that
    forces a choice. No solution here.

    ## Decision
    "We will <decision>." Active voice, present tense. State what was chosen.

    ## Alternatives considered
    The real options that were on the table, and the specific reason each was
    rejected. This section is the most valuable and the most often skipped —
    it is what stops a future engineer from re-walking a dead end.

    ## Consequences
    What becomes easier, what becomes harder, what new constraint this imposes.
    Include the costs, not just the benefits. An ADR with only upsides is
    incomplete.

## Compact alternative (Y-statement)

For smaller-but-still-significant decisions, a single structured sentence:

    In the context of <use case/component>, facing <concern>, we decided
    <option> over <alternatives>, to achieve <quality>, accepting <downside>.

## Boundary

An ADR records that a decision was made and why; it does not make the decision
good. Do not author an ADR that invents a rationale to justify a choice no human
actually reasoned through. If the "why" is unclear, the decision isn't ready to
record — surface that to the human.
