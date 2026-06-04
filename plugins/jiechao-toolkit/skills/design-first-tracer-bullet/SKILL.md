---
name: design-first-tracer-bullet
description: >-
  Before generating non-trivial code, state the design and build a thin
  end-to-end slice first. Use when a task is large, unfamiliar, spans multiple
  files or layers, or lacks a clear design — i.e. whenever you would otherwise
  start writing bulk implementation from scratch.
---

# Design First, Then a Tracer Bullet

You write code effortlessly, which is exactly the danger: you will happily
produce 800 lines of plausible architecture in the dark before anyone has
confirmed the shape is right. This skill forces two cheap steps that prevent
that — externalize the design, then validate it end-to-end thin — before you
spend (and make the human review) bulk implementation.

Two principles justify this. First, conceptual integrity — a system reflecting
one coherent design — is the most important property of a system (Brooks,
*The Mythical Man-Month*), and you cannot originate it: you average over
millions of conflicting designs. The human must own the design theory; your job
is to make it explicit and conform to it. Second, build a thin slice end-to-end
to get feedback under real conditions rather than specifying the system to death
(Hunt & Thomas, *The Pragmatic Programmer* — "tracer bullets"). A tracer bullet
fired in the dark shows you where you're actually aiming before you commit the
magazine.

## Step 1 — State the design before writing implementation

In 3-6 sentences, before any non-trivial code, write:

- **Intent** — what this change is for, in problem terms.
- **Approach** — the shape of the solution: the main components and how they
  connect. Name the seam(s).
- **Assumptions** — what you are taking as given. Make these explicit so a wrong
  assumption is caught now, not after implementation.
- **Non-goals** — what you are deliberately NOT building. This is where you
  resist the second-system effect (Brooks): no speculative configuration, no
  extension points no one asked for, no future-proofing. Name the temptations
  you are declining.

**If the task has no clear design and you find yourself inventing one, STOP.**
Present the design and ask the human to confirm or correct it before you build.
Inventing a design and then implementing it silently is how an LLM manufactures
incoherence — you become a second cook in a kitchen that should have one.

## Step 2 — Fire a tracer bullet

Build the thinnest possible path that runs end-to-end — from entry point to
output — touching every layer the real feature will touch, but doing the minimum
real work at each. Hard-code, stub, and shortcut the interiors; the goal is a
working skeleton, not a finished room.

The tracer bullet answers, cheaply: do the layers connect the way the design
assumed? Is the seam in the right place? Does data flow through? If the skeleton
is wrong, you've spent minutes, not hours — and the human reviews a 40-line
skeleton, not a 600-line guess.

Only after the tracer bullet runs and the human (or a test) confirms the shape
do you flesh out the interiors.

## What this is not

This is not big-design-up-front. The design statement is 3-6 sentences, not a
spec document; the tracer bullet is runnable code, not a diagram. The point is
to make the design cheap to inspect and the shape cheap to correct — not to
front-load ceremony.

## Boundary

You make the design explicit; the human judges whether it is good. When the task
genuinely is trivial and the design is obvious, skip both steps and say so —
applying this ritual to a one-line change is its own waste.
