---
name: package-public-api
description: |
  Define each package's public API via explicit `exports` entries (concrete
  files, never barrels), and use `package.json` `imports` (Node subpath
  imports) for in-package code-sharing instead of `tsconfig.json` `paths`.
  Triggers on: package.json exports, package.json imports, subpath imports
  (#src/*, #components/*), tsconfig paths aliases, public API surface,
  deep imports from another package, "import from folder" patterns. Use
  when adding files that other packages will consume, changing `exports`
  or `main`/`module`, or wiring up internal aliases inside a package.
---

# Package Public API & Subpath Imports

A package has two distinct surfaces:

- **`exports`** (`package.json`) — the **public** API consumers may
  import.
- **`imports`** (`package.json`) — **internal** aliases for code-sharing
  *inside* the same package.

Keep them separate; do not use `tsconfig.json` `paths` for either.

---

## `exports` — the public surface

### Rules

- **Public vs private**
  - Expose only what is intentionally part of the package's API.
  - Keep helpers and implementation details private (unexported, or only
    accessible via internal `imports` paths).

- **Concrete entries, no barrels**
  - List concrete files or subpaths in `exports`. Do not use
    `index.ts`/`index.js` barrels.
  - Prefer named subpaths over a single root `"."` export when a package
    has multiple entry concepts.
  - ✅ `"exports": { "./foo.ts": "./src/foo.ts", "./components/button.tsx":
    "./src/components/button.tsx" }`
  - ❌ `"exports": { ".": "./src/index.ts" }` where `index.ts` is just
    re-exports.

- **Consumers import from declared entrypoints only**
  - ✅ `import { Foo } from 'pkg-name/utils/foo.ts';`
  - ❌ `import { Foo } from 'pkg-name/dist/foo';` — never `dist`/`src`
    internals.
  - ❌ `import { Foo } from 'pkg-name/#src/private.ts';` — internal
    `imports` aliases are not public API.

- **Keep `exports` in sync with files**
  - Update `exports` when moving or renaming public files.
  - Remove stale exports when endpoints are deleted.

See [[no-barrel-files]] for the rationale behind banning barrel files.

---

## `imports` — internal subpath aliases

Node.js
[subpath imports](https://nodejs.org/api/packages.html#subpath-imports)
are the go-to mechanism for within-package linking.

### Rules

- **Define internal aliases in `package.json` `imports`**
  - `"#src/*": "./src/*"`, `"#components/*": "./src/components/*"`,
    `"#utils/*": "./src/utils/*"`, etc.
  - Apps may add more for structure: `#app/*`, `#hooks/*`, `#contexts/*`,
    `#server/*`, `#types/*`, `#schemas/*`, `#constants/*`, `#assets/*`.
  - Prefer a small, stable set of aliases over one-off entries.

- **Use the alias in code**
  - ✅ `import { Foo } from '#components/foo.tsx';`
  - ✅ `import { bar } from '#utils/bar.ts';`
  - ❌ `import { Foo } from '../../../components/foo.tsx';` when
    `#components/*` is defined.

- **Internal stays internal**
  - Another package must never import via your `#…` aliases. They resolve
    only inside the owning package.

- **Don't proliferate one-off aliases**
  - If a path can be covered by an existing alias, use it. Add a new
    alias only when it represents a stable structural concept.

---

## Why not `tsconfig.json` `paths`

We **don't** use TypeScript path aliases (`"@/*": ["src/*"]`,
`"@app/*"`, etc.) for within-package linking. Reasons:

- TypeScript paths are **not native** to Node or browsers; they require
  the TS compiler or a bundler to rewrite imports at build time. In a
  large monorepo this is **extremely slow** and adds tooling churn.
- Node subpath imports (`package.json` `imports`) are **native** and
  resolve at runtime without a rewrite step. TypeScript also resolves
  `#…` natively when the package uses `imports`.

See [Why I don't like path aliases in
TypeScript](https://dev.to/bennycode/why-i-dont-like-path-aliases-in-typescript-2b2a).

The source of truth for internal aliases is always `package.json`
`imports`; do not add equivalent `paths` in `tsconfig.json`.

---

## Quick checks

- [ ] `exports` lists concrete file paths (no `index.ts` barrels).
- [ ] Cross-package imports go through declared `exports` subpaths
      only — no `dist/`, no `src/` internals, no `#…` aliases of other
      packages.
- [ ] In-package imports use the package's own `#…` aliases instead of
      deep relative paths.
- [ ] `tsconfig.json` does not contain `paths` entries shadowing or
      duplicating internal `imports`.

## Related

- [[no-barrel-files]] — `exports` and `imports` must resolve to concrete
  files, not directory barrels.
- [[vertical-code-structure]] — package boundaries are the cross-package
  expression of vertical structure; explicit `exports` keeps those
  boundaries enforceable.
