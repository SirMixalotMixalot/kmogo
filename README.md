# Roam

**Study to run across the world.** Roam is a focus timer where every study session is a run on a real map. At your pace (default 6:00 /km), a 30-minute session is a 5K. Your runner moves along real Apple Maps routes as you study, so Waterloo → Toronto takes about a week of solid work and Toronto → Vancouver takes a whole term.

Inspired by FocusFlight, Forest, and YPT, with Strava-style share cards built for Instagram stories.

## Features

| | |
|---|---|
| **Runs = study sessions** | Pick 5K, 10K, half marathon, marathon, or a custom session of up to 10 hours. The session length is distance × pace. |
| **Real-world journey** | Choose a destination city. Roam fetches a real walking route from Apple Maps, or a driving route if walking fails, or a great-circle line as a last resort. Each run moves you along it. If you run past a city, the extra km carry over to your next leg. |
| **Live run map** | A full-screen map shows your runner moving along the route in real time, with a countdown, distance, pace, and a follow-camera. The screen stays awake during a run, and you get a notification when you finish. |
| **Focus tracking** | Roam counts every time you leave the app. **Strict mode** ends your run if you're away for more than 60 s, and you're only credited up to the moment you left. |
| **Coins & shop** | You earn 10 coins per km, with a +20% bonus for finishing a run (half coins if you bail). Spend them on 🚌 bus (15 km), 🚆 train (60 km), or ✈️ plane (straight to your destination) tickets. |
| **Group runs** | Create a run that starts in X minutes and share the `roam://` link. Everyone who opens it starts and finishes at the same moment. Late joiners run the remaining part. No server needed, because the link holds the whole session. |
| **Share cards** | 1080×1920 PNGs for IG stories in three styles: **Route** (your trail shape on a gradient), **Map** (a dark map snapshot with your route), and **Sticker** (transparent, Strava-style, to paste over your own photo). Use Share or Copy. |
| **Passport** | Collect cities. Towns you pass through are reverse-geocoded and added automatically. Includes your run history and lifetime stats. |

## Running it

Requires Xcode 16+ (built with Xcode 27.2). The deployment target is iOS 17.

```sh
open Roam.xcodeproj        # then ⌘R on any iPhone simulator
# or
xcodebuild -project Roam.xcodeproj -scheme Roam -destination 'platform=iOS Simulator,name=iPhone 15 Pro' test
```

Routing uses MapKit, so you don't need an API key. The simulator needs network access to fetch routes.

**Demo data (Debug builds only).** Add these launch arguments under Scheme → Run → Arguments:

- `-demo`: seeds a profile, a real Waterloo → Montréal route, and four past runs, including an 8-hour "finals season" ultra
- `-demoRun`: also starts a 5K immediately
- `-demoSummary`: opens the share card for the 8-hour run
- `-tab N`: opens tab N (0 Run, 1 Journey, 2 Shop, 3 Passport)

Group-run links can be tested in the simulator with:
`xcrun simctl openurl booted "roam://group?id=abc123&host=Sam&start=$(($(date +%s)+60))&km=5&pace=360"`

## Code map

```
Roam/
  RoamApp.swift            App entry, root navigation, full-screen run flow, shared components
  Model/
    Models.swift           City, Leg, RunRecord, ActiveRun, GroupInvite, Transit, GameState, formatting
    AppStore.swift         All game rules (distance credit, coins, arrivals, strict mode, shop) + JSON persistence
    Geo.swift              Haversine, great circles, polyline thinning, Track (position at km / slicing)
    Cities.swift           Destination catalogue
  Services/Services.swift  MapKit routing, reverse geocoding, notifications, map snapshots
  Views/                   Onboarding, RunSetup, ActiveRun (+ group lobby), RunSummary, ShareCard, Journey, Shop, Passport
RoamTests/                 Unit tests for geo math, invite links, and game rules
```

The state is a single `Codable` `GameState`. It's saved as JSON in Application Support after every change, and an in-progress run survives an app relaunch.

## Next steps

- **Live Activity / Dynamic Island** for the run timer (needs a widget extension target).
- **Universal links** (`https://roam.app/g/...`) so invites are tappable inside Instagram DMs and other apps that block custom schemes.
- **Backend for group runs** (CloudKit or Firebase) to show who's in the lobby and a live leaderboard.
- **Direct "Share to Instagram Stories"** through the `instagram-stories://` pasteboard API. This needs a Meta app ID.
- **Trails** (an AllTrails-style catalogue), more cities, and cosmetics for the runner.
- **Screen Time / FamilyControls** app blocking during runs, for a stronger focus mode.
