---
name: cross-platform-tests
description: >-
  Use when Node.js or TypeScript tests behave differently across runners —
  passing locally but failing in CI, passing on one OS but failing on
  another, or flaking on Ubuntu while macOS stays green. Also use when
  auditing tests for portability risks: env-var syntax in `package.json`
  scripts (`FORCE_COLOR=1 vitest`), fixed-delay `await tick()` /
  `setTimeout` waits in ink-testing-library or RTL, filesystem assertions
  (mtime, paths, line endings), NTFS-reserved characters in filenames,
  locale leaks, snapshot drift across OSes. Covers triage of multi-OS
  GitHub Actions matrices — root cause vs cascades, fix order — and
  recognition of discriminating signals (`replaceAll(':', '-')` as an
  NTFS defence; consecutive `await tick();` as a race confession;
  `mtimeMs === mtimeMs` testing the wrong invariant). Invoke when the
  platform or runtime is the suspect — not generic test-writing or code
  review.
---

# Tests that pass on every runner, not just yours

## What this skill is actually for

The two canonical fixes — `cross-env` for inline env vars in `package.json`
scripts, and a polling `waitFor` for async UI tests — are widely known and
short to apply. Skim the **Quick fixes** section if that's all you need.

The harder work, and the work where most reviewers and AFK agents get it
wrong, is two-fold:

- **Triaging a multi-OS failure log.** Which failure is the root cause, which
  rows are downstream cascades, what order should you patch in. Get this
  wrong and you "fix" three things, only one of which mattered.
- **Recognising portability *signals* in code.** The discriminating moves —
  spotting `replaceAll(':', '-')` as an NTFS-reserved-character defence,
  reading a double-`tick()` as the author's confession, noticing
  `mtimeMs === mtimeMs` is asserting against the wrong invariant — separate
  a real review from a generic checklist. This skill loads them into context.

The body below is organised around those two jobs. The quick fixes are at
the top because you'll often need them; the diagnostic content is what
makes this skill load-bearing.

---

## Quick fixes (the well-known answers)

### Inline `FOO=1 cmd` in a `package.json` script

**Symptom.** Windows CI dies in seconds with `'FOO' is not recognized as an
internal or external command`. POSIX runners pass.

**Fix.** Wrap with `cross-env`:

```json
{ "scripts": { "test": "cross-env FORCE_COLOR=1 vitest run" } }
```

Install `cross-env` once at the workspace root. Per-package devDependencies
aren't needed — pnpm hoists it.

**Alternative**: drop the prefix from `package.json` and set the variable in
the CI workflow `env:` block. Cleaner per-package but loses the variable for
local non-TTY runs (`pnpm test | cat`, `turbo run test`) — see the
**ansi-color-piping** skill if your tests assert on escape codes locally.

**What does *not* work**: vitest `test.env`, `setupFiles`, top-of-file
`process.env.FOO = '1'`. These run *inside* the worker — too late for any
library (chalk, supports-color, ink) that probes `process.env` at module
import time.

### Fixed-delay `await tick(60)` between `stdin.write` and `lastFrame()`

**Symptom.** Test passes on dev box, fails on `ubuntu-latest` CI. Received
frame in the failure shows the *previous* state (or `Loading…`) instead of
the post-input state.

**Fix.** Poll for the condition. A minimal helper:

```ts
async function waitFor<T>(
  predicate: () => T | Promise<T>,
  { timeoutMs = 2000, intervalMs = 10 } = {},
): Promise<T> {
  const deadline = Date.now() + timeoutMs
  let lastError: unknown
  for (;;) {
    try { return await predicate() }
    catch (e) { lastError = e }
    if (Date.now() >= deadline)
      throw lastError ?? new Error(`waitFor timed out after ${timeoutMs}ms`)
    await new Promise((r) => setTimeout(r, intervalMs))
  }
}
```

Use by wrapping the assertion itself:

```ts
stdin.write(ENTER)
await waitFor(() => {
  expect(stripAnsi(lastFrame() ?? '')).toContain('Consultation · loaded')
})
```

The assertion *is* the condition. No constant to tune.

**Drop-in version** at `scripts/wait-for.ts` in this skill folder; the same
helper sits in many React Testing Library codebases.

