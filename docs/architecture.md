# Architecture

## System Summary

Constellation is a local-first SwiftUI iOS app. It does not depend on a backend or third-party SDKs. Most runtime behavior falls into five areas:

1. constellation data loading from bundled JSON resources
2. user-created pattern capture and geometric matching
3. constellation browsing and detail rendering
4. moon calculation, calendar rendering, and location-aware rise/set computation
5. app-to-widget Live Activity handoff

## Target Boundaries

| Boundary | Responsibilities | Does not own |
| --- | --- | --- |
| Main app target | UI, matching, moon calculations, permissions, notification scheduling, Live Activity lifecycle | Widget rendering |
| Widget extension | Lock Screen and Dynamic Island presentation for existing activities | Starting or stopping activities |
| Test targets | Launch smoke tests and future regression coverage | Production code paths |

## High-Level Dependency Graph

```text
SwiftUI Views
  -> Services
     -> ConstellationDataStore
        -> bundled JSON resources

ConstellationCanvasView
  -> ConstellationMatcher
     -> preloaded constellation/star snapshot

ConstellationDetailView / MoonPhaseView
  -> ViewStateManager
     -> LiveActivityManager
        -> ActivityKit
           -> Widget extension rendering

SettingsView / MoonPhaseView
  -> LocationManager
  -> NotificationManager
     -> UserNotifications

Illustration-bearing views
  -> ImageCache
     -> PNG files under illustrations/
```

## Launch and App Lifecycle

`ConstellationApp` is the app entry point and performs three important startup tasks:

- prewarms `ConstellationMatcher` on a detached utility task so the create flow is responsive
- instantiates `NotificationManager.shared` early so foreground notification presentation works immediately
- configures UIKit navigation and tab-bar appearance once at launch

The initial root view is a `ZStack` containing:

- `MainTabView`
- `SplashScreenView`

The splash screen is not only visual. On first completion it also triggers:

- notification permission request through `NotificationManager`
- location request through `LocationManager`

Scene phase transitions drive background behavior:

- `.active`: end any running Live Activities and reschedule moon notifications once per day if enabled
- `.background`: start a Live Activity based on the last registered view context
- `.inactive`: ignored to avoid false positives during transient iPad resizing/state changes

## Primary User Flows

### Create Flow

`ConstellationCanvasView` owns the interactive creation experience.

Runtime sequence:

1. User taps the canvas to place up to 30 stars.
2. Re-tapping or tapping another star creates edges between star indices.
3. On submit, the view snapshots `stars` and `edges`.
4. `ConstellationMatcher.findMatches` normalizes user points, scans rotation in 5 degree increments, and scores candidates using combined positional and edge similarity.
5. The top four `MatchResult` values are presented.
6. Selecting a candidate overlays the matched constellation art and star geometry.
7. Tapping `View Details` navigates into `ConstellationDetailView`.

Important implementation details:

- Matching is local and uses bundled data only.
- The matcher tolerates star-count differences using a proportional threshold.
- Candidate overlays use the same illustration cache as gallery/detail screens.

### Gallery and Detail Flow

`GalleryView` loads the full constellation list asynchronously from `ConstellationLoader`, then supports:

- text search by constellation name or meaning
- persisted grid/list presentation via `@AppStorage("galleryViewMode")`
- navigation into `ConstellationDetailView`

`ConstellationDetailView` then:

- loads star geometry by constellation id, with illustration-name fallback
- converts HIP-star connections to integer indices for rendering and Live Activity context
- renders constellation stars and artwork in the same coordinate space
- registers the current detail context with `ViewStateManager`
- clears context and ends constellation activities only when the user leaves while the app remains active

### Moon Flow

`MoonPhaseView` is both a feature screen and the home of the astronomical engine.

Runtime sequence:

1. The screen initializes around the currently selected day.
2. `MoonCalculator.getMoonData` computes phase, illumination, next major phase, and optional rise/set times.
3. `LocationManager` provides the latest cached or live coordinate.
4. A minute-level timer refreshes today's data while the view is active.
5. A per-month cache stores phase values used by the 42-cell lunar calendar.
6. The view registers moon context with `ViewStateManager` so backgrounding can spawn the appropriate Live Activity.

The moon feature is local-first:

- phase-only calculations can run without location
- rise/set is withheld until location is available
- location denial is surfaced as UI guidance rather than a hard failure

### Settings and Notification Flow

`SettingsView` centralizes operational toggles:

- moon notifications
- Live Activities
- feedback mail link
- About screen navigation

When moon notifications are enabled:

