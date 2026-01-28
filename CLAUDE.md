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
- `AudioPlayer` protocol - Abstraction for audio playback
- `PodcastAudioPlayer` - Implementation using AVPlayer (streaming) and AVAudioPlayer (local files), seamlessly switches between stream and downloaded file during playback

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

### CarPlay Integration

`CarPlaySceneDelegate.swift` implements `CPTemplateApplicationSceneDelegate`:
- Tab bar with Radio and Shows tabs
- `RadioPlayer` singleton for CarPlay audio
- `PodcastRepository` for fetching latest episodes from Realm

### Key Dependencies

- **RealmSwift** - Local database for podcast storage and favorites
- **AVFoundation** - Audio playback
- **CarPlay** - Vehicle integration via CPTemplateApplicationSceneDelegate

### Background Audio

Configured in Info.plist with `UIBackgroundModes: audio` for continuous playback.
