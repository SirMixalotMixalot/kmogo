import React, { createContext, useContext } from "react";
import { AbsoluteFill, interpolate, random, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { C, fontFamily } from "./theme";
import { useTimeline } from "./timeline";

// ---------------------------------------------------------------------------
// Context: absolute frame + per-cut look

/** Absolute composition frame (useCurrentFrame() is relative inside a Sequence). */
export const AbsFrame = createContext(0);

/** Visual personality of a cut. */
export type Look = {
  /** What drives glows and bumps: the kick level, or transient hits (better over sustained 808s). */
  pulse: "kick" | "hit";
  /** Uppercase captions. */
  uppercase: boolean;
  /** Red/cyan split and punch-zoom on heavy hits. */
  glitch: boolean;
};

export const LookContext = createContext<Look>({ pulse: "kick", uppercase: false, glitch: false });
export const useLook = () => useContext(LookContext);

/** Transient hit level right now, 0–1. */
export const useHit = () => {
  const t = useTimeline();
  return Math.min(1, t.hitAt(useContext(AbsFrame)) * 1.6);
};

/** Audio-reactive level for glows and bumps, 0–1. */
export const usePulse = () => {
  const t = useTimeline();
  const abs = useContext(AbsFrame);
  const hit = useHit();
  return useLook().pulse === "hit" ? hit : t.kickAt(abs);
};

/** CSS filter that splits an element red/cyan on heavy hits (glitch looks only). */
export const useGlitchFilter = (gain = 1): string | undefined => {
  const hit = useHit();
  const { glitch } = useLook();
  if (!glitch || hit < 0.12) return undefined;
  const x = 16 * hit * gain;
  return `drop-shadow(${-x}px 0 rgba(255,30,70,0.8)) drop-shadow(${x}px 0 rgba(0,225,255,0.8))`;
};

/** Spring that starts `delay` frames into the current Sequence. */
export const usePop = (delay: number, config: { damping?: number; stiffness?: number; mass?: number } = {}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config: { damping: 14, stiffness: 170, mass: 0.7, ...config } });
};

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

// ---------------------------------------------------------------------------
// Phone mockup (iPhone 15 Pro proportions; screenshots are 1179×2556)

export const SCREEN_ASPECT = 1179 / 2556;

export const Phone: React.FC<{ width: number; children: React.ReactNode; style?: React.CSSProperties }> = ({
  width,
  children,
  style,
}) => {
  const bezel = width * 0.032;
  const screenW = width - bezel * 2;
  const screenH = screenW / SCREEN_ASPECT;
  const radius = width * 0.165;
  return (
    <div
      style={{
        width,
        height: screenH + bezel * 2,
        borderRadius: radius,
        padding: bezel,
        background: "linear-gradient(145deg, #3a3a40, #121215 40%, #2b2b30)",
        boxShadow: "0 50px 140px rgba(0,0,0,0.6), 0 0 0 3px #4a4a52 inset",
        position: "relative",
        ...style,
      }}
    >
      <div
        style={{
          width: screenW,
          height: screenH,
          borderRadius: radius - bezel,
          overflow: "hidden",
          position: "relative",
          background: "#000",
        }}
      >
        {children}
        {/* Dynamic Island */}
        <div
          style={{
            position: "absolute",
            top: screenW * 0.028,
            left: (screenW - screenW * 0.32) / 2,
            width: screenW * 0.32,
            height: screenW * 0.094,
            borderRadius: 999,
            background: "#000",
          }}
        />
      </div>
    </div>
  );
};

export const fill: React.CSSProperties = { width: "100%", height: "100%", objectFit: "cover" };

// ---------------------------------------------------------------------------
// Captions: each part lands on a beat (beats counted from the scene start)

export type Part = { text: string; beat: number; accent?: boolean };

export const Caption: React.FC<{ parts: Part[]; top?: number; size?: number; align?: "center" | "left" }> = ({
  parts,
  top = 190,
  size = 96,
  align = "center",
}) => {
  const pulse = usePulse();
  const hit = useHit();
  const look = useLook();
  const split = look.glitch && hit > 0.12 ? 7 * hit : 0;
  return (
    <div
      style={{
        position: "absolute",
        top,
        left: 70,
        right: 70,
        textAlign: align,
        fontFamily,
        fontWeight: 900,
        fontSize: look.uppercase ? size * 0.9 : size,
        lineHeight: 1.02,
        letterSpacing: look.uppercase ? 0 : -1.5,
        textTransform: look.uppercase ? "uppercase" : "none",
        color: C.white,
        textShadow: split
          ? `${-split}px 0 rgba(255,30,70,0.85), ${split}px 0 rgba(0,225,255,0.85), 0 8px 40px rgba(0,0,0,0.55)`
          : "0 8px 40px rgba(0,0,0,0.55)",
      }}
    >
      {parts.map((p, i) => (
        <CaptionLine key={i} part={p} pulse={pulse} />
      ))}
    </div>
  );
};

