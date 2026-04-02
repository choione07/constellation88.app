# Data and Maintenance

## Bundled Data Contracts

### `constellations-map.json`

Top-level structure:

- JSON object keyed by constellation abbreviation, for example `Aql`, `And`, `Ori`

Each value maps to `Constellation` and currently contains:

- `name`
- `meaning`
- `illustration`
- `center_ra`
- `center_dec`
- `observable_seasons`
- `description`
- `constellation_scale`
- `constellation_rotation`
- `x_shift`
- `y_shift`
- `hemisphere`

Operational notes:

- The code injects `id` from the top-level key after decoding.
- Records are sorted by `name` in `ConstellationDataStore`.
- `illustration` must continue to match a PNG filename after lowercasing and removing `.png`.

### `constellation-stars.json`

Top-level structure:

- JSON object keyed by the same constellation abbreviations used by `constellations-map.json`

Each value maps to `ConstellationStars`:

- `stars`: array of `{ hip, x, y }`
- `connections`: array of two-element arrays containing HIP identifiers

Operational notes:

- `ConstellationMatcher` converts HIP identifiers to integer indices during snapshot preparation.
- `ConstellationDetailView` repeats the connection conversion when preparing Live Activity context.
- Mismatched or missing HIP ids are silently skipped from rendered connections.

### Illustration Assets

Illustrations live in `Constellation/illustrations/` and are loaded by filename from three surfaces:

- gallery thumbnails
- constellation detail artwork
- create-screen match overlays

Images are post-processed so dark pixels become transparent. If the source art style changes, re-evaluate `ImageCache.convertBlackToTransparent`.

## Persisted Keys

The codebase currently stores the following keys in `UserDefaults` / `@AppStorage`:

| Key | Owner | Type | Purpose |
| --- | --- | --- | --- |
| `hasRequestedPermissions` | `ConstellationApp` | `Bool` | Prevents repeating the first-run permission handoff after splash |
| `galleryViewMode` | `MainTabView`, `GalleryView` | `String` | Persists gallery layout as `grid` or `list` |
| `moonNotificationsEnabled` | `SettingsView`, `ConstellationApp` | `Bool` | Master switch for moon rise/set alerts |
| `liveActivityEnabled` | `SettingsView`, `LiveActivityManager` | `Bool` | App-level switch for Live Activities |
| `moonNotificationsLastScheduled` | `ConstellationApp` | `Date` | Limits rescheduling to once per calendar day |
| `locationCachedLatitude` | `LocationManager` | `Double` | Restores last known latitude across launches |
| `locationCachedLongitude` | `LocationManager` | `Double` | Restores last known longitude across launches |

Maintenance rule:

- add new keys here when they are introduced
- keep string literals consistent across call sites
- prefer a centralized declaration if the number of keys grows further

## Activity Payload Contract

The activity payloads are defined twice:

- `Constellation/Models/ActivityAttributes.swift`
- `ConstellationWidgets/ConstellationWidgetsBundle.swift`

This duplication is required because the widget extension cannot directly rely on the app target at runtime in the current structure, but it introduces schema drift risk.

Whenever changing activity fields:

1. update both copies
2. update `LiveActivityManager` construction code
3. update widget rendering code
4. verify any preview/sample payloads still compile

## Moon Validation Support

`MoonCalculator` includes a built-in validation helper:

- `validationReport(csvAt:)`
- `validationReport(csv:)`

Accepted CSV columns are case-insensitive:

- `timestamp` or equivalent (`datetime`, `date`, `time`) - required
- `timezone`
- `latitude`
- `longitude`
- `phase`
- `illumination`
- `rise_hours`
- `set_hours`

Accepted event values:

- numeric hours in local time
- blank to skip comparison
- `none` or `n/a` to assert that no event should occur

Use this before and after altering astronomical formulas, refactoring `MoonCalculator`, or changing timezone handling.

## Build and Run Notes

Project-level settings extracted from `project.pbxproj`:

- iOS deployment target: `18.0`
- Swift version: `5.0`
- main app marketing version: `1.0.2`
- widget marketing version: `1.0`
- supported device families: `1,2` (`iPhone`, `iPad`)

Shared schemes:

- `Constellation`
- `ConstellationWidgetsExtension`

Suggested commands:

```bash
open Constellation.xcodeproj
xcodebuild -project Constellation.xcodeproj -scheme Constellation build
xcodebuild -project Constellation.xcodeproj -scheme ConstellationWidgetsExtension build
```

For tests, supply a simulator installed on the local machine:

```bash
xcodebuild -project Constellation.xcodeproj -scheme Constellation \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Change Impact Guide

### If you add or rename a constellation

Update:

- `constellations-map.json`
- `constellation-stars.json`
- `illustrations/` asset set
- any assumptions in docs that mention 88 records if the total changes

Validate:

- gallery loads correctly
- detail lookup by id works
- detail fallback lookup by illustration still works
- matcher snapshot builds without missing connections

### If you change constellation rendering

Likely files:

- `ConstellationDetailView.swift`
- `ConstellationCanvasView.swift`
- `ConstellationWidgetsBundle.swift`
- `Constellation.swift` if you add new rendering parameters

Validate:

- detail overlay alignment
- create-screen overlay alignment
- widget star pattern appearance

### If you change the matching algorithm

Likely files:

- `ConstellationMatcher.swift`
- `ConstellationCanvasView.swift` if match presentation changes

Validate:

- startup prewarm still happens
- candidate ranking remains stable
- match overlays use the chosen angle/scale correctly

### If you change moon calculations

Likely files:

- `MoonPhaseView.swift`
- `NotificationManager.swift`
- `SettingsView.swift`
- `LiveActivityManager.swift`
- widget extension rendering if displayed fields change

Validate:

- phase label and illumination
- next major phase
- rise/set availability and times
- notification scheduling
- Live Activity moon content

### If you change permissions or settings UX

Likely files:

- `ConstellationApp.swift`
- `SettingsView.swift`
- `NotificationManager.swift`
- `LocationManager.swift`

Validate:

- first-run flow
- denied-permission messaging
- cross-launch persistence
- background notification rescheduling

## Current Gaps and Risks

### Test coverage is minimal

- `ConstellationTests` is still a template placeholder
- UI tests cover launch only
- there is no automated regression suite for matcher accuracy, moon math, or notification logic

Recommended next additions:

- unit tests for `ConstellationMatcher` normalization and ranking behavior
- unit tests for `MoonCalculator` phase and rise/set validation samples
- UI tests for the create flow, gallery search, and settings toggles

### `MoonCalculator` is embedded in a view file

This works, but it mixes a heavy domain engine with SwiftUI presentation. If the astronomy surface grows, move it into `Services/` or a dedicated `Astronomy/` group.

### Widget layout tuning is source-driven

Dynamic Island sizing constants are embedded directly in `ConstellationWidgetsBundle.swift`. That is workable for a small project, but harder to audit than a more structured layout configuration.

### Activity contracts are duplicated

Keep the two attribute definitions synchronized or the app and widget extension can diverge at compile time or runtime.

## Recommended Maintenance Rhythm

- Update this documentation when adding a new target, major feature, persisted key, or bundled resource contract.
- Keep `docs/module-reference.md` aligned with any renamed/moved files.
- Re-run moon validation when touching astronomical formulas.
- Review notification id formats before changing moon scheduling windows.
- Check widget layouts on-device whenever Dynamic Island constants are changed.
