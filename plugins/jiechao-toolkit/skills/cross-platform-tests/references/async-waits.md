# Async waits without races

Most "flaky on CI, fine locally" tests have a single root cause: somewhere
the test waits a *fixed amount of time* for something asynchronous to finish.
On the developer's machine the fixed amount is long enough; on a slow runner
it isn't.

The cure is to wait for the *condition*, not for a clock.

## The taxonomy of waits

| Pattern | What it flushes | Bounded? | When to use |
|---|---|---|---|
| `await Promise.resolve()` | one microtask | yes (1) | almost never alone |
| `await new Promise(r => setImmediate(r))` | one macrotask boundary | yes (1) | "let I/O complete one step" — still racy |
| `await new Promise(r => setTimeout(r, 0))` | one macrotask boundary | yes (1) | same as setImmediate |
| `await new Promise(r => setTimeout(r, 60))` | wall clock ms | no | **never** as a sync primitive |
| `vi.runAllTimersAsync()` | all *fake* timers | yes | works only if you also `vi.useFakeTimers()` |
| `waitFor(predicate)` | until predicate holds | yes (timeout) | the right answer |

Lines marked "bounded? yes (1)" finish in one tick of the event loop. A chain
of async work (`useEffect` → `import()` → `fs.readFile` → `setState` →
re-render) has *N* ticks where N depends on whoever's scheduling. No fixed
number is correct.

`waitFor` doesn't pretend to know N. It checks, gives up the loop, checks
again, and stops when the condition is true or the timeout elapses.

## The minimal `waitFor`

```ts
// tests/utils/wait-for.ts
export async function waitFor<T>(
  predicate: () => T | Promise<T>,
  { timeoutMs = 2000, intervalMs = 10 } = {},
): Promise<T> {
  const deadline = Date.now() + timeoutMs
  let lastError: unknown
  for (;;) {
    try {
      const value = await predicate()
      if (value !== undefined && value !== false) return value
    } catch (error) {
      lastError = error
    }
    if (Date.now() >= deadline) {
      throw lastError ?? new Error(`waitFor timed out after ${timeoutMs}ms`)
    }
    await new Promise((r) => setTimeout(r, intervalMs))
  }
}
```

Two usage shapes:

**(a) Wrap an `expect`** — the assertion throws, `waitFor` catches and
retries, and when the assertion finally holds it returns `undefined` (which
counts as "ok" because no error was thrown). The trick is the function passed
to `waitFor` ends with the assertion, no explicit return:

```ts
await waitFor(() => {
  expect(stripAnsi(lastFrame() ?? '')).toContain('Consultation · loaded')
})
```

This is the most readable shape. The "what we're waiting for" *is* the
assertion. No duplicated condition.

**(b) Return a truthy value** — for cases where you want the matched data:

```ts
const row = await waitFor(() => {
  const found = listRows().find((r) => r.id === expectedId)
  if (!found) throw new Error('row not yet visible')
  return found
})
```

## Why fixed delays seem to work

A constant like `await tick(60)` is the seductive shortcut: it works on the
author's machine, the test goes green, the PR merges. The problem only shows
up later, when the test runs on a machine where 60ms isn't enough.

The numerical reality on a typical macOS dev box:

| Step | Time on M-series laptop |
|---|---|
| React render | 0.5–2ms |
| `useEffect` cleanup + new effect | 1–3ms |
| `import('./module.ts')` | 2–8ms (cached: <1ms) |
| `fs.readFile('small.md')` | 1–4ms |
| Re-render after `setState` | 0.5–2ms |
| **Total realistic budget** | **5–15ms** |

On a `ubuntu-latest` runner under load, the same chain is 30–500ms. Sometimes
2 seconds. The 60ms constant was fine for the first measurement, terrible for
the second. There is no constant that's right for both.

The same logic kills `await tick(500)` and `await tick(1000)`: you've made
the suite slow without making it correct.

## Patterns that need real time

Some things genuinely depend on the wall clock. For those, use fake timers
so the test controls the clock:

```ts
import { vi } from 'vitest'

beforeEach(() => vi.useFakeTimers())
afterEach(() => vi.useRealTimers())

it('debounced search fires after 300ms', async () => {
  const { result } = renderHook(() => useDebouncedSearch())
  result.current.search('q')

  await vi.advanceTimersByTimeAsync(299)
  expect(searchSpy).not.toHaveBeenCalled()

  await vi.advanceTimersByTimeAsync(1)
  expect(searchSpy).toHaveBeenCalledWith('q')
})
```

