import React from "react";
import headlockBeats from "./beats-headlock.json";
import mollyBeats from "./beats-molly.json";
import { Cut, EditEntry, LaunchVideo } from "./LaunchVideo";
import {
  CardHeroScene,
  CardsFanScene,
  ColdOpen,
  CountdownColdOpen,
  DistanceScene,
  Drop,
  EndCard,
  ExploreScene,
  GoDrop,
  GroupScene,
  JourneyScene,
  LiveRunScene,
  PassportScene,
  ShopScene,
  StickerScene,
  StreetViewScene,
} from "./scenes";
import { Analysis } from "./timeline";

/** The feature run shared by both cuts: video bars 6–18 (one feature per bar, the live run gets two). */
const features: EditEntry[] = [
  { bars: [6, 7], Scene: DistanceScene, name: "30 min = 5K" },
  { bars: [7, 9], Scene: LiveRunScene, name: "Live 3D run" },
  { bars: [9, 10], Scene: StreetViewScene, name: "Street view" },
  { bars: [10, 11], Scene: ExploreScene, name: "Explore" },
  { bars: [11, 12], Scene: JourneyScene, name: "Journey" },
  { bars: [12, 13], Scene: PassportScene, name: "Passport" },
  { bars: [13, 14], Scene: GroupScene, name: "Group runs" },
  { bars: [14, 15], Scene: ShopScene, name: "Tickets" },
  { bars: [15, 16], Scene: CardsFanScene, name: "Run cards" },
  { bars: [16, 17], Scene: CardHeroScene, name: "8 hours = 80 km" },
  { bars: [17, 18], Scene: StickerScene, name: "Post it" },
];

/**
 * HEADLOCK — Luci Gang (130 BPM, bar ≈ 1.85 s).
 * Song bar 32 is the breakdown where the kick drops out; the drop hits 4 bars later
 * (≈66.5 s). 21 bars ≈ 38.8 s.
 */
export const headlock: Cut = {
  song: "headlock.mp3",
  analysis: headlockBeats as Analysis,
  firstSongBar: 32,
  totalBars: 21,
  look: { pulse: "kick", uppercase: false, glitch: false },
  edit: [
    { bars: [0, 4], Scene: ColdOpen, name: "Cold open (breakdown)" },
    { bars: [4, 6], Scene: Drop, name: "Drop: R-O-A-M" },
    ...features,
    { bars: [18, 21], Scene: EndCard, name: "End card" },
  ],
};

/**
 * MOLLY TALK — ISOxo (150 BPM, half-time; bar = 1.6 s = 48 frames exactly).
 * Song bars 14–15 close the build, bar 17 is near-silent, and drop 1 hits on bar 18
 * (28.8 s) — the biggest energy jump in the song — followed by 16 straight bars.
 * The cut ends as the energy falls away at bar 34. 21 bars = 33.6 s.
 */
export const mollyTalk: Cut = {
  song: "molly-talk.mp3",
  analysis: mollyBeats as Analysis,
  firstSongBar: 14,
  totalBars: 21,
  // The grid's bar 18 is 28.823 s; the drop transient measures 28.800 s.
  gridNudge: -0.023,
  look: { pulse: "hit", uppercase: true, glitch: true },
  edit: [
    { bars: [0, 4], Scene: CountdownColdOpen, name: "Cold open + 3·2·1" },
    { bars: [4, 6], Scene: GoDrop, name: "Drop: GO. / ROAM" },
    ...features,
    { bars: [18, 21], Scene: EndCard, name: "End card" },
  ],
};

export const HeadlockVideo: React.FC = () => <LaunchVideo cut={headlock} />;
export const MollyTalkVideo: React.FC = () => <LaunchVideo cut={mollyTalk} />;
