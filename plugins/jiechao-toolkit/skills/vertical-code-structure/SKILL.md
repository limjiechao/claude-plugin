---
name: vertical-code-structure
description: |
  Group code by what changes together (vertical slices: domain / feature /
  functionality), not by file type (components/hooks/utils). Triggers on:
  folder structure, refactoring directories, feature ownership, cohesion,
  coupling, monorepo vertical packages, horizontal layout anti-pattern,
  colocation, where-to-put-this-file. Use when structuring or refactoring
  folders inside a package, splitting features across packages, reviewing
  import graphs, or when the user mentions horizontal layouts, feature
  ownership, or "shared/common" buckets growing unbounded.
---

# Vertical Code Structure

## Why

Horizontal folders (`components/`, `hooks/`, `utils/`) optimize for file
*kind*, not behavior. That scatters what changes together, hides boundaries,
and makes ownership unclear.

Vertical structure does the opposite: **low coupling, high cohesion**, easier
navigation, and clearer dependencies — within a package and across packages
at scale.

Further reading:
[The Vertical Codebase](https://tkdodo.eu/blog/the-vertical-codebase).

---

## Nomenclature

"Vertical" covers anything from:

- **domain** — tied to business requirements or problem space
- **feature** — user-visible capability within a domain or across domains
- **functionality** — capability provided by code, independent of user
  visibility or business boundaries

---

## How to structure

### 1. Slice the vertical by what it does, not what it is

Ask: **what distinct, singular behavior does this code bring?** Put
everything that implements that slice in one place — UI, hooks, types,
helpers, server actions, schema, constants, queries — regardless of "what
kind" of file it is.

Good vertical names reflect *what the slice does* (`checkout/`,
`page-filters/`, `profiling/`), not "shared" or "common" unless that truly
is a single cohesive domain/feature/functionality.

### 2. Colocate by default

Keep types, hooks, and helpers next to the component or route they serve.
Extract to another file in the **same vertical** when readability demands
it — not to a top-level `utils/` just because it is "not a component."

NEVER separate code by type.

### 3. When code is reused: promote it to its own vertical

Cross-cutting UI or behavior used in multiple places is often **its own**
vertical (e.g. a design-system slice or a `PageFilters` domain), not random
files in a giant shared bucket. If reuse is real and stable, **then** lift
it; avoid premature abstraction.

### 4. Across packages: verticals become boundaries

In a monorepo, a vertical can map to a package (or a clearly named subtree
with the same discipline). Treat **package `exports`** as the public
contract: consumers import published entrypoints only; internals stay
private.

- Prefer **narrow, intentional exports** over huge barrels (see
  [[no-barrel-files]] and [[package-public-api]]).
- Enforce allowed dependencies (layering, no deep imports) per repo rules.

**Exception:** when a technical/functional layer is by its nature highly
reusable across many vertical packages or apps (e.g. shared config, shared
utility helpers, generated server-function bindings), a thin
type-or-functionality-layered package is acceptable.

### 5. Anti-pattern: the "everything dump" package

A package that mixes unrelated features, helpers, and UI with weak
boundaries raises coupling, obscures ownership, and makes changes risky.
**Do not grow new grab-bag packages.** Extract stable pieces into focused
packages with explicit exports.

### 6. Hard parts (expect them)

- **Naming verticals** is judgment, not a rigid rule: start from
  routes/pages or product areas; split when a subtree is large or shared
  widely.
- **Private vs shared** needs team communication; duplicated one-off
  helpers across verticals are often a sign exports or a shared vertical
  are missing.

---

## Quick checks

- [ ] Vertical structure follows **change**, not **code-type**.
- [ ] Verticals define **ownership and boundaries**.
- [ ] New code lives under a **domain folder**, not only under type-based
      top-level folders.
- [ ] Shared code is either a **deliberate small package/export** or stays
      inside the vertical until reuse is proven.
- [ ] Cross-package use goes through **explicit package exports**, not deep
      paths into another package's internals.
- [ ] Never expand catch-all packages; split by cohesive vertical instead.
