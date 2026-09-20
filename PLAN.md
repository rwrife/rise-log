# Rise Log — PLAN

## Scope

MVP is a single-user, local-only iPhone app: manage named cultures, append events to per-culture ledgers, and display deterministic derived status. Dual-screen (iPhone Duo) is a documented design target behind one layout seam; it is not built today because native fold APIs do not exist in the shipping SDK.

### Explicitly out of scope (MVP)

- Recipe management, baker's-math suites, formula scaling.
- Food-safety, spoilage, or health determinations of any kind.
- Network features: sync, sharing feeds, price/weather lookup, remote notifications.
- Android; native iPad layouts (`TARGETED_DEVICE_FAMILY = 1` everywhere; opt-in only to change).
- Cross-platform frameworks (Flutter/RN/Expo/KMP/MAUI/Unity) — prohibited.

## Architecture

```
RiseLog (iOS app, SwiftUI)
├── Views            # jar wall, culture detail, event capture, settings
├── FermentWorkspaceLayout   # single dual-screen migration seam (today: single-pane collapse)
├── RiseKit (local Swift package, pure Swift, no UI/network imports)
│   ├── Domain       # Culture, CultureType, Event (feed/rise-check/bottle/bake/discard/note/split), Lineage
│   ├── Derivation   # status engine: hours-since-feed, rise-phase band, ferment-days, due-window; Unknown never coerced to safe
│   └── BackupCodec  # versioned JSON archive + CSV ledger encode/decode (pure, testable)
├── Store            # GRDB (SQLite) migrations, append-only event table, culture table
└── Notifications    # UNUserNotificationCenter local reminders per culture cadence
```

Rationale:
- **Append-only event ledger** makes every displayed number a pure function of ledger + clock → trivially testable, honestly reconstructable, and immune to drift between cached "status" fields.
- **Pure-Swift RiseKit** runs on Linux CI (swift-testing) so derivation/backup semantics are gated even where Xcode can't run; Xcode CI adds build/UI gates on macOS runners.
- **GRDB** mirrors prior tool-lab apps (proven migrations story, strong test ergonomics).

## Technology choices

| Choice | Rationale |
|---|---|
| Swift 6, SwiftUI | user directive: native only; strict concurrency default |
| iOS 26 SDK (Xcode 26.0.1 / 17A400 pinned in toolchain.json) | required floor; matches fleet convention |
| GRDB/SQLite | relational ledger, migrations, deterministic queries |
| swift-testing | fleet convention; runs on Linux for RiseKit |
| App Store Connect API (via repo secrets) | TestFlight upload without fastlane/cloud accounts |

Bundle ID: `com.infinityball.riselog` — `com.infinityball.` prefix is mandatory; never any other prefix in any target, extension, or CI signing config.

## Milestones & dependency order

1. **Skeleton & CI** (no deps): Xcode project, RiseKit package, pinned-toolchain macOS CI job, zero-network gate, iPhone-only grep guard + post-build `UIDeviceFamily == [1]` check, Linux job for RiseKit.
2. **Domain + derivation** (1): RiseKit events, status engine, unknown-safe semantics, lineage DAG with cycle rejection — swift-testing suite.
3. **Store** (2): GRDB schema, append-only enforcement, migration 1, store tests.
4. **Core workflow UI** (3): create culture, log Feed/Rise-check/Bottle/Bake, jar wall with badges, culture timeline; accessibility pass.
5. **Duo seam + polish** (4): `FermentWorkspaceLayout` collapse implementation, selection/scroll continuity scaffolding, photo notes, per-culture local reminders.
6. **Backup/export + privacy gate** (3): JSON archive preview/restore, CSV export, documented schema, expanded network allowlist audit = empty.
7. **Release** (all): signing, archive, TestFlight upload, processed-build evidence.

## Testing strategy

- **Linux CI:** RiseKit unit tests — derivation math (DST-safe calendar handling, unknown propagation), ledger invariants, lineage cycle rejection, backup codec round-trips.
- **macOS CI:** exact-pinned Xcode build, XCUITest happy path (create → feed → badge updates), store migration tests, zero-network gate, iPhone-only enforcement (source grep + built Info.plist inspection).
- **Manual/device gates:** real-device logging feel, VoiceOver pass, notification timing on hardware — recorded as evidence, never assumed.
- No claim of "tested" for anything not actually executed; simulator results are labeled simulator results.

## Packaging / distribution

Ad Hoc → TestFlight via ASC API secrets → phased App Store release (user decision). Release acceptance requires a processed build and real screenshots; Linux-only evidence never substitutes.

## Risks

| Risk | Mitigation |
|---|---|
| "Ready/safe" badge misread as food-safety advice | unknown-safe rendering, README + in-app disclaimer, wording review gate |
| Fold SDK arrives with different capability model | all adaptation isolated in `FermentWorkspaceLayout` |
| Notification cadence spam | per-culture opt-in, default off, quiet-day handling in cadence model |
| iOS CI simctl flakiness (fleet-known) | bounded retries, log evidence, no fake greens |

## Non-goals

Stated twice deliberately: no health/safety claims, no network MVP features, no iPad/Android without explicit opt-in, no cross-platform frameworks, no placeholder completion — every acceptance criterion needs real tool output.
