# Cross-platform environment variables — recipe book

This is the full menu of ways to get a variable to a Node test process, with
explicit notes on which Windows-friendly and which not.

## The taxonomy

There are four places an env var can come from. Knowing which is which is
half the battle:

| Origin | Reached by | Windows-safe? |
|---|---|---|
| (a) Process is launched with var already set | OS env / parent shell / CI workflow `env:` | yes |
| (b) Script syntax sets var before exec | `FOO=1 cmd` (POSIX), `cross-env FOO=1 cmd` | only `cross-env` is portable |
| (c) `process.env.FOO = '1'` at top of test | `globalSetup`, `setupFiles`, top-level assignment | yes, but **timing risk** for libraries that read at import time |
| (d) Test runner config | vitest `test.env`, jest `globals` | yes, but **same timing risk** as (c) |

If a library reads the var lazily (inside a function that runs after the test
starts), (c)/(d) are fine. If the library reads it eagerly (at module-import
time, like `chalk` / `supports-color`), only (a) and (b) work — and on
Windows, only `(a)` and `cross-env`-flavoured `(b)`.

## Recipe 1 — `cross-env` in `package.json`

The default choice for monorepo packages where you want `pnpm run test` to
work identically on every developer's machine.

```bash
pnpm add -wD cross-env
```

```json
{
  "scripts": {
    "test": "cross-env FORCE_COLOR=1 vitest run --passWithNoTests",
    "test:debug": "cross-env DEBUG=app:* vitest run"
  }
}
```

Multiple variables on one line:

```json
{
  "scripts": {
    "test": "cross-env FORCE_COLOR=1 TZ=UTC LANG=C vitest run"
  }
}
```

`cross-env` itself is unmaintained but stable — there's no churn in the
problem it solves. `cross-env-shell` is the variant for when the right-hand
side is itself a shell snippet (rare).

## Recipe 2 — GitHub Actions `env:` block

Best when the variable is only needed in CI:

```yaml
- name: Test
  run: pnpm run test
  env:
    FORCE_COLOR: '1'
    TZ: 'UTC'
```

`env:` can be at the step, job, or workflow level — choose the narrowest
scope that covers your use case. Workflow-level is fine for things that apply
everywhere (TZ, LANG); step-level is better for one-shot debugging vars.

Trade-off vs. `cross-env`: the var is *only* set in CI. Running the script
locally won't have it. That's good if the var only matters in CI (TZ pinning
to detect timezone bugs); it's bad if the test genuinely needs it
everywhere (FORCE_COLOR for ANSI assertions).

## Recipe 3 — `dotenv-cli` for shared `.env` files

When several scripts share a long list of vars:

```bash
pnpm add -wD dotenv-cli
```

```json
{
  "scripts": {
    "test": "dotenv -e .env.test -- vitest run"
  }
}
```

`.env.test`:

```
FORCE_COLOR=1
TZ=UTC
LANG=C
```

Portable, no per-script noise. Watch: don't commit secrets to `.env.test`;
it should hold portability vars only. Treat `.env.local` (developer-specific)
as ignored, `.env.test` (committed) as a fixture.

## Recipe 4 — vitest `test.env`

```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config'
export default defineConfig({
  test: {
    env: {
      MY_FEATURE_FLAG: 'true',
    },
  },
})
```

**Use this for variables your own code reads**, not for libraries that probe
`process.env` at import time. The reason: vitest sets these *inside* the
worker after Vite has already evaluated some modules. Anything that read the
var during import has already seen `undefined`.

**Known to be timing-sensitive in this layer**:

- `FORCE_COLOR` / `NO_COLOR` (chalk, supports-color, kleur)
- `DEBUG` (debug module reads at first call, *but* per-namespace caching means
  changes mid-test may not take effect)
- `TZ` (Node reads at process start to build the Date prototype — `test.env`
  is too late)
- `NODE_ENV` (Webpack/Vite/many libs branch on this at boot)

**Safe in this layer**:

- Application feature flags read inside the test
- Mock-server URLs
- Anything you control

## Recipe 5 — `globalSetup` for things that genuinely must be runtime

Sometimes a variable depends on something computed at test-launch (a port
number, a temp dir). Use `globalSetup`:

