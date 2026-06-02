---
name: no-barrel-files
description: |
  Do not use barrel files (index.ts/index.js that only re-export from
  siblings). Import from concrete modules; expose package public API via
  explicit `exports` entries pointing at real files. Triggers on:
  index.ts re-exports, barrel files, circular imports, tree-shaking,
  build/dev performance, "import from folder" patterns, public API
  surfaces, package.json exports pointing at index files. Use when
  reorganizing files, creating an index.ts to "tidy up imports", or
  configuring a package's public API.
---

# No Barrel Files

A **barrel file** is one that does nothing but re-export from other files
(commonly `index.ts` / `index.js`). Don't use them: import from concrete
modules, and expose public API via explicit `exports` in `package.json`.

## Why

- **Circular imports** — barrels encourage "import from the folder," which
  easily creates cycles when a file in that folder imports from the
  barrel. See [TkDodo – Please Stop Using Barrel
  Files](https://tkdodo.eu/blog/please-stop-using-barrel-files) and [The
  index.ts
  dilemma](https://krishnavadlamudi44.medium.com/the-index-ts-dilemma-balancing-convenience-and-performance-in-typescript-projects-85e9dd4fc18f).
- **Dev/build performance** — importing from a barrel loads every
  re-exported module. In large apps this balloons module count and slows
  dev/build. Next.js
  [optimizePackageImports](https://nextjs.org/docs/app/api-reference/config/next-config-js/optimizePackageImports)
  helps only for *external* packages; internal barrels still hurt. See
  also [Why I don't use barrel files (index.ts) in
  2026](https://javascript.plainenglish.io/why-i-dont-use-barrel-files-index-ts-in-2026-d7e04b41af80).
- **Explicit over convenient** — concrete imports and explicit `exports`
  make dependencies and public API clear, and avoid accidental re-export
  chains.

## Rules

- **Do not create barrel files**
  - No `index.ts` / `index.js` that only re-exports from siblings or child
    files.
  - No "import from directory" pattern (e.g. `from '@/components/tabs'`
    resolving to `tabs/index.ts`).

- **Import from concrete modules**
  - Within a package: import the exact file (e.g.
    `#components/tabs/tab-list.tsx`, `#utils/format-date.ts`).
  - Across packages: import the explicit exported subpath (e.g.
    `pkg/tab-list.tsx`), not a directory barrel.

- **Expose public API via `exports` only**
  - List concrete files or subpaths in `package.json` `exports`.
  - Avoid a root `"."` export that points at an `index.ts` barrel; prefer
    named subpaths (`"./foo.ts": "./src/foo.ts"`).

- **Single-module packages**
  - The one acceptable "single entry" is when a package has one main
    module and that module is the **real implementation file**, not a
    re-export barrel.

## Do / Don't examples

**Within a package**
- ✅ `import { TabList } from '#components/tabs/tab-list.tsx';`
- ❌ Add `tabs/index.ts` that re-exports `tab-list` and `tab-panel`, then
  `import { TabList } from '#components/tabs';`

**Package public API**
- ✅ `"exports": { "./tab-list.tsx": "./src/tabs/tab-list.tsx",
  "./tab-panel.tsx": "./src/tabs/tab-panel.tsx" }`
- ❌ `"exports": { ".": "./src/index.ts" }` where `index.ts` only
  re-exports.

**Adding a new component or util**
- ✅ Add `my-thing.tsx` and import it as `#components/my-thing.tsx`. Add
  an `exports` entry if it's public.
- ❌ Add `my-thing.tsx` and also add/update `index.ts` to re-export it
  "so we can import from the folder."

## Related

- [[package-public-api]] — `exports` entries must point at concrete
  modules; `imports` subpaths target concrete files, not directory
  barrels.
- [[vertical-code-structure]] — colocate by what changes together; don't
  add `index.ts` to "tidy" a vertical.
