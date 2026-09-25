# Rise Log

**Pitch:** Local-first iPhone log for sourdough starters and home ferments: feeding ledgers, rise-phase status, bottle/bake events, and a glanceable jar wall — no accounts, no cloud.

## Overview

Rise Log is a native Swift (SwiftUI) iPhone app for people who keep living cultures at home — sourdough starters, kombucha, kimchi, yogurt, vinegar mothers, and other counted ferments. Its core object is a **named culture** with an append-only **event ledger** (feed, rise-check, bottle, bake, note). Everything the app shows — hours since last feed, rise phase, days in ferment, "is it due?" status — is *derived deterministically* from that ledger. Nothing is stored twice; nothing leaves the device.

## Motivation

Starter and ferment keepers live in note apps, group chats, and memory. "Did I feed this Tuesday or Wednesday?", "How long has the kombucha been brewing?", "When did I last discard?" — these questions turn a hobby into anxiety. Paper logs get wet; generic note apps can't answer time-derived questions. A dedicated ledger with deterministic derived status gives a confident, at-a-glance answer with zero cloud dependency.

## Target users

- Home bakers maintaining one or more sourdough starters.
- Home fermenters (kombucha, kimchi, sauerkraut, yogurt, vinegar, hot sauce).
- Gift-givers who hand out starter scoops and want to track each "child" jar.
- Anyone who wants a private, exportable history of their ferments.

## Concrete use cases

1. **Quick feed:** open the jar's detail, tap Feed, record grams (flour/water) and time. Ledger row created; "hours since feed" resets.
2. **Glance check:** the jar wall shows each culture's derived status — "Fed 8h ago · rising · peak near" — without opening anything.
3. **Bottling decision:** kombucha batch shows days-in-primary with the user's own taste-note history; user bottles, logs the event, secondary timer starts.
4. **Bake link:** log a bake event with flour used from the starter; the app shows bake cadence and starter usage without a recipe manager.
5. **Child tracking:** split a starter into a gifted jar; link it to the parent for lineage display (a directed acyclic graph of feed-split events).
6. **Backup:** export a versioned JSON archive (and CSV of the event ledger) to the Files app; restore replaces state after preview.

## How to use (intended end-to-end workflow)

1. Install and open — no sign-up, no network. First run offers a sample starter or start empty.
2. Create a culture: name, type (starter/kombucha/kimchi/other, user-editable), optional jar note and photo stored locally.
3. Log events as you work: Feed (with amounts), Rise-check (visual stage the user picks), Bottle, Bake, Discard, Note.
4. Glance at the jar wall for derived status; tap a jar for its full timeline.
5. Set per-culture feeding-cadence reminders (local notifications, opt-in).
6. Export backups on your schedule; import restores with a previewed diff.

## MVP feature list

- Cultures CRUD with type taxonomy (predefined + user-defined types).
- Append-only event ledger per culture; edit mistakes via correcting events, never silent mutation.
- Deterministic derived status engine: hours-since-feed, rise-phase band from user-logged checks, ferment-days, due-window from user cadence. Unknown/missing data renders **unknown**, never a guessed "safe/ready".
- Jar wall list/grid with status badges; culture detail timeline.
- Lineage links between parent/child cultures (DAG, cycle-rejected).
- Local notifications: per-culture feeding-cadence reminder (opt-in).
- Versioned JSON backup/restore with preview; CSV ledger export.
- Full VoiceOver/Dynamic Type support; haptic feedback on logging.

## Non-goals

- No recipe manager, no hydration-percentage baker's math suite, no fermentation science advice or temperature-curve automation.
- No pH/temperature hardware, no Bluetooth probes, no cloud sync, no social feed, no sharing accounts.
- No AI identification of "doneness", no spoilage safety advice (wellness boundary below).
- No Android, no native iPad support (see Platform scope).

## Platform scope and implementation

