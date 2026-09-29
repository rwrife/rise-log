# Rise Log — Release pipeline (issue #8)

The release gate is `.github/workflows/release.yml`. It turns a `v*.*.*` tag
push (or a manual dispatch) into:

1. **Exact-pin gate** — `Scripts/select_xcode.py` against `toolchain.json`
   (Xcode 26.0.1 / build 17A400 / iOS SDK 26.0). A missing exact pin is an
   environment acceptance blocker; the run fails, nothing is substituted.
2. **Contract gates** — zero-network scan, workspace-layout seam guard,
   iPhone-only source assertion (`TARGETED_DEVICE_FAMILY = 1` everywhere,
   no `1,2`, no other values), signing-material gitignore check.
3. **Signed archive** — `xcodebuild archive` for `generic/platform=iOS`,
   automatic signing driven by the App Store Connect API key in repository
   Actions secrets (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`,
   `ASC_TEAM_ID` — names only, values never echoed or logged).
   `CURRENT_PROJECT_VERSION` is the GitHub run number (monotonic),
   `MARKETING_VERSION` comes from the tag.
4. **Archive gates on the built artifact** — bundle id must be
   `com.infinityball.riselog`, `UIDeviceFamily == [1]` (no `2`),
   `NSPrivacyTracking=false` with empty tracking-domain and collected-data
   arrays, `codesign --verify --deep --strict`.
5. **Export + upload** — `xcodebuild -exportArchive` with
   `method=app-store-connect` and `destination=upload` (TestFlight),
   authenticated with the same ASC API key. No fastlane, no altool
   (removed in Xcode 26).
6. **Processed-build evidence** — `scripts/poll_testflight_build.sh` polls
   the App Store Connect API (JWT minted by `scripts/asc_jwt.rb`, raw R‖S
   ES256 signature) until the uploaded build's `processingState` is
   `VALID`/`COMPLETE` and prints the raw API responses. The job fails on
   `FAILED`/`INVALID` or timeout — completion is never claimed without it.
7. **GitHub release** (tag pushes only) — release notes generated from the
   squash-merge subjects since the previous tag.

## Retry / repoint policy

If a tag run fails for a reason fixed on `main`, fix forward via PR, merge,
then repoint the tag: `git tag -f -a v0.1.0 <new-main-sha> && git push -f
origin refs/tags/v0.1.0` (GitHub re-fires the workflow; build numbers stay
monotonic because the run number increments).

## Evidence location (issue #8)

Run URL + raw `processingState` responses + build id are recorded on
https://github.com/rwrife/rise-log/issues/8 once a real processed build
exists. Until then, nothing here is claimed as done — Linux-side checks
(actionlint, YAML parse, bash syntax) verify the pipeline only statically.
