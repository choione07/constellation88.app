# Constellation

Technical documentation for the Constellation iOS codebase.

## Overview

Constellation is a SwiftUI iOS application that lets users:

- draw a custom star pattern and match it against the 88 standard constellations
- browse a searchable gallery of built-in constellations
- inspect constellation artwork, metadata, and star connections
- track moon phases, next major phase, and moon rise/set times
- surface constellation and moon context on the Lock Screen and Dynamic Island via Live Activities

The repository currently contains:

- 1 main iOS app target
- 1 WidgetKit extension target
- 1 unit test target
- 1 UI test target
- 88 constellation metadata records in `constellations-map.json`
- 88 constellation star-map records in `constellation-stars.json`

This documentation reflects the repository contents reviewed on 2026-03-18.

## Documentation Map

- [`docs/architecture.md`](docs/architecture.md): runtime architecture, lifecycle, data flow, state, and service interactions
- [`docs/module-reference.md`](docs/module-reference.md): file-by-file reference for every target and module
- [`docs/data-and-maintenance.md`](docs/data-and-maintenance.md): resource contracts, persisted keys, build/test notes, and maintenance guidance

## Targets

| Target | Type | Purpose |
| --- | --- | --- |
| `Constellation` | iOS app | Main SwiftUI application and business logic |
| `ConstellationWidgetsExtension` | WidgetKit extension | Lock Screen and Dynamic Island Live Activities |
| `ConstellationTests` | Unit tests | Placeholder test target using the new `Testing` framework |
| `ConstellationUITests` | UI tests | Basic launch and performance smoke tests |

## Tech Stack

- Swift 5
- SwiftUI for all primary UI
- UIKit for appearance configuration and image processing helpers
- ActivityKit + WidgetKit for Live Activities
- CoreLocation for observer location
- UserNotifications for moon rise/set alerts
- Foundation, Combine, CoreGraphics for models, timing, and geometry

The Xcode project is configured for iOS 18.0 and universal device family support (`iPhone` and `iPad`).

## Repository Layout

```text
Constellation/
  Models/          Shared model and ActivityKit attribute types
  Services/        Data loading, matching, caching, location, notifications, Live Activities
  Views/           SwiftUI screens and reusable UI components
  Resources/       JSON data for constellation metadata and star maps
  illustrations/   PNG source artwork used by gallery, detail, and match overlays

ConstellationWidgets/
  ConstellationWidgetsBundle.swift   Widget extension entry point and Live Activity views

ConstellationTests/
ConstellationUITests/
Constellation.xcodeproj/
```

## Getting Started

1. Open `Constellation.xcodeproj` in Xcode.
2. Build and run the `Constellation` scheme on an iOS 18 simulator or device.
3. Build the `ConstellationWidgetsExtension` scheme when iterating on Live Activity UI.
4. Review the deeper docs before changing shared ActivityKit payloads, JSON contracts, or astronomical calculations.

Example CLI commands:

```bash
open Constellation.xcodeproj
xcodebuild -project Constellation.xcodeproj -scheme Constellation build
xcodebuild -project Constellation.xcodeproj -scheme ConstellationWidgetsExtension build
```

For simulator tests, use a locally installed simulator destination:

```bash
xcodebuild -project Constellation.xcodeproj -scheme Constellation \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Where To Start Reading

- Start with [`docs/architecture.md`](docs/architecture.md) if you need to understand runtime behavior.
- Start with [`docs/module-reference.md`](docs/module-reference.md) if you need to find the owning file for a feature.
- Start with [`docs/data-and-maintenance.md`](docs/data-and-maintenance.md) if you are changing JSON resources, Live Activity payloads, or persisted settings.
