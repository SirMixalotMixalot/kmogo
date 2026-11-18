import { createContext, useContext } from "react";

/**
 * Everything in a video is timed against its song, in bars and beats.
 * Beat maps come from `marketing/analyze_song.py`; each cut picks the song bar
 * where the video starts and how many bars it runs.
 */
export const FPS = 30;

export type Analysis = {
  bpm: number;
  bars: number[];
  kickEnvelope: number[];
  energyEnvelope: number[];
  hitEnvelope?: number[];
};

/**
 * `gridNudge` (s) shifts the whole beat grid; onset detection can land a hair after
 * the true transient, so a cut can pull its grid onto the measured drop hit.
 */
export const makeTimeline = (analysis: Analysis, firstSongBar: number, totalBars: number, gridNudge = 0) => {
  const BEAT_S = 60 / analysis.bpm;
  const BAR_S = 4 * BEAT_S;
  /** Song time (s) where the video starts. */
  const SONG_START = analysis.bars[firstSongBar] + gridNudge;
  /** Frames of audio skipped at the start of the song. */
  const AUDIO_TRIM = Math.round(SONG_START * FPS);
  /** Song time (s) → composition frame. */
  const frameAtSong = (t: number) => Math.round(t * FPS) - AUDIO_TRIM;
  /** Start of video bar `v` as a song time. */
  const barTime = (v: number) => SONG_START + v * BAR_S;
  /** Absolute frame of video bar `v`, beat `k` (k may be fractional). */
  const beatFrame = (v: number, k = 0) => frameAtSong(barTime(v) + k * BEAT_S);
  const barFrame = (v: number) => beatFrame(v, 0);
  /** Frames from a scene's start to its beat `k` (tempo is constant). */
  const beats = (k: number) => Math.round(k * BEAT_S * FPS);
  const env = (arr: number[] | undefined, abs: number) => arr?.[abs + AUDIO_TRIM] ?? 0;
  return {
    bpm: analysis.bpm,
    BEAT_S,
    BAR_S,
    SONG_START,
    AUDIO_TRIM,
    totalBars,
    duration: barFrame(totalBars),
    frameAtSong,
    barTime,
    beatFrame,
    barFrame,
    beats,
    /** 0–1 kick-drum level (sustained bass included). */
    kickAt: (abs: number) => env(analysis.kickEnvelope, abs),
    /** 0–1 transient hits with fast decay (punches even over a sustained 808). */
    hitAt: (abs: number) => env(analysis.hitEnvelope ?? analysis.kickEnvelope, abs),
  };
};

export type Timeline = ReturnType<typeof makeTimeline>;

export const TimelineContext = createContext<Timeline | null>(null);

export const useTimeline = (): Timeline => {
  const t = useContext(TimelineContext);
  if (!t) throw new Error("useTimeline() must be used inside a <LaunchVideo> cut");
  return t;
};
