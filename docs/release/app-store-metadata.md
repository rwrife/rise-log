# Rise Log — App Store metadata (v0.1.0)

Authoritative copy for App Store Connect. Source of truth for what the app
does is the code + `README.md` / `PLAN.md`; this file records what was
submitted so future metadata changes are diffable.

## Identity
- Name: **Rise Log**
- Subtitle: *Sourdough & ferment ledger*
- Bundle ID: `com.infinityball.riselog` (prefix `com.infinityball.` is mandatory)
- SKU: `riselog-ios-iphone`
- Primary language: English (US)
- Platform: iPhone only (`TARGETED_DEVICE_FAMILY = 1`; iPad/Android not enabled — explicit user opt-in required)
- Content rights declaration: owns everything; third-party ads: no
- Age rating: answers per questionnaire → 4+ (no harmful content; medical/health: none — the app makes **no** food-safety or health determinations)

## Categories
- Primary: Food & Drink
- Secondary: Utilities

## Privacy — "Data Not Collected"
Rise Log collects **no** data and uses **no** tracking. Zero network access
by construction, enforced by the CI zero-network gate (empty allowlist; any
network API usage fails the build). All cultures, events, and backups live
in an on-device SQLite database and user-initiated exports the user controls
(share sheet / Files). The in-app privacy manifest (`RiseLog/PrivacyInfo.xcprivacy`)
declares `NSPrivacyTracking=false`, empty tracking domains, and empty
collected data types; the release workflow re-verifies this in the archived
artifact on every release run.

Privacy policy URL: not required (no data collected). If a URL becomes
required by policy, point it at the README's privacy section in the public
repo.

## App description (whats-new baseline for 0.1.0)
Rise Log is a local-only journal for sourdough starters and other
ferments. Keep a jar wall of your cultures, log feed / rise-check /
bottle / bake / discard / note events to an append-only ledger, and see a
derived status that tells you what the ledger shows — and says "unknown"
when it does not, instead of guessing.

- Every number is derived from your own event history; nothing is hidden in cached state.
- Optional per-culture feeding reminders — off by default.
- Versioned JSON backup and restore with a previewed diff, plus CSV ledger export. All on your device.
- Lineage tracking for splits from mother cultures.
- No accounts, no sync, no ads, no network access at all.

Rise Log is a baking log, not a food-safety tool: it never judges whether
a ferment is safe to use.

## Keywords (100 chars)
sourdough,starter,levain,ferment,kefir,baking,journal,starter log,combine: none

## What's New for 0.1.0
First TestFlight build: jar wall, culture detail with append-only event
ledger, derived status badges, per-culture local reminders (opt-in),
versioned JSON backup/restore with previewed replace, CSV export, and an
iPhone-only single-pane layout (dual-screen is a documented future seam).