const CaptionLine: React.FC<{ part: Part; pulse: number }> = ({ part, pulse }) => {
  const { beats } = useTimeline();
  const s = usePop(beats(part.beat), { damping: 12, stiffness: 220 });
  return (
    <div
      style={{
        opacity: interpolate(s, [0, 0.4], [0, 1], clamp),
        transform: `translateY(${(1 - s) * 60}px) scale(${0.85 + 0.15 * s + (part.accent ? pulse * 0.03 : 0)})`,
        color: part.accent ? C.orange : C.white,
      }}
    >
      {part.text}
    </div>
  );
};

// ---------------------------------------------------------------------------
// Backgrounds

/**
 * Orange glow that breathes with the music, over the night gradient.
 * `base={false}` draws only the glow, so footage underneath stays visible.
 */
export const GlowBackdrop: React.FC<{ y?: number; strength?: number; base?: boolean }> = ({
  y = 62,
  strength = 1,
  base = true,
}) => {
  const pulse = usePulse();
  const glow = (0.22 + pulse * 0.28) * strength;
  const radial = `radial-gradient(circle at 50% ${y}%, rgba(255,107,44,${glow}) 0%, rgba(255,107,44,0) 55%)`;
  return (
    <AbsoluteFill
      style={{ background: base ? `${radial}, linear-gradient(170deg, ${C.dusk} 0%, ${C.night} 60%)` : radial }}
    />
  );
};

/** Faint winding routes that draw themselves across the frame — on-brand texture. */
export const RouteBackdrop: React.FC<{ seed?: number; opacity?: number }> = ({ seed = 1, opacity = 0.16 }) => {
  const frame = useCurrentFrame();
  const paths = [0, 1, 2].map((i) => {
    const r = (k: number) => random(`route-${seed}-${i}-${k}`);
    const y0 = 200 + i * 620 + r(0) * 200;
    return `M -60 ${y0} C ${260 + r(1) * 200} ${y0 - 300 + r(2) * 200}, ${560 + r(3) * 200} ${y0 + 400 - r(4) * 300}, ${
      1140
    } ${y0 + 120 - r(5) * 240}`;
  });
  return (
    <AbsoluteFill>
      <svg width={1080} height={1920} style={{ position: "absolute", inset: 0 }}>
        {paths.map((d, i) => {
          const progress = interpolate(frame, [i * 6, i * 6 + 45], [0, 1], clamp);
          return (
            <path
              key={i}
              d={d}
              pathLength={1}
              fill="none"
              stroke={C.orange}
              strokeOpacity={opacity}
              strokeWidth={10}
              strokeLinecap="round"
              strokeDasharray={1}
              strokeDashoffset={1 - progress}
            />
          );
        })}
      </svg>
    </AbsoluteFill>
  );
};

export const Vignette: React.FC = () => (
  <AbsoluteFill
    style={{
      pointerEvents: "none",
      background: "radial-gradient(ellipse at 50% 45%, rgba(0,0,0,0) 55%, rgba(0,0,0,0.55) 100%)",
    }}
  />
);

// ---------------------------------------------------------------------------
// Hits

/** White flash that decays over `frames` (put it at the start of a Sequence). */
export const Flash: React.FC<{ frames?: number; color?: string }> = ({ frames = 9, color = "#fff" }) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, frames], [0.95, 0], clamp);
  return <AbsoluteFill style={{ background: color, opacity, pointerEvents: "none" }} />;
};

/** Camera shake that decays after a hit. */
export const useShake = (amplitude = 28, frames = 14) => {
  const frame = useCurrentFrame();
  const decay = interpolate(frame, [0, frames], [1, 0], clamp);
  const x = (random(`sx-${frame}`) - 0.5) * 2 * amplitude * decay;
  const y = (random(`sy-${frame}`) - 0.5) * 2 * amplitude * decay;
  return `translate(${x}px, ${y}px)`;
};

/** A tap ripple (two rings) at a point, starting `delay` frames into the scene. */
export const TapRipple: React.FC<{ x: number; y: number; delay: number }> = ({ x, y, delay }) => {
  const frame = useCurrentFrame() - delay;
  if (frame < 0) return null;
  const rings = [0, 7].map((offset) => {
    const t = interpolate(frame - offset, [0, 22], [0, 1], clamp);
    return (
      <div
        key={offset}
        style={{
          position: "absolute",
          left: x - 60,
          top: y - 60,
          width: 120,
          height: 120,
          borderRadius: 999,
          border: `8px solid ${C.orange}`,
          opacity: 1 - t,
          transform: `scale(${0.3 + t * 1.2})`,
        }}
      />
    );
  });
  const dot = interpolate(frame, [0, 4, 14], [0, 1, 0.85], clamp);
  return (
    <>
      {rings}
      <div
        style={{
          position: "absolute",
          left: x - 26,
          top: y - 26,
          width: 52,
          height: 52,
          borderRadius: 999,
          background: "rgba(255,255,255,0.9)",
          boxShadow: "0 4px 20px rgba(0,0,0,0.4)",
          transform: `scale(${dot})`,
        }}
      />
    </>
  );
};
