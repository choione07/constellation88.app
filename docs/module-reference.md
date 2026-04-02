# Module Reference

This document catalogs the codebase by target and file so each module has a clear owner and purpose.

## Main App Target: `Constellation`

### App Entry

| File | Main types | Responsibility | Key dependencies |
| --- | --- | --- | --- |
| `Constellation/ConstellationApp.swift` | `ConstellationApp` | App entry point, splash handling, first-run permission requests, scene-phase handling, global appearance, Live Activity lifecycle entry | `MainTabView`, `SplashScreenView`, `ConstellationMatcher`, `NotificationManager`, `LocationManager`, `LiveActivityManager` |

### Models

| File | Main types | Responsibility | Key dependencies |
| --- | --- | --- | --- |
| `Constellation/Models/Constellation.swift` | `Constellation`, `ConstellationData` | Codable metadata model for each constellation; includes rendering parameters and astronomy metadata | `constellations-map.json` |
| `Constellation/Models/ConstellationStar.swift` | `ConstellationStars`, `ConstellationStars.Star` | Codable star-map model containing point coordinates and HIP-based connections | `constellation-stars.json` |
| `Constellation/Models/ActivityAttributes.swift` | `ConstellationActivityAttributes`, `MoonActivityAttributes` | Shared ActivityKit payload definitions used by the main app when creating Live Activities | `ActivityKit`, widget target must stay in sync |

### Services

| File | Main types | Responsibility | Key dependencies |
| --- | --- | --- | --- |
| `Constellation/Services/AppDebugLog.swift` | `appDebugLog`, `appDebugTrace` | Debug-only logging helpers used across services and views | `DEBUG` builds |
| `Constellation/Services/ConstellationDataStore.swift` | `ConstellationDataStore` | Actor-based resource loader and cache for constellation metadata and star maps | bundled JSON resources |
| `Constellation/Services/ConstellationLoader.swift` | `ConstellationLoader` | Thin async facade returning all `Constellation` models | `ConstellationDataStore` |
| `Constellation/Services/ConstellationStarLoader.swift` | `ConstellationStarLoader` | Thin async facade for all star maps, by id, and by illustration name | `ConstellationDataStore` |
| `Constellation/Services/ConstellationMatcher.swift` | `ConstellationMatcher`, `MatchResult`, `NormalizedPoints`, `ConstellationMatchData` | Preloads constellation geometry, normalizes patterns, scans rotations, and ranks match candidates | `ConstellationLoader`, `ConstellationStarLoader`, `CoreGraphics` |
| `Constellation/Services/ImageCache.swift` | `ImageCache` | Caches processed constellation artwork and coalesces concurrent loads | `UIKit`, `illustrations/` PNG assets |
| `Constellation/Services/LocationManager.swift` | `LocationManager` | One-shot location access, authorization tracking, cross-launch coordinate caching | `CoreLocation`, `UserDefaults` |
| `Constellation/Services/NotificationManager.swift` | `NotificationManager` | Notification permission tracking, scheduling, cancellation, and foreground presentation | `UserNotifications`, `MoonCalculator` |
| `Constellation/Services/ViewStateManager.swift` | `ViewStateManager`, nested context types | Tracks which screen context should be represented if the app backgrounds | `Combine`, `SwiftUI`, `LiveActivityManager` consumer |
| `Constellation/Services/LiveActivityManager.swift` | `LiveActivityManager` | Starts and ends constellation/moon Live Activities based on current screen context and app phase | `ActivityKit`, `ViewStateManager`, `UserDefaults` |

### Views

| File | Main types | Responsibility | Key dependencies |
| --- | --- | --- | --- |
| `Constellation/Views/MainTabView.swift` | `MainTabView` | Root tab container for Create, Gallery, Moon, and More sections | `ConstellationCanvasView`, `GalleryView`, `MoonPhaseView`, `SettingsView` |
| `Constellation/Views/SplashScreenView.swift` | `StarAnimationValues`, `SplashScreenView`, `StarShape` | Branded first-run splash animation and permission handoff trigger | SwiftUI keyframe animation |
| `Constellation/Views/ResponsiveLayout.swift` | `ResponsiveLayoutMetrics` | Shared iPhone/iPad layout heuristics for padding, columns, widths, and split views | `SwiftUI`, `UIKit` |
| `Constellation/Views/ConstellationCanvasView.swift` | `ConstellationCanvasView`, `CandidateCard`, `MatchIllustrationLayer` | Interactive star-placement canvas, edge creation, match submission, candidate browsing, overlay rendering | `ConstellationMatcher`, `ConstellationDetailView`, `ImageCache` |
| `Constellation/Views/GalleryView.swift` | `GalleryView`, `ConstellationCard`, `ConstellationListRow`, `ConstellationThumbnail` | Searchable gallery of bundled constellations with persisted grid/list mode | `ConstellationLoader`, `ImageCache`, `ConstellationDetailView` |
| `Constellation/Views/ConstellationDetailView.swift` | `ConstellationDetailView`, `ConstellationImageView`, `ConstellationStarsLayer`, `IllustrationLayer`, `InfoRow` | Constellation metadata screen with layered art/star rendering and Live Activity context registration | `ConstellationStarLoader`, `ImageCache`, `ViewStateManager` |
| `Constellation/Views/MoonPhaseView.swift` | `MoonData`, `MoonCalculator`, `MoonPhaseShape`, `MoonSphereView`, `MoonInfoRow`, `CalendarDayCell`, `PhaseCard`, `DateWheelPicker`, `MoonPhaseView` | Moon feature UI plus astronomical computation engine, phase calendar cache, location-aware rise/set calculations, and Live Activity context registration | `LocationManager`, `ViewStateManager`, `LiveActivityManager` |
| `Constellation/Views/SettingsView.swift` | `SettingsView` | Operational settings for notifications and Live Activities, plus app info/contact entry points | `NotificationManager`, `LocationManager`, `ActivityKit` |
| `Constellation/Views/AboutView.swift` | `AboutView`, `FeatureRow`, `AppIconView` | Static about screen with feature summary and attribution | `ViewStateManager` |

