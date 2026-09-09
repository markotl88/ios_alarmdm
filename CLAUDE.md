# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

Open the Xcode project and build:
```bash
open AlarmDM/AlarmDM.xcodeproj
xcodebuild -project AlarmDM/AlarmDM.xcodeproj -scheme AlarmDM -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Run tests:
```bash
xcodebuild -project AlarmDM/AlarmDM.xcodeproj -scheme AlarmDM -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Architecture Overview

AlarmDM is a SwiftUI podcast/radio streaming app for the "Daško i Mlađa" radio show. It supports live radio streaming, podcast playback, offline downloads, and CarPlay integration.

### Core Layers

**Models** (`AlarmDM/Model/`)
- `Podcast` - Main domain model with show type, duration, download status, bookmarks
- `Show` - Enum defining all available shows with display names, descriptions, and images
- `Bookmark` - Timestamp markers within podcasts

**Service Layer** (`AlarmDM/ServiceLayer/`)
- `PodcastService` - Fetches podcasts from Firebase backend, handles downloads
- `NetworkManager` - Generic HTTP client with download progress support
- `APIRouter` - Endpoint definitions for Firebase functions, livestream, etc.

**Player** (`AlarmDM/Player/`)
- `PlaybackEngine` - **The single source of truth for playback.** One AVPlayer, one
  audio session, one Now Playing info centre, remote commands registered once.
  Both the SwiftUI app and the CarPlay scene drive `PlaybackEngine.shared`, so the
  phone and the car can never disagree or play two streams at once.
- `PlaybackSource` - `.radio(url:)` or `.podcast(Podcast)`; resolves to a local file
  when the episode is downloaded, otherwise streams.
- `switchToLocalFile(_:)` - swaps a streaming episode for its finished download
  without losing position.
- `AudioPlayer` / `PodcastAudioPlayer` - legacy, no longer used by any view.

**Persistence** (`AlarmDM/Realm/`)
- Uses RealmSwift for local storage
- `PodcastRealm` - Realm object mirroring `Podcast` model
- Schema version managed in `AlarmDMApp.swift`

### View Architecture

Uses MVVM pattern with SwiftUI:

**Tab Structure** (`Views/TabView/TabContentView.swift`)
- Custom tab bar implementation with 4 tabs: Radio, Shows (Emisije), Support (Podrži), Settings (Ostalo)
- `PlayerViewModel` is shared via `@EnvironmentObject` across all views

**Player Views** (`Views/PlayerView/`)
- `MiniPlayerView` - Compact player shown at bottom when content is playing
- `PlayerView` / `PlayerModalView` - Full-screen player with controls
- `PlayerViewModel` - Manages playback state, download progress, and player mode (radio vs podcast)

**PlayerMode enum** - Distinguishes between live radio streaming and podcast playback

`PlayerViewModel` is a thin facade over `PlaybackEngine.shared`: it owns presentation
and download state and mirrors playback state, so playback started from CarPlay or the
lock screen shows up correctly in the app.

### CarPlay Integration

`CarPlaySceneDelegate.swift` implements `CPTemplateApplicationSceneDelegate`:
- Tab bar with Radio and Emisije tabs
- Every action goes through `PlaybackEngine.shared`; CarPlay owns no player
- Observes the engine to keep the radio row's state in sync
- `PodcastRepository` for fetching latest episodes from Realm
- Entitlement: `com.apple.developer.carplay-audio` only (the deprecated
  `playable-content` key was removed)

### Key Dependencies

- **RealmSwift** - Local database for podcast storage and favorites
- **AVFoundation** - Audio playback
- **CarPlay** - Vehicle integration via CPTemplateApplicationSceneDelegate

### Background Audio

Configured in Info.plist with `UIBackgroundModes: audio` for continuous playback.