1. permission is requested if needed
2. current location is required for accurate local rise/set times
3. `NotificationManager.scheduleMoonNotifications` computes up to 7 days of events
4. pending requests with known ids are synchronously replaced to avoid async cancellation races

When the app returns to the foreground, `ConstellationApp` rate-limits rescheduling to once per day using `moonNotificationsLastScheduled`.

## Data Loading Architecture

`ConstellationDataStore` is an `actor` and the single source of truth for bundled constellation data.

Responsibilities:

- decode `constellations-map.json`
- decode `constellation-stars.json`
- cache decoded arrays/dictionaries in memory
- deduplicate concurrent loads with task memoization
- build an illustration filename -> constellation id map

Why this matters:

- views and services avoid repeated JSON decoding
- concurrency safety is centralized
- star lookup by illustration is supported when ids are unavailable

The public loaders (`ConstellationLoader` and `ConstellationStarLoader`) are thin facades over this actor.

## Matching Architecture

`ConstellationMatcher` builds an immutable snapshot that merges:

- `Constellation` metadata
- raw star positions from `ConstellationStars`
- normalized star positions
- edge lists converted from HIP identifiers to integer indices

Matching algorithm summary:

- normalize user points by centroid and RMS scale
- reject obviously incompatible star-count combinations
- rotate the user pattern through the full 360 degrees in 5 degree steps
- compute chamfer distance for positional error
- derive nearest-neighbor correspondence
- score edge agreement against known constellation edges
- combine positional error and edge mismatch into a single ranking score

The matcher is explicitly preloaded at app startup because it is the largest pure-compute dependency used by the create flow.

## Rendering Architecture

### Shared rendering patterns

- `Canvas` is used for star and edge drawing in create, detail, and widget contexts.
- Illustration PNGs are post-processed by `ImageCache` to turn dark pixels transparent.
- `ResponsiveLayoutMetrics` centralizes width-based breakpoints and spacing rules for iPhone/iPad layouts.

### Coordinate transforms

Constellation rendering is not naive image overlay. The app applies:

- scale derived from resource bounds
- constellation-specific scale multiplier from JSON
- x/y shifts from JSON
- constellation-specific rotation from JSON
- Y-axis inversion where needed because JSON coordinates and canvas coordinates differ

The same logical data is reused in three places:

- detail screen star overlay
- create-screen match overlay
- widget star pattern rendering

## State Management

State is deliberately simple and mostly view-local, with a few singleton managers:

| State owner | Purpose |
| --- | --- |
| SwiftUI `@State` | Screen-local interaction state such as selected dates, drawn stars, search text, and loading indicators |
| `@AppStorage` | Small persisted user preferences and first-run markers |
| `LocationManager.shared` | Cached/current coordinate and authorization status |
| `NotificationManager.shared` | Notification permission status and scheduling |
| `ViewStateManager.shared` | Current screen context used for Live Activity handoff |
| `LiveActivityManager.shared` | Starts and ends activities based on view context and scene phase |

There is no broader reducer/store architecture in this codebase. The current design relies on:

- single-purpose service singletons
- bundled resources
- explicit screen registration for background handoff

## Live Activity Handoff

Live Activities rely on a two-step design:

1. Feature screens register the current constellation or moon context with `ViewStateManager`.
2. `ConstellationApp` watches the scene phase and asks `LiveActivityManager` to start an activity only when the app truly backgrounds.

Benefits of this approach:

- background cards reflect the user's most recent detail context
- activities are not started while the user is still actively using the app
- activities are ended when the app returns to the foreground

Important coupling:

- `Constellation/Models/ActivityAttributes.swift` and `ConstellationWidgets/ConstellationWidgetsBundle.swift` both define the same ActivityKit payload shapes
- any schema change must be applied in both targets

## Permissions and External System Integration

### Location

- Requested once the splash flow completes and again opportunistically from settings/moon screens
- Cached across launches in `UserDefaults`
- Used only for moon rise/set calculations and notification scheduling

### Notifications

- Optional
- Used only for moon rise and set alerts
- Foreground banners are enabled by setting `NotificationManager` as the center delegate

### Live Activities

- Controlled both by system-level ActivityKit availability and the app-level `liveActivityEnabled` flag
- UI controls are shown only on iPhone in `SettingsView`

## Reliability Notes

Current architecture strengths:

- no network dependency
- resource loading is concurrency-safe
- expensive matcher preparation is preloaded
- notification replacement avoids a common scheduling race
- Live Activity startup is tied to explicit screen context

Current architectural risks:

- `MoonCalculator` lives inside a view file and is difficult to test in isolation without refactoring
- Activity attribute types are duplicated across targets
- test coverage is effectively absent
- widget layout constants are hardcoded directly in source
