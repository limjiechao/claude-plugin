---
name: spec-audit
description: >-
  Use when about to write acceptance tests, property tests or an implementation
  from a written spec (ADRs, a glossary, rulings, a manual, a PRD), when acting
  as an independent tester before code exists, or when asked to find what a
  spec leaves undecided, unspecified or ambiguous.
---

# Spec audit

Before tests or code are written from a spec, list every **spec hole**: a case
whose expected result the named documents do not determine. Vyssotsky, quoted
by Brooks: "Many, many failures concern exactly those aspects that were never
quite specified" (_The Mythical Man-Month_, prop. 13.2). The audit belongs to
someone other than the implementer, before any code (prop. 13.3).

An unflagged hole is worse than a missing test: whoever writes the test or the
code fills it with an assumption, and the assumption then looks like the spec.

## What counts as a hole

A case is a hole when an implementer reading only the named documents could
write two different, defensible expected results for it. Typical sources:

- **Signatures and ports** the tests need but the documents don't give (an
  argument's type, a random source's interface, an error's form).
- **Domain edges**: inputs the documents don't say are valid or invalid.
- **Failure behaviour**: what happens on invalid input (throw, return an error
  value, impossible by type).
- **Order and tie rules** that change the observable result.
- **Facts you derived** rather than read. If you computed it (an extended
  table row, an implied range), it is a hole until a document states it.

A case whose answer follows strictly from the documents is not a hole. Write
its test.

## Procedure

1. Name the documents you may use. Read only those. Never read the
   implementation.
2. Sweep three input domains (Brooks, _MM-M_ p. 166), and for each, write down
   the expected result or the reason you can't:
   - **mainline**: the commonly encountered inputs;
   - **barely legitimate**: the edges of the valid domain (smallest, largest,
     empty, boundary values, every valid exception);
   - **barely illegitimate**: just outside the domain (one past each bound,
     wrong type or shape, out-of-range values from collaborators).
3. Also list every **assumption** you would need to write the tests at all: a
   signature, a port, a unit. Each one not stated in the documents is a hole.
4. Report in the output contract below.
5. **If the hole list is non-empty, stop: write no tests.** Tests written over
   a hole encode your guess as the spec. Once each hole has an answer, a fresh
   tester writes the tests.
6. If the hole list is empty, write the tests from the documents.

## Output contract

The report has exactly these parts, in this order:

1. **Documents used**: one line listing them.
2. **Spec holes**: a numbered list, mainline first, then barely legitimate,
   then barely illegitimate, then assumptions. Each hole is:
   - **Case**: the concrete input or situation.
   - **Why open**: what the documents say, and why it doesn't decide the case
     (quote or cite the passage, or say "not mentioned").
   - **Options**: 2–3 candidate answers, each with its consequence.
   - **Blocks**: which tests can't be written until it is answered.
3. **Settled cases**: one line per test you *can* write, with its expected
   result and the passage that settles it. These are written only after the
   holes are answered, unless there are no holes.
4. **Verdict**: `HOLES: n — no tests written`, or `NO HOLES — tests follow`.

## Common mistakes

| Mistake | Instead |
| --- | --- |
| Writing the tests, then noting the open questions at the end | Holes first; with any hole, write no tests |
| Assuming a signature so the tests can be written | List the signature as an assumption hole |
| Extending a table or range by your own derivation | A derived fact is a hole until a document states it |
| Only testing the valid domain | Sweep barely illegitimate inputs too |
| Phrasing a hole as "unclear" | Give the case, why it's open, and 2–3 options |