**What does *not* work**: bumping the constant. `tick(500)` just turns a
fast flake into a slow flake — the 2-second outlier on CI is still out
there.

---

## Triage discipline — when handed a failing multi-OS log

The matrix log usually shows dozens of failure rows. Most are cascades from
a single root cause. The discipline is to find the root, ignore the
cascades, and patch one *class* of failure at a time.

### Step 1 — read the OS pattern, not the row count

Three patterns and what each means:

| OS pattern | Likely class |
|---|---|
| **Windows fails, Linux/macOS pass** | Shell or path or syntax — env vars, `&&` chaining, hardcoded `/tmp`, line endings |
| **Linux fails, macOS passes (Windows ?)** | Race condition. Linux CI runner is slower than the dev's macOS box; macOS is masking the bug |
| **All OSes fail** | Real logic bug, not a portability issue. Investigate as a regular bug |
| **Linux + Windows fail, macOS passes** | Combo of the above two — usually a race *and* a shell issue stacked |

The user's own log (the one that prompted this skill) was the fourth case:
Windows died at `FORCE_COLOR=1 vitest` (shell), Ubuntu had 7 race failures
in `history-app.test.tsx` (race), macOS was green. Two unrelated classes.

### Step 2 — the first ABEND wins; downstream rows are cascades

In the user's Windows log, every package showed `ELIFECYCLE Test failed`.
Six rows of red. **All six are the same cause**: the `FORCE_COLOR=1` prefix
that aborts before vitest loads. Fix that one line and all six rows go
green together.

Read CI logs chronologically. Find the first row whose error message is
*substantive* (not just `ELIFECYCLE`, not just `Process completed with
exit code 1`, not just a tool wrapper saying its child failed). That row
is the root cause. Everything below it that just says "test failed" is
likely the same cause repeating.

### Step 3 — patch one class at a time, in dependency order

Order matters when failures stack:

1. **Process must start before it can race.** Fix env-var/shell issues
   first. You cannot diagnose race conditions on a Windows runner that's
   dying before vitest loads.
2. **Tests must run before snapshots can diverge.** Get the suite running
   on every OS, *then* deal with snapshot/path/locale issues.
3. **Race conditions last.** They're the highest-effort fix and the most
   likely to need iteration. Tackle them when you have a stable
   environment to test against.

Pushing a patch that fixes both classes at once is fine *as a PR*, but
in the *diagnostic* phase, knowing which class is which keeps you
honest. If both env-var and race fixes are in flight and CI still
fails, you don't know which one was wrong.

### Step 4 — beware "fixed by re-running"

A CI re-run button that turns red to green is an admission of a race
condition, not evidence of a flake. If a test needed a re-run to pass,
treat it as broken until you understand why.

### Step 5 — Attack the class, not the instance (Lesson A)

When the matrix reveals an anti-pattern in one file, **grep the whole
repo for that pattern before pushing the fix**. A single class of failure
typically lives in five or six places — the file you noticed, plus
sibling test files that share the same idioms. Each unfixed instance
becomes the next round of the matrix.

Real example. The May 2026 hexagram-generator stabilisation (commits
`4eae942` … `800d3fc`) spent **rounds 2 → 3 → 6** serially discovering
the same `await tick()` after `stdin.write()` anti-pattern in three
different packages: `history-ui` (round 2), then `casting-ui` + `shell`
(round 3), then `core` + a different `casting-ui` test (round 6). One
workspace-wide `grep -rEn "await tick\b" packages/ apps/` at round 2
would have collapsed rounds 3 and 6 into the same PR. That's a 24-hour
delay paid for by serial diagnosis.

**The discipline, on encountering a class signal:**

1. **Grep the whole workspace** for the anti-pattern. Not just the file
   that flaked — every sibling that could have flaked but didn't yet.
2. **Triage in one pass.** For each match, classify as race-prone (swap
   to `waitFor`), yield-only (rename or remove), or animation-pump (wrap
   in a named helper). The triage is mechanical once you know what
   you're doing.
3. **Fix the class, not the instance.** Land all sites in one PR (or one
   PR per file with shared helpers). The cost of touching ten files at
   once is far below the cost of paying for ten round-trips through CI.
