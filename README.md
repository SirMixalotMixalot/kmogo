# Roam

**Study to run across the world.** Roam is a focus timer where every study session is a run on a real map. At your pace (default 6:00 /km), a 30-minute session is a 5K. Your runner moves along real Apple Maps routes as you study, so Waterloo → Toronto takes about a week of solid work and Toronto → Vancouver takes a whole term.

Inspired by FocusFlight, Forest, and YPT, with Strava-style share cards built for Instagram stories.

## Features

| | |
|---|---|
| **Runs = study sessions** | One-tap distance chips (1K, 3K, 5K, 10K, half, marathon) or a custom session of up to 10 hours. The session length is distance × pace. |
| **Journey runs** | Choose a destination city. Roam fetches a real walking route from Apple Maps, or a driving route if walking fails, or a great-circle line as a last resort. Each journey run moves you along it, and extra km past a city carry over. You can change your destination mid-route. |
| **Explore runs** | Tap anywhere on the zoomable setup map, or roll a random direction 🎲. Roam finds a real walking route and fits it to exactly your distance, trimming it or making it an out-and-back. Your runner stays where the run ends, finishing near a city collects it, and your journey re-routes from the new spot. |
| **Live run view** | A 3D satellite follow-cam tracks your animated runner and turns with the road. A live **Look Around street-view** card updates as you move, the header shows the street you're on ("Now on King St W"), and you get toasts and haptics at every km split. You can switch to an overview or the standard map. The screen stays awake during a run, and you get a notification when you finish. |
| **Focus tracking** | Roam counts every time you leave the app. **Strict mode** ends your run if you're away for more than 60 s, and you're only credited up to the moment you left. |
| **Coins & shop** | You earn 10 coins per km, with a +20% bonus for finishing a run (half coins if you bail). Spend them on 🚌 bus (15 km), 🚆 train (60 km), or ✈️ plane (straight to your destination) tickets. |
| **Group runs** | Create a run that starts in X minutes and share the `roam://` link. Everyone who opens it starts and finishes at the same moment. Late joiners run the remaining part. No server needed, because the link holds the whole session. |
| **Share cards** | 1080×1920 PNGs for IG stories in three styles: **Route** (your trail shape on a gradient), **Map** (a dark map snapshot with your route), and **Sticker** (transparent, Strava-style, to paste over your own photo). Use Share or Copy. |
| **Passport** | Collect cities. Towns you pass through are reverse-geocoded and added automatically. Includes your run history and lifetime stats. |
| **Accounts & friends** | Email accounts, friend codes, requests, and opt-in sharing of virtual positions and study progress through Supabase. Friends appear on the Friends and Journey maps. |

## Cheat code 🕹️

Go to Passport → ⚙️ Settings → **Cheat code**, enter `ROAMFAST`, and tap Redeem. This unlocks:

- **Time warp** (10× / 60× / 300×) for new solo runs. At 60×, a 5K takes 30 s and an 8-hour ultra takes 8 minutes. The run is still recorded as the full study time.
- A purple **Finish** button during runs that completes them instantly.
- **+1,000 coins**, **Teleport to destination**, and **Add a week of sample runs**, which includes an 8-hour ultra for share-card testing.

These cheats ship in every build right now. Remove them or gate them before a public release.

## Running it

Requires Xcode with Swift 6.1 or later (CI uses Xcode 27). The deployment target is iOS 17.

```sh
open Roam.xcodeproj        # then ⌘R on any iPhone simulator
# or
xcodebuild -project Roam.xcodeproj -scheme Roam -destination 'platform=iOS Simulator,name=iPhone 15 Pro' test
```

Routing uses MapKit, so you don't need an API key. The simulator needs network access to fetch routes.

**Demo data (Debug builds only).** Add these launch arguments under Scheme → Run → Arguments:

