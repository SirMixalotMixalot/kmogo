import React, { useMemo } from "react";
import { AbsoluteFill, Audio, interpolate, Sequence, staticFile, useCurrentFrame } from "remotion";
import { AbsFrame, Look, LookContext, Vignette } from "./components";
import { C, fontFamily } from "./theme";
import { Analysis, makeTimeline, TimelineContext } from "./timeline";

export type EditEntry = { bars: [number, number]; Scene: React.FC; name: string };

/** One video: a song, where in it to cut, a look, and scenes laid out in bars. */
export type Cut = {
  /** File in public/. */
  song: string;
  analysis: Analysis;
  /** Song bar the video starts on. */
  firstSongBar: number;
  totalBars: number;
  /** Seconds to shift the beat grid so the drop flash lands on the measured transient. */
  gridNudge?: number;
  look: Look;
  edit: EditEntry[];
};

export const cutDuration = (cut: Cut) =>
  makeTimeline(cut.analysis, cut.firstSongBar, cut.totalBars, cut.gridNudge).duration;

export const LaunchVideo: React.FC<{ cut: Cut }> = ({ cut }) => {
  const frame = useCurrentFrame();
  const timeline = useMemo(
    () => makeTimeline(cut.analysis, cut.firstSongBar, cut.totalBars, cut.gridNudge),
    [cut],
  );
  const fadeStart = timeline.beatFrame(cut.totalBars - 1); // fade over the last bar
  return (
    <TimelineContext.Provider value={timeline}>
      <LookContext.Provider value={cut.look}>
        <AbsFrame.Provider value={frame}>
          <AbsoluteFill style={{ background: C.night, fontFamily }}>
            <Audio
              src={staticFile(cut.song)}
              trimBefore={timeline.AUDIO_TRIM}
              volume={(f) =>
                interpolate(f, [0, 6, fadeStart, timeline.duration], [0, 1, 1, 0], { extrapolateRight: "clamp" })
              }
            />
            {cut.edit.map(({ bars: [a, b], Scene, name }) => (
              <Sequence key={name} name={name} from={timeline.barFrame(a)} durationInFrames={timeline.barFrame(b) - timeline.barFrame(a)}>
                <Scene />
              </Sequence>
            ))}
            <Vignette />
          </AbsoluteFill>
        </AbsFrame.Provider>
      </LookContext.Provider>
    </TimelineContext.Provider>
  );
};
