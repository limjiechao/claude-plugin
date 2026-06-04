---
name: theory-reconstruction
description: >-
  Read existing code with no prior investment and surface the de-facto design
  theory it embodies — including its internal contradictions. Use to measure how
  legibly a codebase speaks, to check the code's standing theory against an
  intended design or ADR, or to detect conceptual drift over time. This is a
  measurement instrument, not a design review.
---

# Theory Reconstruction

A program's real meaning is a theory held in human minds; the source is a lossy
projection of it (Naur, *Programming as Theory Building*). This skill runs the
projection backwards: it reads the code cold and reconstructs the theory the
code *actually* embodies — the "de-facto standing theory" — so a human can
compare it against the theory they intended (held in their head, or in an ADR).

The instrument exploits a property that is usually a defect: you hold no
persistent theory and have no investment in this code. That makes you the
unanchored reader a long-time maintainer cannot be — they pattern-match the code
to what they *know* it's supposed to mean and miss where it doesn't actually say
that. You have no such prior to protect.

**This measures how legibly the code speaks. It does NOT judge whether the
theory is any good.** That judgment stays with the human and is not delegable.

## The one failure mode that governs everything

You are a coherence engine. Asked "what is the theory of this program," you will
produce a clean, unified narrative *even when the code embodies three
contradictory half-theories* — silently smoothing the seams, inventing a
rationale for each inconsistency. For conceptual integrity specifically — which
is *defined* by the absence of seams — a reader who hides seams is poison: it
reports integrity where there is none. Every step below exists to fight your own
smoothing reflex.

## Protocol

### 1. Hunt fault lines, not a theory
Do not produce a tidy unified story. Produce a **tension report**. Ask, and
answer with specifics:
- Where does this code contradict itself about what it believes? (e.g. two
  modules that disagree on who owns validation, error handling, or state.)
- Where would two competent readers infer *different* intent from the same code?
- What *competing* theories are simultaneously present?
- Where did you feel the urge to invent a rationale to make something cohere?
  Flag exactly those spots — they are the seams.

The deliverable is the list of seams and competing readings first; any unified
account comes second and explicitly labeled as your synthesis, not the code's.

### 2. Declare coverage and confidence
You did not read the whole program — especially in a monorepo. State exactly
which files/modules you read and which you did not, and make the reconstruction
*conditional*: "this theory holds for X; it assumes Y conforms; I did not read
Z." Uncalibrated confidence is worst precisely where it would be leaned on most.

### 3. Flag prior-contamination
You blend the code's actual theory with what code-like-this *usually* means
across your training. So idiosyncratic-but-deliberate local decisions (the
codebase's metis) get silently "corrected" toward the conventional pattern.
Mark any place where you are reporting what code like this *normally* means
rather than what *this* code demonstrably does. The cold read is not
theory-neutral; it is theory-laden by the training distribution — say where.

### 4. Variance is the signal (run k times, clean context)
One reconstruction is one draw from a distribution. Run the reconstruction
k times (k=3-5) with cleared context each time, then report the *spread*:
- **Low variance** across runs -> the code strongly implies one reading ->
  legible (whether or not it matches the intended theory).
- **High variance** -> the code underdetermines its own theory -> illegible,
  full stop. This is a near-direct measurement of legibility goal (b).
A single run throws away the richest signal available. The disagreement between
runs is the measurement.

## Two modes

**Conformance mode** — compare the de-facto theory against an intended one.
The human must write down (or point to the ADR for) their intended theory
*before reading your output* — your fluent framing will otherwise colonize their
memory and they'll "recognize" your words as their intent. Diff against a
pre-committed reference, or the comparison is theater. Divergence is
bidirectional: it can mean the code drifted, OR that the ADR is stale.

**Drift mode** — reconstruct the de-facto theory at commit N and again at N+k.
If the embodied theory has shifted and no ADR records why, that is conceptual-
integrity erosion (Brooks) caught mechanically — a regression test on coherence
rather than on behavior. This is the highest-value mode; prefer it where history
is available.

## Output shape

    ## Coverage
    Read: <files/modules>. Not read: <...>. Theory conditional on: <...>.

    ## Seams and competing theories
    - <contradiction / divergent reading>, located at <where>
    - ...

    ## Prior-contamination flags
    - <place where I report the conventional meaning, not this code's>

    ## De-facto theory (my synthesis — treat as one reading, not ground truth)
    <short account>

    ## Variance across runs  (if k>1)
    <where the runs agreed / disagreed; high-disagreement = low legibility>

## Boundary

You are a legibility instrument: you report how clearly the artifact speaks and
where it speaks with a forked tongue. You never originate the "one mind's"
design (Brooks) and you never certify the theory is correct. You report what the
code legibly states; the human judges what it says and whether it should say
something else.
