import beats from "./beats.json";

/**
 * Everything in the video is timed against the song, in bars and beats.
 *
 * `beats.json` comes from `marketing/analyze_song.py` (≈130 BPM). The cut we
 * use starts at song bar 32 — the breakdown where the kick drops out — so the
 * cold open plays over the tension and the logo lands on the drop four bars
 * later (song bar 36, ≈66.5 s).
 */
export const FPS = 30;
export const BPM = beats.bpm;
export const BEAT_S = 60 / BPM;
export const BAR_S = 4 * BEAT_S;

const FIRST_SONG_BAR = 32;
/** Song time (s) where the video starts. */
export const SONG_START = beats.bars[FIRST_SONG_BAR];
/** Frames of audio skipped at the start of the song. */
export const AUDIO_TRIM = Math.round(SONG_START * FPS);

/** Song time (s) → composition frame. */
export const frameAtSong = (t: number) => Math.round(t * FPS) - AUDIO_TRIM;
/** Start of video bar `v` (0 = breakdown, 4 = drop), as a song time. */
export const barTime = (v: number) => SONG_START + v * BAR_S;
/** Absolute frame of video bar `v`, beat `k` (k may be fractional). */
export const beatFrame = (v: number, k = 0) => frameAtSong(barTime(v) + k * BEAT_S);
export const barFrame = (v: number) => beatFrame(v, 0);
/** Frames from a scene's start to its beat `k` (tempo is constant). */
export const beats_ = (k: number) => Math.round(k * BEAT_S * FPS);

export const DROP_BAR = 4;
/** 4-bar cold open + the 16-bar phrase after the drop + 1 bar for the end card to breathe. */
export const TOTAL_BARS = 21;
export const DURATION = barFrame(TOTAL_BARS);

/** 0–1 kick-drum envelope at an absolute frame — drives audio-reactive motion. */
export const kickAt = (absFrame: number) => beats.kickEnvelope[absFrame + AUDIO_TRIM] ?? 0;
export const energyAt = (absFrame: number) => beats.energyEnvelope[absFrame + AUDIO_TRIM] ?? 0;
