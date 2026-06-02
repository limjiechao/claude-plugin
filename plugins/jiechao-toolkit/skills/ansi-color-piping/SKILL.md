---
name: ansi-color-piping
description: >-
  Diagnose and fix Ink (or other CLI) tests that emit no ANSI colour codes when
  run under Turbo — or any task runner that pipes the test process's stdout. The
  signature is tests that assert on escape codes (`[2m`, `[7m`, or substrings
  whose spacing depends on ANSI) passing in an interactive terminal but failing
  under `turbo run test` or in CI. Trigger this skill whenever the user mentions:
  vitest/Ink tests that pass locally but fail under turbo or CI, ANSI or
  escape-code assertions, `ink-testing-library` frames rendering without styling,
  `FORCE_COLOR` / `NO_COLOR`, or "colours are gray / stripped under turbo". Use
  it especially when the user already tried `FORCE_COLOR` or vitest's `test.env`
  and it "didn't work" — that mis-fix is the central case this skill addresses.
---

# Ink/CLI tests lose their colours under Turbo

## Symptom

A test asserts on ANSI escape codes — `expect(frame).toContain('[2m')`
(dim), `'[7m'` (inverse), or even a plain substring like `' Casting '`
whose surrounding spaces only survive because a reset code sits next to them.
The test **passes when you run `vitest` directly in your terminal** but **fails
under `turbo run test`** (or in CI). The received output is the right text with
no escape codes in it.

## Why it happens

`turbo run test` spawns `vitest`, captures its stdout so it can prefix each line
(`@scope/pkg:test: …`), and so vitest's stdout is a **pipe, not a terminal**.
Ink — via `chalk` / `supports-color` — checks `isatty(stdout)`, sees no TTY, and
renders plain text with no ANSI. Run in an interactive terminal, vitest's stdout
*is* a TTY, colour is on, and the same assertions pass. That gap between "works
on my machine" and "fails under turbo/CI" is the entire bug.

`FORCE_COLOR` overrides the TTY check: with it set, Ink emits ANSI regardless of
what `isatty` returns. The whole fix is getting `FORCE_COLOR` to the vitest
process *reliably*.

## The fix that works

Set `FORCE_COLOR` in the package's `test` **script**, so it is a real
environment variable before the `vitest` process even starts:

```json
{ "scripts": { "test": "FORCE_COLOR=1 vitest run" } }
```

Why the script boundary: the shell exports the variable before `vitest` exists,
so vitest — and the worker processes it forks — are *born* with it.
`supports-color` can read it however early it wants and still sees it. This is
identical to what a manual `FORCE_COLOR=1 turbo run test` does, just made
permanent so nobody has to remember the prefix.

`1` is enough for `bold` / `dim` / `inverse` and the 16 named colours (level-1
ANSI). Reach for `2` (256-colour) or `3` (truecolor) only if the code renders
hex/RGB values — at a lower level the library quantises them to different escape
sequences, which matters if you assert on the exact bytes.

## What does NOT reliably work

```ts
// vitest.config.ts — do not rely on this
export default defineConfig({ test: { env: { FORCE_COLOR: '1' } } })
```

`test.env` injects the variable into `process.env` *after* the vitest worker has
already started. Whether that lands before Ink/chalk reads it is
timing-dependent: in this skill's origin case the identical `test.env` config
worked in one environment and silently failed in another. Treat **anything that
mutates `process.env` after the process is already running** — `test.env`, a
`setupFiles` assignment — as unreliable for colour detection. Set the variable
before the process starts (the script boundary above), full stop.

## Verifying a fix — the trap that wastes hours

`FORCE_COLOR` may already be exported in your shell, your CI, or an
agent/sandbox environment. If it is, *every* run is colour-on no matter what you
change — so a passing run proves nothing. You can "confirm" a fix that does
nothing, or dismiss a real fix as inert. (This genuinely happened while
debugging the origin case: a shell with `FORCE_COLOR=3` set produced two
confident, wrong conclusions in a row.)

Before trusting any result, neutralise the environment **and** reproduce the
piped condition:

```bash
env -u FORCE_COLOR -u NO_COLOR -u CI turbo run test --force | cat
```

- `env -u …` removes the variables that mask the bug. (`NO_COLOR` disables
  colour and wins over `FORCE_COLOR` in many libraries — rule it out too.)
- `| cat` makes turbo's own stdout a pipe, reproducing the non-TTY condition
  even when you are sitting in an interactive terminal.
- `--force` bypasses Turbo's cache — a cached task replays its stored (possibly
  colourless) output instead of actually re-running.

Then prove the A/B: the bug should **fail without the fix and pass with it**,
both under that exact command. If you cannot make it fail, your environment is
still masking it and you have verified nothing.

## Check the whole monorepo, not just one package

These assertions cluster. If one package's Ink tests fail this way, its siblings
very likely do too — they were all written and checked in a colour-on terminal,
so the latent break is identical everywhere. Before declaring the job done,
grep every package for tests that touch escape codes:

```bash
grep -rlE '\\u001b|\[[0-9]+m' packages/*/tests
```

Apply the same `FORCE_COLOR=1` script change to every package's `test` script.
Keeping the scripts uniform also means a newly scaffolded package (copied from a
sibling) inherits the fix instead of silently reintroducing the bug.

## When the better fix is to stop asserting on ANSI

Forcing colour on is sometimes papering over a brittle test. An assertion on raw
escape bytes is coupled to the colour library's encoding, the `FORCE_COLOR`
level, and the library version — a dependency bump that changes one sequence
breaks it. If the test's real intent is "this content is present" or "this row
is highlighted", prefer:

- asserting on the text after stripping ANSI (`stripAnsi(frame)`), or on
  component props / pre-render data;
- keeping one or two focused smoke tests that *do* check ANSI is emitted, so the
  styling itself still has coverage.

In the origin monorepo this was visible side by side: the package whose tests
stripped ANSI before asserting passed under piped Turbo untouched; only the
packages asserting on raw `[2m` / `[7m` codes broke. When you see a raw
escape-code assertion, weigh fixing the test against forcing colour — and give
the user both options rather than only the `FORCE_COLOR` one.

## Honest framing

Don't hand the user `FORCE_COLOR=1` with no model of why. If it doesn't take —
wrong placement, or a masked environment — they are stuck with no way to debug.
Explain the two load-bearing facts: the variable must reach the process
*before it starts*, and verification only means something in an environment
that is not already colour-on.