4. **Erect a fence.** Add a lint rule (`no-restricted-syntax` with an
   AST selector for the anti-pattern, scoped to test files) so the next
   developer can't reintroduce it. Existing un-migrated files carry a
   top-of-file disable directive lifted as each migrates.

**Concrete fence — banning `await tick()` in test files:**

```js
// eslint.config.js
{
  files: ['**/*.test.{ts,tsx}'],
  rules: {
    'no-restricted-syntax': ['error', {
      selector: "AwaitExpression > CallExpression[callee.name='tick']",
      message: "Use waitFor(predicate) / yieldMacrotask() / pumpSliderTick(n) instead. See cross-platform-tests skill, signal #1.",
    }],
  },
}
```

The selector matches `await tick(...)` exactly — not bare references,
not arguments containing `tick`. Test files migrate one at a time, lifting
their `/* eslint-disable no-restricted-syntax */` directive as they go.

**Why this matters specifically for race-prone patterns.** Each instance
of `stdin.write → tick → expect` masks a different latent flake — the
runtime is unbounded, so what works on a 4-CPU dev box can still fail on
a 2-CPU CI runner. Serially fixing them through CI iterations means you
push, wait 5–15 minutes for the matrix, read logs, push again. That
loop adds 30–90 minutes per file. Class-wide audits skip that loop.

### Verification — the trap that wastes hours

`FORCE_COLOR` may already be exported in your shell, in CI, or in your
agent/sandbox environment. If it is, **every** run is colour-on no matter
what your change does — so a passing run proves nothing. You can confirm
a fix that does nothing or dismiss a real fix as inert.

Before trusting any colour/env-var fix, neutralise the environment **and**
reproduce the piped condition:

```bash
env -u FORCE_COLOR -u NO_COLOR -u CI pnpm test | cat
```

- `env -u …` removes the variables that mask the bug. (`NO_COLOR` disables
  colour and wins over `FORCE_COLOR` in many libraries — rule it out too.)
- `| cat` makes stdout a pipe, reproducing the non-TTY condition even when
  you're sitting in an interactive terminal.

Then prove the A/B: the failure should **reproduce without the fix** and
**not reproduce with it**, both under that exact command. If you cannot
make it fail without the fix, your environment is still masking it and
you have verified nothing.

For race conditions, the analogous discipline is `pnpm test --repeat 50`
plus a CPU throttle (`taskset -c 0`, Docker `--cpus 0.25`) to simulate
runner load. If you can't reproduce locally, you can't trust the fix.

---

## Discriminating signals for code review

When auditing a test file or reviewing a PR, these are the patterns that
distinguish a careful read from a generic survey. Each signal is concrete
— if you see it in the file, the listed interpretation is almost always
right.

See `references/signals.md` for the full catalogue (15+ signals). The
short version, ranked by how often they come up:

1. **`await tick(N)` (or `setTimeout(N)`) immediately followed by an
   assertion on `lastFrame()` / `render`-result / dom-state.** Race
   condition. The wait is unbounded async work and the constant is a
   guess. Replace with `waitFor` (see Quick fixes).

2. **Two consecutive `await tick();` calls.** The author's confession
   that one wasn't enough. They've already met the bug; they patched the
   symptom not the cause. High-confidence flake.

3. **`.replaceAll(':', '-')` in a filename derived from a timestamp or
   user input.** Windows portability defence — `:` is one of the
   characters NTFS reserves (`< > : " / \ | ? *`). Good code; flag if
   missing in a similar position.

4. **`expect(after.mtimeMs).toBe(before.mtimeMs)`.** Testing the wrong
   invariant. mtime resolution varies by filesystem (FAT 2s, ext4 1ns
   or 1s depending on inode_size, NTFS 100ns, APFS 1µs). The actual
   invariant is *content unchanged*; assert on bytes (`fs.readFile` →
   string equality), not on mtime.

5. **`FOO=1 cmd` in a `package.json` script (`scripts.*`).** POSIX-only.
   Windows CMD will reject it. Wrap with `cross-env`.

6. **Hardcoded `/tmp/...` or `/var/folders/...` in a test path.** Not
   portable. Use `os.tmpdir()` + `path.join`.