- **Native Swift (SwiftUI) iPhone-only iOS app.** iOS 26 SDK or newer (pinned in `toolchain.json`). Xcode/xcodebuild + Swift Package Manager.
- **Cross-platform/hybrid frameworks are prohibited** (Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity).
- **iPhone-only:** no Android target (not a roadmap item), and native iPad support is **disabled by default** — `TARGETED_DEVICE_FAMILY = 1` in every app-target build configuration, never `1,2`; built-app `UIDeviceFamily` must verify as `[1]` on an Apple build environment. iPad support requires explicit user opt-in.
- **Bundle identifier:** `com.infinityball.riselog` (registered in App Store Connect: `CREATED com.infinityball.riselog`). Used in PRODUCT_BUNDLE_IDENTIFIER, Info.plist, and all signing/provisioning configuration.

## iPhone Duo dual-screen design target (future)

Rise Log is designed as the canonical **glance-wall + detail-workspace** pair:

- **Folded / today:** a standard single-pane iPhone app; the jar wall is already the glanceable surface.
- **Duo design target:** one screen as a persistent **jar wall control surface** (status badges, quick Feed/Bottle taps, reminder state) while the other shows the selected culture's full timeline, photo notes, and lineage. Fold/unfold continuity must preserve selection and scroll state.
- **Build shape (SDK gap):** the dual-screen experience is a documented design target, **not a dependency**. The app builds today as a standard iPhone app with zero unavailable fold APIs. All layout adaptation funnels through a single seam, `FermentWorkspaceLayout`, which today collapses to single-pane and will adopt native dual-screen APIs when the SDK matures — the only code site expected to change.

## Privacy, permissions, and data storage

- **Zero network by construction.** No analytics, no accounts, no ad SDKs. A CI gate enforces an empty network allowlist.
- Local storage only (SQLite via GRDB in an app sandbox container). Photos are user-captured jar pictures stored in the app container, not the photo library (unless the user explicitly saves one out).
- Permissions: **Notifications** (opt-in reminders) only. No camera-library, location, contacts, or health permissions.
- Export/backup is user-initiated to the Files app: versioned JSON archive + CSV ledger. Restore previews and replaces; never silently merges.
- Data ownership: the user's file is the backup format; a documented schema ships with the app.

## Health & safety limits (non-medical)

Rise Log is a hobby log, not food-safety guidance. It never claims a ferment is "safe to eat", identifies spoilage, or gives medical advice. Rise-phase and due-window badges are derived solely from the user's own logged events and cadence settings, and unknown states render as unknown. Users decide edibility themselves.

## Signing / TestFlight / App Store plan

CI uses the App Store Connect API Actions secrets already configured on this repository — `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` (names only; values are never committed or printed). Release path: signed archive built with the pinned iOS 26-or-newer SDK → TestFlight upload via ASC API → manual release decision. Archive/signing/TestFlight evidence will be real build outputs when those milestones land; none exist yet.

## Current status & milestones

**Core workflow UI landed (M3).** Jar wall with derived badges, culture
detail timeline, fast Feed/Check/Bottle/Bake/Discard/Note capture,
append-only undo/correct, empty-state with sample culture, XCUITest
journey CI on the pinned simulator, and badge wording rules unit-tested
in RiseKit (no safety vocabulary, explicit Unknown states). See
`docs/core-ui-evidence.md` for the host-verified vs CI-pending split.
No device evidence or TestFlight binary exists yet.

1. M1: ✅ Xcode project + pure-Swift domain package + CI (pinned toolchain, iPhone-only guard).
2. M2: ✅ Ledger store (GRDB) + derived status engine with unknown-safe semantics.
3. M3: ✅ Jar wall + culture detail + event logging UI (accessible).
4. M4: Duo layout seam, lineage UI, reminders, photo notes.
5. M5: Backup/restore/export + privacy audit gate.
6. M6: TestFlight release evidence.

## Development quickstart

```bash
# Requires macOS with Xcode pinned in toolchain.json (Xcode 26.0.1 / iOS SDK 26.0)
xcodebuild -project RiseLog.xcodeproj -scheme RiseLog -destination 'generic/platform=iOS Simulator' build
xcodebuild -project RiseLog.xcodeproj -scheme RiseLog -destination 'platform=iOS Simulator,name=iPhone 17' test
```

On Linux, the pure-Swift `RiseKit` domain package builds and tests with a Swift 6 toolchain; it carries the status-derivation and ledger logic with no UI imports.
