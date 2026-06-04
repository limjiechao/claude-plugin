---
name: reviewable-changes
description: >-
  Shape changes so a human reviewer can verify correctness in roughly one pass.
  Use when a change is growing large, mixes several kinds of work, spans many
  files, or when preparing a PR or asking for review. Decompose oversized
  changes into a reviewable sequence.
---

# Reviewable Changes

Legibility goal (a) is concrete: a reviewer should be able to verify a change is
correct in roughly one pass. Reviewability is not a courtesy — it is the gate
that determines whether a defect is caught or shipped. This skill keeps changes
inside the envelope where human review actually works.

The envelope is empirical, not aesthetic. The largest peer-review study on
record (SmartBear / Cisco Systems, ~2,500 reviews over 3.2M lines of code) found
defect-discovery stays high — roughly 70-90% — only when a reviewer takes no
more than ~200-400 lines at a time, over 60-90 minutes; past that, attention
collapses and defects sail through. A diff that exceeds the envelope isn't
"thoroughly reviewed," it's rubber-stamped.

## The rules

1. **One change, one intent.** A diff that mixes a refactor, a feature, and a fix
   is three reviews wearing one coat — and the reviewer can't isolate which part
   introduced a regression. Separate them. A pure refactor (no behavior change)
   and a behavior change must never share a diff: the reviewer's whole strategy
   differs between the two.

2. **Stay under ~400 lines of substantive change** where you can. Generated
   files, lockfiles, and mechanical renames don't count against the budget —
   call them out explicitly so the reviewer can skip them with confidence.

3. **If a change must be large, sequence it.** Decompose into an ordered series
   of small changes, each individually correct, reviewable, and (ideally)
   shippable. Lead with the refactor that makes the feature a small diff, then
   the feature on top. State the sequence up front so the reviewer knows the plan.

4. **Make the diff locally legible.** Prefer changes a reviewer can understand
   without holding the whole system in their head (orthogonality; Hunt & Thomas).
   If verifying this change requires reasoning about distant code, either bring
   the relevant context into the PR description or reconsider whether the design
   forces too much ripple.

5. **Lead with intent.** The PR/description states WHY before WHAT, names what to
   review carefully versus skim, and flags anything you are unsure of. Direct the
   reviewer's scarce attention; don't make them find the load-bearing 20 lines
   inside 380 lines of scaffolding.

## When you can't get under the envelope

Some changes genuinely can't be split below the threshold (a framework
migration, a generated-code bump). When that's true, say so explicitly, isolate
the human-meaningful part of the diff from the mechanical bulk, and tell the
reviewer precisely where to spend their attention. An honest "review these 60
lines; the other 900 are a mechanical codemod" is worth more than a 960-line
diff presented as uniform.

## Boundary

Small and single-intent makes a change *reviewable*; it does not make it
*correct*. Don't shrink a diff by hiding complexity behind an indirection the
reviewer now can't see — that trades visible size for invisible obscurity, which
is worse. The goal is genuine one-pass verifiability, not a smaller number.