The combination of fake timers + `advanceTimersByTimeAsync` lets you advance
the clock by an exact amount and *also* flush microtasks scheduled within
that window. It's the right tool for "after N ms, X happens" assertions.

**The catch**: if your component also does real I/O (`fs.readFile`,
network), fake timers don't help — I/O completes on its own schedule. In
that case pair real I/O `waitFor`s with fake-timer advances for the time
parts.

## Anti-patterns

### `await new Promise(r => setTimeout(r, 0))` to "flush microtasks"

This flushes *exactly one* macrotask boundary. A chain of `.then()`s might
span many. The only time `setTimeout(0)` is correct is when you have a
specific known structure that finishes in exactly that boundary.

### `await Promise.resolve()` × N

```ts
await Promise.resolve()
await Promise.resolve()
await Promise.resolve()
```

You see this in older codebases — flush the microtask queue 3× to "be sure."
It's a worse version of `await tick(0)`: still bounded, still racy, and now
also confusing. Replace with `waitFor(condition)`.

### `setTimeout` in the test body itself

```ts
setTimeout(() => {
  expect(frame).toContain('foo')
  done()  // mocha-style
}, 100)
```

The test reports pass before the `setTimeout` fires if `done` isn't called,
and the timer can fire after the test has been torn down. Use `await` and
`waitFor`.

### "Just rerun on flake"

CI re-run buttons are an admission of a race condition. They make the
problem invisible without fixing it. If a test needs a rerun to pass, treat
it as broken.

## Diagnosing a flaky test

If you can't immediately see where the race is:

1. **Repeat locally with throttling.** `pnpm test --repeat 50` to amplify the
   race, plus a CPU/IO throttle (`taskset -c 0`, Docker `--cpus 0.25`) to
   simulate a slow runner. If it flakes locally, you can iterate.
2. **Add a `waitFor` around the first thing the test checks.** If it
   stabilises, the race was on that boundary. If a later assertion now
   flakes, push the `waitFor` later.
3. **Look at the failure frame.** If the rendered output contains a
   placeholder (`Loading…`, `…`, an empty cell), the test ran while the
   async chain was mid-flight — you need to wait for the post-load state.
4. **Time the chain.** Add `console.time` / `console.timeEnd` around the
   suspect operation. If it's 300ms locally on the slowest run, your CI is
   probably seeing 1–3s.

## ink-testing-library specifics

`lastFrame()` returns whatever the renderer has output up to now. After
`stdin.write(ENTER)`, the renderer has to:

1. Receive the key event (event loop tick)
2. Run the component's input handler (synchronous)
3. Trigger any `useEffect` it scheduled (next tick)
4. Run async work inside that effect (multiple ticks)
5. Call `setState` (next tick after work completes)
6. Re-render (next tick after `setState` batches)
7. Emit the new frame (next tick)

A single `await tick()` between `stdin.write` and `lastFrame()` covers tick
1 only. Use `waitFor` to poll `lastFrame()` until the expected text appears.

A worked example from the user's project:

```ts
// Before — flaky on Ubuntu CI
const { lastFrame, stdin } = render(<HistoryApp dir={tmpDir} />)
await tick()
stdin.write(ENTER)
await tick()
expect(stripAnsi(lastFrame() ?? '')).toContain('Consultation · loaded')

// After — passes on every runner
const { lastFrame, stdin } = render(<HistoryApp dir={tmpDir} />)
await waitFor(() => {
  expect(stripAnsi(lastFrame() ?? '')).toContain('Past Consultations')
})
stdin.write(ENTER)
await waitFor(() => {
  expect(stripAnsi(lastFrame() ?? '')).toContain('Consultation · loaded')
})
```

The post-`render` `waitFor` ensures the directory scan completed before
`ENTER` is pressed (otherwise pressing Enter on an empty list is a no-op).
The post-`ENTER` `waitFor` ensures the file load completed before the
assertion.

If the test was already calling `tick()` for legitimate reasons
(animations advancing one frame), keep the deliberate `tick()` and wrap the
condition-dependent assertions in `waitFor`.
