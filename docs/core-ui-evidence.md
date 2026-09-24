# Issue #4 — Core workflow UI: verification evidence

Honest split of what was actually executed where. Simulator results are
simulator results; device evidence does not exist yet.

## Host-verified (Linux, this session, before push)

- **RiseKit swift-testing suite**: 73 tests / 14 suites passed via
  `carekit-swift-sqlite` (Swift 6.2.4, system SQLite) — includes the new
  `DerivedStatusTextTests` (badge/wording rules incl. forbidden-vocabulary
  scan), `SampleDataTests` (sample badge pinned to `Fed 14h · peaked`;
  store-seed + duplicate-rejection), and `DisplaySummaryTests`
  (timeline one-liners).
- **Zero-network gate**: PASS with extended roots (RiseLog, Packages,
  UITests), empty allowlist.
- **Script helper unittests**: 21 tests OK (`python3 -m unittest discover
  -s Scripts/tests`) — exact-pin selector, simulator enumeration retry,
  bounded boot/retry/bootstatus semantics.
- **`bash -n Scripts/ci.sh`**: clean.
- **pbxproj integrity**: brace-balanced; every referenced object ID is
  defined (regex diff). UITests target IDs `…C1/…CA` do not collide with
  main (no other open PRs).
- **Swift syntax parse**: app + UITests sources pass `swiftc -parse` on
  Linux (syntax only — this is NOT type-checking; Apple CI does that).

## CI-pending (exact head SHA; must be green before merge)

- `linux-package`: swift test (GRDB/libsqlite3), zero-network gate,
  signing-material gitignore probe.
- `ios-build` (`Scripts/ci.sh`): exact toolchain pin (`Exact pin found`),
  zero-network, iPhone-only pre/post-build (`UIDeviceFamily == [1]`,
  bundle id, embedded xcprivacy), Release app build, XCUITest journeys:
  - create → feed → wall badge flips Unknown → `Fed 0 hours ago`
  - empty-state → sample → badge `Fed 14 hours ago, observed peaked`
  - undo appends matching discard (both rows remain); correct appends a
    superseding event
  - core loop at AX5 Dynamic Type (`UICTContentSizeCategoryAccessibility5`)
  All simulator results — no device results.

## Not claimed

- No VoiceOver *manual* review (labels are present + asserted, but the
  human review gate happens with real hardware later).
- No haptics (planned with polish; ledger correctness never depended on
  them).
- No device/TestFlight evidence (issue #8 territory).
