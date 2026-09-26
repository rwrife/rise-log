# Dual-Screen Workspace Design (Issue #5)

## Status

**Design target, not a supported configuration.** Rise Log ships as an
iPhone-only app (`TARGETED_DEVICE_FAMILY = 1`) and every release build runs
the single-column flow. This document records the architectural seam through
which a future iPhone Duo workspace will land, and the contract it must keep.

## The Seam

All workspace layout routing funnels through exactly one file:

- `RiseLog/FermentWorkspaceLayout.swift` — the only app-target view that
  reads `horizontalSizeClass`, and the only file that composes the jar wall
  (`JarWallView`) with the culture timeline (`CultureDetailView`).

Routing logic itself is pure domain code in RiseKit
(`Workspace/FermentWorkspaceRouting.swift`):

| Band     | `spannedSupportEnabled` | Presentation  |
|----------|-------------------------|---------------|
| compact  | (any)                   | singleColumn  |
| spanned  | `false` (shipped)       | singleColumn  |
| spanned  | `true` (future)         | twoPane       |

The master gate `FermentWorkspaceRouting.spannedSupportEnabled` is pinned to
`false` and a Linux unit test asserts it. The CI gates
(`scripts/check_workspace_layout_seam.sh`, package test
`FermentWorkspaceRoutingTests.seamIsSoleRouter`) enforce that:

1. no other app file reads `horizontalSizeClass`,
2. the seam delegates to `FermentWorkspaceRouting.route`,
3. no source anywhere references fold/hinge/span SDK names (`FoldStatus`,
   `HingeAngle`, `SystemFold`, `spanningMode`, …) — no unreleased hardware
   API is referenced today.

## The Duo Target

When fold hardware and a released span-state SDK exist:

- **Left pane:** the jar wall stays a *persistent control surface* — the
  user always sees every jar and its derived badge while working.
- **Right pane:** the culture detail (status header, fast logging, timeline).
  Selecting a wall row swaps the detail pane in place; no navigation push.

`twoPaneLayout` in the seam file is the inert hook point that already
implements this shape, reachable only when the gate flips.

## Continuity Contract

The contract that must hold across layout rebuilds (band changes, state
restoration) **and** app backgrounding, on current iPhone hardware today:

- **Selection identity** — the selected culture id survives; encoded in
  `WorkspaceContinuityState.selectedCultureID`.
- **Per-culture scroll anchor** — the top-most visible timeline event per
  culture survives; encoded in
  `WorkspaceContinuityState.timelineAnchorByCultureID` (bounded to 64
  entries, oldest-dropped on overflow).

Both persist via `@SceneStorage` as tolerant versioned JSON
(`WorkspaceContinuityState` in RiseKit — Codable, unit-tested on Linux for
round-trip, malformed-input tolerance, pruning, and normalization).
An XCUITest journey (`testSelectionAndScrollAnchorSurviveBackgrounding`)
backgrounds/foregrounds the app mid-detail and asserts the timeline row it
scrolled to is still visible — simulator evidence only.

## Migration Path

When the fold SDK matures:

1. Replace the `horizontalSizeClass`-based band mapping in the seam file with
   the released span/fold-state API (the ONLY change to layout code).
2. Flip `FermentWorkspaceRouting.spannedSupportEnabled` to `true` — gated on
   real hardware evidence, never on simulator emulation.
3. Re-run the continuity XCUITest on a physical fold device before claiming
   continuity on the new hardware class.

Until then the app's device policy is unchanged: **iPhone-only, and iPad
support remains an explicit opt-in directive, not a side effect of this
seam.**
