---
name: capturing-commit-intent
description: >-
  Write commit messages that record WHY a change exists, and split commits that
  contain more than one intent. Use when committing, staging changes, preparing
  a PR description, or when the user asks to write or fix a commit message.
---

# Capturing Commit Intent

The diff already shows WHAT changed. A reviewer can read it. What no one can
recover later is WHY — the intent that existed in working memory at the moment
of the change and evaporates the instant this session ends. Code is cheap to
generate; intent is the scarce resource. Your job here is to externalize intent
while it is still free to capture.

A program's real meaning is a theory the maintainers hold in their heads, not
the source text (Naur, *Programming as Theory Building*). You hold no persistent
theory. The commit message is the cheapest, most durable place to leave the
breadcrumb a future human needs to rebuild that theory.

## Procedure

1. Look ONLY at the staged diff. Do not infer intent from the broader task —
   infer it from what is actually staged.
2. Enumerate the distinct intents present. A refactor is one intent. A feature
   is another. A bug fix is a third. A formatting sweep is a fourth.
3. **If there is more than one intent, STOP and propose splitting** into separate
   commits, one intent each. Do not write a message that papers over a mixed
   commit — a mixed commit is unreviewable in one pass, which defeats the point.
4. For each commit, write:
   - **Subject** — <=50 chars, imperative mood, names the behavior change.
   - **Body** (wrap ~72 chars) — the problem this solves; why this approach over
     the alternative you considered; any trade-off, known limitation, or
     constraint a maintainer would otherwise have to rediscover by archaeology.
5. Never write a body that merely restates the diff in prose. If the subject is
   self-explanatory and there is no non-obvious "why," omit the body entirely.
   An empty body is honest; a redundant body is noise that trains readers to
   skip bodies.

## The test for a good body

A maintainer six months from now hits this code, doesn't understand why it's
shaped this way, and runs `git blame`. Does your body answer their question, or
does it just narrate what they can already see? Write for that person.

## Example

Bad — restates the diff, captures no intent:

    Update auth middleware

    Changed the token refresh logic and added a mutex.

Good — captures the WHY, the rejected alternative, and the constraint:

    Fix token-refresh race under concurrent requests

    The middleware refreshed tokens lazily with no lock; concurrent
    requests triggered duplicate refreshes and intermittent 401s.
    Guard refresh with a mutex.

    Rejected a per-request token cache — it broke logout, since a
    cached token outlived session teardown. Closes #742.

## Boundary

This protects the conditions for theory-rebuilding; it does not certify the
change is good. If you cannot articulate why the change exists, that is a signal
the change may not be well-understood — surface that to the human rather than
inventing a plausible rationale.