### Resources and Assets

| Path | Purpose | Notes |
| --- | --- | --- |
| `Constellation/Resources/constellations-map.json` | Constellation metadata keyed by abbreviation | Includes names, descriptions, hemisphere, seasons, and rendering transforms |
| `Constellation/Resources/constellation-stars.json` | Constellation point clouds and edges keyed by abbreviation | Connections are stored using HIP star identifiers |
| `Constellation/illustrations/` | Source PNG artwork used in gallery/detail/create overlays | Image filenames must stay aligned with `illustration` fields |
| `Constellation/Assets.xcassets/` | App icons and about icon assets | Standard app asset catalog |

## Widget Extension Target: `ConstellationWidgetsExtension`

| File | Main types | Responsibility | Key dependencies |
| --- | --- | --- | --- |
| `ConstellationWidgets/ConstellationWidgetsBundle.swift` | `ConstellationWidgetsBundle`, duplicated `ConstellationActivityAttributes`, duplicated `MoonActivityAttributes`, `ConstellationLiveActivity`, `MoonLiveActivity`, `ConstellationLockScreenView`, `MoonLockScreenView`, `StarPatternView`, `MoonView`, `MoonShape` | Entire widget extension implementation, including Lock Screen and Dynamic Island layouts, preview/debug helpers, and compact/minimal rendering | `WidgetKit`, `ActivityKit`, payload schema must match main app |

Widget-specific notes:

- The extension does not fetch data or start activities.
- It only renders attributes/state passed from the main app.
- Layout tuning for the Dynamic Island is controlled by hardcoded constants at the top of the file.
- The file also contains debug overlay helpers that are disabled by default.

## Test Targets

| File | Main types | Responsibility | Notes |
| --- | --- | --- | --- |
| `ConstellationTests/ConstellationTests.swift` | `ConstellationTests` | Placeholder unit test target using `Testing` | No production assertions yet |
| `ConstellationUITests/ConstellationUITests.swift` | `ConstellationUITests` | Basic app launch and launch-performance smoke test | Uses `XCTest` |
| `ConstellationUITests/ConstellationUITestsLaunchTests.swift` | `ConstellationUITestsLaunchTests` | Launch screenshot smoke test | Mostly Xcode template content |

## Project and Scheme Files

| Path | Purpose | Notes |
| --- | --- | --- |
| `Constellation.xcodeproj/project.pbxproj` | Project configuration, targets, build settings, deployment target, bundle ids | iOS deployment target is 18.0 |
| `Constellation.xcodeproj/xcshareddata/xcschemes/Constellation.xcscheme` | Shared app scheme | Builds/runs the main app target |
| `Constellation.xcodeproj/xcshareddata/xcschemes/ConstellationWidgetsExtension.xcscheme` | Shared widget scheme | Builds the extension and launches through SpringBoard |
| `ConstellationWidgetsInfo.plist` | Widget extension Info.plist | Explicit plist used because the widget target does not autogenerate one |

## File Ownership by Feature

Use this map when deciding where changes belong.

### Constellation matching

- Capture UI: `ConstellationCanvasView.swift`
- Matching algorithm: `ConstellationMatcher.swift`
- Data contracts: `Constellation.swift`, `ConstellationStar.swift`
- Resource loading: `ConstellationDataStore.swift`, `ConstellationLoader.swift`, `ConstellationStarLoader.swift`

### Constellation presentation

- Gallery browsing: `GalleryView.swift`
- Detail page: `ConstellationDetailView.swift`
- Artwork loading/caching: `ImageCache.swift`

### Moon feature

- Astronomy engine: `MoonPhaseView.swift` (`MoonCalculator`)
- Screen UI and calendar caching: `MoonPhaseView.swift`
- Location dependency: `LocationManager.swift`
- Alerts: `NotificationManager.swift`

### Live Activities

- Activity payload definitions: `Models/ActivityAttributes.swift`
- Context capture: `ViewStateManager.swift`
- Activity lifecycle: `LiveActivityManager.swift`
- Widget rendering: `ConstellationWidgetsBundle.swift`

### Global app behavior

- App lifecycle and permissions: `ConstellationApp.swift`
- Top-level navigation: `MainTabView.swift`
- First-run splash: `SplashScreenView.swift`
- Shared layout breakpoints: `ResponsiveLayout.swift`
- User settings/info surfaces: `SettingsView.swift`, `AboutView.swift`