```ts
// vitest.globalSetup.ts
import getPort from 'get-port'

export default async function setup() {
  const port = await getPort()
  process.env.MOCK_SERVER_URL = `http://127.0.0.1:${port}`
  return async () => { /* teardown */ }
}
```

```ts
// vitest.config.ts
export default defineConfig({
  test: { globalSetup: ['./vitest.globalSetup.ts'] },
})
```

Same caveat: this runs *inside the worker*, so libraries probing at module
init are still too late. It's fine for runtime variables.

## Recipe 6 — Turborepo / monorepo: declare in `turbo.json`

If Turbo is in the picture and a task's behaviour depends on an env var, you
must declare it for cache invalidation:

```json
{
  "tasks": {
    "test": {
      "env": ["FORCE_COLOR", "TZ", "CI"]
    }
  }
}
```

This doesn't *set* the variable — it tells Turbo that the task's output
depends on the variable's value, so the cache key changes when it changes.
Without this, Turbo can serve a cached pass from a previous run where the
variable was different. Common gotcha when debugging matrix flakes: you
"fix" the env, run again, and Turbo replays the old (broken) output.

Combine with one of the actual *setting* recipes above.

## Anti-recipes — what doesn't work portably

### `FOO=1 cmd` directly in `scripts`

```json
{ "scripts": { "test": "FORCE_COLOR=1 vitest run" } }
```

POSIX-only. Windows CMD literally tries to run a program called `FORCE_COLOR=1`
and fails with `'FORCE_COLOR' is not recognized as an internal or external
command`. Every Windows CI job dies here before vitest loads.

### `set FOO=1 && cmd` directly in `scripts`

```json
{ "scripts": { "test": "set FORCE_COLOR=1 && vitest run" } }
```

Windows-only. POSIX `sh` would set `FOO` as a local variable but not export
it, so `vitest` wouldn't see it.

### `&` chaining (Windows-only)

```json
{ "scripts": { "test": "set FORCE_COLOR=1 & vitest run" } }
```

CMD-specific "and-then" operator. Not POSIX.

### `:` (POSIX no-op) as a wrapper

```json
{ "scripts": { "test": ": ${FOO:=1}; vitest run" } }
```

POSIX-only — `:` is a builtin. Windows CMD doesn't have it.

### Top-of-test `process.env` assignment for color libraries

```ts
// THIS WILL NOT WORK
process.env.FORCE_COLOR = '1'
import { render } from 'ink-testing-library'
```

Even though it looks like it runs first, `import` is hoisted in ESM/TS —
`ink-testing-library` and its dependency chain (chalk, supports-color) all
evaluate before the assignment. The variable lands too late.

If you absolutely must do it in code, use a *separate* setup file referenced
by `setupFiles`, *and* know that this is still timing-sensitive — some libs
will still race you.

## How to pick

```
Need it in CI only? → GitHub Actions env: block
Need it locally too?
  Reads at import time (color libs, TZ, NODE_ENV)? → cross-env in package.json
  Reads at runtime?                                → vitest test.env or top-of-test
Many vars across many scripts?                   → dotenv-cli + .env.test
Value computed at launch (ports, paths)?         → globalSetup
Turborepo in the picture?                        → add to turbo.json's env array
```

## Verifying the fix

The trap (also called out in the `ansi-color-piping` skill): if `FORCE_COLOR`
is already set in your shell, in CI, or in some agent environment, *every*
run is colour-on no matter what your change does. You can confirm a fix that
does nothing or dismiss a real fix as inert.

```bash
# Reproduce a clean, non-TTY, non-cached run
env -u FORCE_COLOR -u NO_COLOR -u CI pnpm run test | cat
```

For Windows-specific verification, the equivalent in PowerShell:

```powershell
$env:FORCE_COLOR=$null; $env:NO_COLOR=$null; pnpm run test | Out-String
```

Or in CMD:

```cmd
set FORCE_COLOR=
set NO_COLOR=
pnpm run test
```

(An empty `set FOO=` clears the variable in CMD.)

The A/B is: the failure should reproduce with the variable unset *and* the
fix in place, and pass with the fix and the verification command above.
