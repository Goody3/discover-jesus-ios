# Discover Jesus iOS - Component Attribute Standardization Plan

Date: November 1, 2026

## Goal
Standardize component attributes so backend payloads are easier to validate, the iOS renderer is simpler, and future components can be added with minimal branching.

## Recommended Standardization

- Use one canonical payload shape for every section:
  - `id`
  - `component`
  - `content`
  - `attributes`
  - `actions`
  - `layout`
  - `meta`
- Keep `legacyType`/`legacyProps` as migration inputs only (not long-term renderer-facing fields).
- Replace overloaded keys like `attribute` with explicit names (`level`, `ordered`, `variant`, etc.).
- Normalize enum-style values to lowercase (`h1`, `h2`, `h3`).

## Canonical Cross-Component Contract

### `component`
Canonical type such as:
- `text`
- `button`
- `list`
- `image`
- `bibleVerse`
- `navBar`

### `content`
User-facing payload (text/media/list data):
- `text`
- `title`
- `items`
- `url`
- `alt`
- `reference`

### `attributes`
Visual/semantic options:
- `level`
- `ordered`
- `size`
- `variant`
- `fit`

### `actions`
Behavior definitions:
- `primary` (navigate/open URL/other)

### `layout`
Presentation hints:
- spacing
- alignment
- width/margins

### `meta`
Diagnostics/source:
- `sourceComponentId`
- `legacyType`
- transform trace fields

## Field-Level Standardization (Current -> Target)

- `value` and `legacyProps.text` -> `content.text`
- `src` and `legacyProps.url` -> `content.url`
- `target` and `action.pageId` -> `actions.primary`
- `headerAttribute` and `headerLevel` -> `attributes.level` (`h1|h2|h3`)
- list detection via `style.role == "list"` -> `component: "list"`
- list ordered detection via mixed fields -> `attributes.ordered: boolean`

## Recommended Per-Component Schemas

### Header
- `component`: `header`
- `content.text`
- `attributes.level`: `h1 | h2 | h3`

### Text
- `component`: `text`
- `content.text`
- `attributes.size` (optional): `small | medium | large`

### Button / NBButton
- `component`: `button`
- `content.text`
- `attributes.variant` (optional): `primary | secondary | link`
- `actions.primary`: `{ "type": "navigate", "pageId": "..." }`

### List
- `component`: `list`
- `content.items`: `[string]`
- `attributes.ordered`: `boolean`
- `content.title` (optional)

### Image / Media
- `component`: `image`
- `content.url`
- `content.alt`
- `attributes.fit` (optional): `contain | cover`

### BibleVerse
- `component`: `bibleVerse`
- `content.text`
- `content.reference`
- `attributes.translation` (e.g. `esv`)
- `layout.marginPercent` (for true portable ~10% margins)

## Deprecations to Plan

- Deprecate `legacyProps.attribute` (ambiguous meaning across component types).
- Deprecate inferring component identity from `style.role` when canonical `component` exists.
- Deprecate renderer dependency on `legacyType` once backend emits canonical `component` consistently.

## Migration Strategy (Low Risk)

### Phase 1 - Dual-Write / Dual-Read
- Backend emits both legacy and canonical fields.
- iOS reads canonical first; falls back to legacy.

### Phase 2 - Validation
- Add schema validation in backend CI for canonical payload contract.
- Add payload fixtures for each component shape.

### Phase 3 - App Cleanup
- Remove legacy fallback paths from renderer once coverage is complete.
- Keep telemetry for unknown component types.

### Phase 4 - Backend Cleanup
- Remove legacy fields from API responses.
- Version API payload contract.

## Release-Focused Checklist

- [ ] Canonical schema agreed between backend/web/iOS
- [ ] Canonical fields emitted for all currently supported components
- [ ] iOS renderer reads canonical-first for all components
- [ ] Unit tests cover decode and rendering decisions
- [ ] Unknown-component telemetry active
- [ ] Legacy fields removed or formally sunset

## Summary

The current app architecture is already strong for iterative rendering. The highest-value next step is a canonical contract that removes attribute ambiguity and reduces renderer branching. This will make future releases safer, faster, and easier to test.