7. **`new Date()` or `Date.now()` baked into an assertion as a string.**
   Timezone-dependent. The test's own clock leaks the runner's TZ.
   Pin `TZ=UTC` in CI, or assert on `.getTime()` / epoch ms.

8. **`toLocaleString` / `localeCompare` in the code under test, no
   explicit locale pinned in the test.** Locale leak. Pin `LANG=C` or
   pass an explicit `Intl` locale.

9. **`process.kill(pid, 0)` or signals other than `SIGTERM`/`SIGKILL`.**
   Windows-incompatible signals. Gate with `process.platform !==
   'win32'` or use a different liveness check.

10. **`fs.watch` with a single-event assertion.** Windows fires multiple
    events per write. Debounce in the test.

11. **`setRawMode` in a test that doesn't mock stdin.** TTY-only;
    `ink-testing-library` stdin isn't a TTY.

12. **Hardcoded `\r\n` or `\n` in a comparison against on-disk file
    contents you didn't write.** Line-ending leak. Either normalise
    before compare or ensure `.gitattributes` has `* text=auto eol=lf`.

Signals you should *not* flag (common false positives):

- `path.join(...)` — this is the *correct* pattern; only flag absent
  `path.join` where string concatenation is used.
- `fs.mkdtemp(path.join(process.cwd(), 'prefix-'))` — unconventional but
  portable. If the file has a comment explaining the choice (status-line
  truncation, etc.), engage with the rationale.
- A test that uses `await tick()` *and also* has a `waitFor` defined —
  the `tick` may be for a legitimate one-macrotask yield. Check usage
  before flagging.

---

## Audit discipline — when reviewing a file for portability

When asked to audit a test file:

1. **Stay in file scope.** If the prompt is "audit `foo.test.tsx`," the
   audit covers that file. Don't pull in `package.json`, `vitest.config.ts`,
   or workflows unless their content is directly load-bearing for an
   in-file assertion (e.g., the file asserts on ANSI codes that depend on
   `FORCE_COLOR` being set elsewhere — *that* is in scope, but only as a
   citation, not as a "fix this script too").

2. **Cite line numbers accurately.** Read the file first; check the lines.
   A finding at line 247 that's actually at line 281 reads as carelessness.

3. **Categories that don't apply: say so explicitly, don't fill them.**
   "Snapshots — not applicable; no `toMatchSnapshot` calls." is a
   complete entry. Three paragraphs of speculation about hypothetical
   snapshot risks is worse than no entry. The reader needs to know the
   category was *checked*, not that something *might* exist there.

4. **Do not speculate about filesystems, configurations, or future
   defaults that aren't in the file.** No "FAT/exFAT would round mtime
   to 2 seconds" if the file isn't running on FAT. No "any future change
   to the default columns would break this" if no such change is
   proposed. Future-proofing fantasies fill space without informing.

5. **Engage with comments.** If the file has an inline comment
   explaining a non-obvious choice, your audit should acknowledge it
   rather than re-flag the choice generically. "tmpDir under
   `process.cwd()` not `os.tmpdir()` — the comment justifies this with
   status-line truncation; portable on every OS, deliberate trade-off."

A good audit reads like a careful human review. A bad audit reads like
the audit-checklist was filled in. The difference is that the human cites
specifics from the file; the checklist cites the categories.

---

## See also

- `references/signals.md` — the full catalogue of discriminating
  portability signals. Skim before auditing.
- `references/env-vars.md` — env-var recipe book (cross-env, dotenv-cli,
  vitest config, GitHub Actions, Turbo). Reference, not reading material.
- `references/async-waits.md` — deeper look at `waitFor` semantics, fake
  timers, and why fixed delays can't bound real async chains.
- `scripts/wait-for.ts` — drop-in helper to copy into a project.
- The `ansi-color-piping` skill — sibling for the specific case of ANSI
  escape codes vanishing under piped stdout.

## Honest framing

Cross-platform tests aren't about supporting Windows for its own sake.
They're about catching real bugs — race conditions, hidden POSIX
assumptions, locale leaks — that would also bite Linux users running in
containers, in slow VMs, under different shells. A test suite that
passes on Ubuntu *and* on Windows is one that has earned its "works"
claim. One that only passes on the author's laptop has not.
