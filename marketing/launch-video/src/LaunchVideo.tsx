import React from "react";
import { AbsoluteFill, Audio, interpolate, Sequence, staticFile, useCurrentFrame } from "remotion";
import { AbsFrame, Vignette } from "./components";
import {
  CardHeroScene,
  CardsFanScene,
  ColdOpen,
  DistanceScene,
  Drop,
  EndCard,
  ExploreScene,
  GroupScene,
  JourneyScene,
  LiveRunScene,
  PassportScene,
  ShopScene,
  StickerScene,
  StreetViewScene,
} from "./scenes";
import { C, fontFamily } from "./theme";
import { AUDIO_TRIM, barFrame, beatFrame, DURATION, TOTAL_BARS } from "./timeline";

/** The edit, in video bars (1 bar ≈ 1.85 s). Bar 0 = song breakdown, bar 4 = the drop. */
const EDIT: { bars: [number, number]; Scene: React.FC; name: string }[] = [
  { bars: [0, 4], Scene: ColdOpen, name: "Cold open (breakdown)" },
  { bars: [4, 6], Scene: Drop, name: "Drop: ROAM" },
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
  { bars: [18, TOTAL_BARS], Scene: EndCard, name: "End card" },
];

export const LaunchVideo: React.FC = () => {
  const frame = useCurrentFrame();
  const fadeStart = beatFrame(TOTAL_BARS - 1); // fade over the last bar
  return (
    <AbsFrame.Provider value={frame}>
      <AbsoluteFill style={{ background: C.night, fontFamily }}>
        <Audio
          src={staticFile("song.mp3")}
          trimBefore={AUDIO_TRIM}
          volume={(f) => interpolate(f, [0, 6, fadeStart, DURATION], [0, 1, 1, 0], { extrapolateRight: "clamp" })}
        />
        {EDIT.map(({ bars: [a, b], Scene, name }) => (
          <Sequence key={name} name={name} from={barFrame(a)} durationInFrames={barFrame(b) - barFrame(a)}>
            <Scene />
          </Sequence>
        ))}
        <Vignette />
      </AbsoluteFill>
    </AbsFrame.Provider>
  );
};