- `-demo`: on a fresh install, seeds a profile, a real Waterloo → Montréal route, and four past runs, including an 8-hour "finals season" ultra
- `-demoRun`: also starts a 5K immediately
- `-demoSummary`: opens the share card for the 8-hour run
- `-tab N`: opens tab N (0 Run, 1 Journey, 2 Shop, 3 Passport, 4 Friends)

## Accounts and friends

Open Passport → Account or Friends → Account to create an email account. Confirm the email, then sign in. A profile is created on the first authenticated connection. New accounts start with progress sharing off.

Backend.swift contains the `roam-dev` project URL and publishable client key. Supabase manages session persistence in Keychain and token refresh. Row Level Security and authenticated database functions enforce access to profiles, friendships, and progress.

To test with two people, exchange codes in Friends, send and accept a request, then enable sharing. The Friends and Journey maps show the shared virtual position. The app refreshes while foregrounded every 15 seconds, and publishes study totals and the active virtual run position. Pull down on Friends to refresh manually.

Each account has a separate journey file on the device. At sign-in, the optional guest import copies the guest journey only when that account has no existing local journey. Whole-journey transfer between devices and iPhone/macOS sync remain future work. Shared progress is the latest snapshot published by a signed-in device.

Supabase's default email sender delivers confirmation emails to organization team members only. For other testers, configure a custom SMTP provider under Authentication → Emails. See [Supabase SMTP setup](https://supabase.com/docs/guides/auth/auth-smtp). Confirming the email in a browser is sufficient, then return to the app to sign in.

Pushes and pull requests run the simulator build check. A manual run of **Roam iOS Build** also runs the unit tests, including account cache isolation and virtual progress snapshots.

Group-run links can be tested in the simulator with:
`xcrun simctl openurl booted "roam://group?id=abc123&host=Sam&start=$(($(date +%s)+60))&km=5&pace=360"`

## Launch videos (Remotion)

`marketing/launch-video/` is a [Remotion](https://www.remotion.dev) project with two 1080×1920, 30 fps launch videos. Both use the same real app footage. Every cut and animation sits on the song's bar/beat grid.

| Composition | Song | Cut | Look |
|---|---|---|---|
| `RoamLaunch` | HEADLOCK by Luci Gang (130 BPM) | 0:59 → 1:38, 38.8 s. The breakdown, then the drop, then the 16-bar phrase | Kinetic type; R-O-A-M slams one letter per beat |
| `RoamLaunchMollyTalk` | MOLLY TALK by ISOxo (150 BPM, half-time) | 0:22 → 0:56, 33.6 s. The build, the silent pre-drop bar, drop 1 | Uppercase; 3·2·1 countdown on the silent bar, then "GO."; red/cyan glitch on heavy hits |

```sh
# 1. Put your licensed copies of the songs in marketing/launch-video/public/
#    as headlock.mp3 and molly-talk.mp3
# 2. (Re)generate the beat maps (stdlib Python + ffmpeg; --bpm N forces a tempo)
python3 marketing/analyze_song.py marketing/launch-video/public/headlock.mp3 marketing/launch-video/src/beats-headlock.json
python3 marketing/analyze_song.py marketing/launch-video/public/molly-talk.mp3 marketing/launch-video/src/beats-molly.json
# 3. Capture app footage from a booted simulator (screenshots, 3D run clips, share cards)
marketing/capture_assets.sh
# 4. Preview / render
cd marketing/launch-video && npm install
npm run studio            # live preview with a scrubbable timeline (both videos)
npm run render            # → out/roam-launch.mp4 and out/roam-launch-molly-talk.mp4
```

Each video is a "cut" in `src/cuts.tsx`: the song, the bar it starts on, its length, a look, and a scene list laid out in bars. Adding a version for another song means analyzing it, picking the bars, and writing a new cut. The songs and captured footage are gitignored.

Using commercial songs in public posts needs a license. Instagram and TikTok can also mute uploads that contain them. The alternative is to render without audio (`npx remotion render <id> out/silent.mp4 --muted`) and add the track from the platform's own music library: start HEADLOCK at 0:59.1 or MOLLY TALK at 0:22.4 and the cuts line up.

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
