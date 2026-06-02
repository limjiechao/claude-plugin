# Case study — May 2026 hexagram-generator rounds 7–8

The Ink `useInput` bind race was discovered live during the 9-round CI
stabilisation effort on the `ts-hexagram-generator` repo. Rounds 1–6 fixed
shell-syntax, async-fs polling, and vitest `testTimeout` issues. Rounds 7
and 8 surfaced this race as the final layer.

This file captures the verbatim commit messages and the diagnosis trail
so future readers can retrace the discovery.

## Round 7 — `fa744f0` (Sun May 24 21:28 +0800)

```
test(casting-ui): gate cross-cast SPACE on slider input-handler ready signal

Three slider-mode tests in viewer.test.tsx raced the listener-less window
between cast unmount and remount on Windows GHA — every commit, the slider
unmounts and a new cast's slider mounts; between the two, no useInput is
bound to stdin. A SPACE written into that window vanishes, leaving the
test polling forever for progress that never arrives.

Replace blind `tick()` between SPACEs with `waitForSliderReady`, which
polls until the rendered `Left Heap:` glyph has advanced past the initial
⠋ — the spinner's setInterval is installed by the same useEffect that
binds useInput, so an advanced glyph is positive proof the input handler
is wired up. The 18-split flow's final iteration skips the progress-bar
wait because committing cast 18 transitions straight to `done` and the
progress bar disappears.
```

### What's happening

- The slider is mounted in `<CastingPromptBox>` via `<SliderCastingPrompt>`,
  which uses `useSliderBounce` (a custom hook that calls `useInput`).
- Every cast commit fires the parent's onSubmit, which advances the
  per-line generator and re-mounts a fresh `<SliderCastingPrompt>` for the
  next cast. The mount key is `${lineNumber}-${castIndex}` so React
  *unmounts* the previous and *mounts* the next — the same input handler,
  but a new effect cycle.
- Between unmount and the new mount's effect-flush, no `useInput` callback
  is registered for the slider. SPACE keystrokes written in that window
  fall through to the parent viewer's `useInput`, which has its own
  handler that ignores SPACE.

### The "exploit" fix

`waitForSliderReady` polls the rendered frame for the Braille spinner
glyph in the `Left Heap:` cell. The initial glyph is `⠋` (tickCount=0);
the spinner only advances past it once the slider's `setInterval` has
fired at least once. That `setInterval` is installed by the same
`useEffect` that binds `useInput`. So an advanced glyph is positive proof
the input handler is wired up.

It works. But it's an exploit of an incidental render artefact, not a
contract.

## Round 8 — `800d3fc` (Sun May 24 21:52 +0800)

```
test(history-ui): retry first cross-state keystroke through useInput bind race

Round 8 closes the listener-bind race that was wiping out 14 tests on
Windows GHA (and 2 on Ubuntu) in `history-app.test.tsx`. After
`awaitListReady` returns, the rendered frame proves `<HistoryList>` has
committed — but its `useInput` handler is registered with Ink's stdin
dispatcher only when the post-commit `useEffect` fires on the next
macrotask. Bytes written into that gap are dispatched to whatever
`useInput` callbacks are currently registered — i.e. just the parent
`<HistoryApp>`'s Ctrl+C-only handler — and silently swallowed. On
Windows this fails 14/14; on Ubuntu it surfaces as intermittent flake.

Fixed with a `pressUntil(stdin, lastFrame, key, predicate)` helper that
writes `key` and re-writes it on each retry tick until `predicate(frame)`
turns truthy (capped at 10 retries / ~200 ms of writes). Retries are
safe because every state-transitioning key fired by this helper is
idempotent past its transition: ENTER on a row is debounced by
`onPick`'s `if (state.loading) return`; Ctrl+D is early-returned by the
modal-open branch; 'y' / 'n' / '/' on the list are unbound keys in their
post-transition view; the unmounted `<HistoryList>` simply receives no
dispatches.

Retrofitted only the 14 tests whose first cross-state keystroke after
`awaitListReady` was racing the bind — ENTER, Ctrl+D + 'y', down arrow,
'/'. Left ESC writes alone where the previous keystroke had already
walked us through a settled `useInput` (an extra ESC would call the
host's `onExit` and break the "ESC returns to list, not host" tests).
```

### What's happening

- `<HistoryApp>` is the host. It renders `<HistoryList>` once
  `scanConsultations()` resolves.
- `<HistoryList>` registers its `useInput` handler in a `useEffect` that
  runs after commit, on the next macrotask.
- The test's `awaitListReady()` predicate matched on the "Past
  Consultations" heading — proof that `<HistoryList>` had committed. But
  it had NOT proved the handler was bound. The macrotask gap was wide
  enough on Windows GHA to drop every first keystroke (14/14 failures).

### The "retry" fix

`pressUntil` writes the same key on each retry tick until the predicate
turns truthy. By the time the third or fourth retry fires, the `useEffect`
has run, the handler is bound, and the keystroke lands.

It works. But it requires every retried key to be idempotent — a
constraint that scales poorly.

## The right fix (Wave 1 follow-up)

Both rounds 7 and 8 were workarounds. The structural fix is to make the
contract explicit: the component fires a typed `onReady` callback from
inside the same `useEffect` that binds `useInput`. See SKILL.md "Fix 1"
for the pattern. The hexagram-generator landed this on three components
in Wave 1 of the post-mortem follow-up:

- `SliderInput` / `CastingPromptBox` — replaces `waitForSliderReady`.
- `HistoryList` — replaces `pressUntil` for first-cross-state keystrokes.
- `CastingStatus` — preemptive (future-proofs the next mode this race
  would have surfaced in).

Production callers pass `undefined` (no-op default); tests pass a
`vi.fn()` spy and `await waitFor(() => expect(spy).toHaveBeenCalled())`
before the first stdin.write.

## Diagnostic signals — what to grep for

When suspecting this race in a fresh codebase:

```bash
# Find all useInput call sites
grep -rEn "\buseInput\(" packages/*/src/

# Find tests with stdin.write followed by an assertion
grep -B1 -A2 "stdin.write" packages/*/tests/*.test.tsx | grep -A2 -E "(stdin\.write|tick|expect)"

# Find pressUntil-style retry helpers (workarounds already in place)
grep -rEn "pressUntil\|waitForSliderReady\|retry.*keystroke" packages/

# Find local waitFor-equivalent helpers with high tick() consumption
grep -rEn "await tick" packages/*/tests/ | wc -l
```

A workspace where the first `useInput` use predates the first `onReady`
prop adoption almost certainly has this race latent in tests. Audit
before the matrix surfaces it.
