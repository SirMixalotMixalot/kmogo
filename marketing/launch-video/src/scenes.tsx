import React from "react";
import { AbsoluteFill, Img, interpolate, OffthreadVideo, Sequence, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import {
  Caption,
  fill,
  Flash,
  GlowBackdrop,
  Part,
  Phone,
  RouteBackdrop,
  TapRipple,
  useGlitchFilter,
  useHit,
  useLook,
  usePop,
  usePulse,
  useShake,
} from "./components";
import { C, fontFamily } from "./theme";
import { useTimeline } from "./timeline";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

const asset = {
  runUi: staticFile("clips/run-ui.mp4"),
  runClean: staticFile("clips/run-clean.mp4"),
  icon: staticFile("icon.png"),
  screen: (name: string) => staticFile(`screens/${name}.png`),
  card: (style: "route" | "map" | "sticker") => staticFile(`cards/card-${style}.png`),
};

// Layout of the phone in feature scenes.
const PHONE_W = 560;
const PHONE_TOP = 560;
const BEZEL = PHONE_W * 0.032;
const SCREEN_W = PHONE_W - BEZEL * 2;
/** Screenshot pixels (1179 wide) → on-screen pixels inside the phone. */
const SHOT_K = SCREEN_W / 1179;
/** Run-clip pixels (1080 wide) → on-screen pixels inside the phone. */
const CLIP_K = SCREEN_W / 1080;

// Spots inside the captured footage, in source pixels (measured from the captures).
const SETUP_5K_CHIP = { x: 624, y: 2146, w: 262, h: 166 }; // screenshot px
const EXPLORE_TAP = { x: 252, y: 855 }; // screenshot px — the route's turnaround on Bloor St W
const STREET_CARD = { x: 45, y: 325, w: 990, h: 358 }; // run-clip px

// ---------------------------------------------------------------------------
// Cold opens (4 bars before the drop)

/** Blurred night city behind the cold open. */
const ColdBackground: React.FC<{ rush: number; darken?: number }> = ({ rush, darken = 0 }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const bgScale = interpolate(frame, [0, durationInFrames], [1.25, 1.45]) + rush * 0.35;
  return (
    <AbsoluteFill
      style={{
        transform: `scale(${bgScale})`,
        filter: `blur(14px) brightness(${0.5 * (1 - darken)}) saturate(1.35)`,
      }}
    >
      <OffthreadVideo src={asset.runClean} muted style={fill} />
    </AbsoluteFill>
  );
};

export const HEADLOCK_LINES: Part[][] = [
  [{ text: "finals", beat: 0 }, { text: "week.", beat: 2 }],
  [{ text: "8 hours", beat: 0, accent: true }, { text: "of studying.", beat: 2 }],
  [{ text: "what if it", beat: 0 }, { text: "actually", beat: 2 }],
  [{ text: "got you", beat: 0 }, { text: "somewhere?", beat: 2, accent: true }],
];

/** Kinetic type, one line per bar; the last beat rushes toward the camera. */
export const ColdOpen: React.FC<{ lines?: Part[][] }> = ({ lines = HEADLOCK_LINES }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const { beats: beats_ } = useTimeline();
  const rush = interpolate(frame, [beats_(15), durationInFrames], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ background: C.night }}>
      <ColdBackground rush={rush} />
      <GlowBackdrop base={false} y={50} strength={interpolate(frame, [beats_(12), durationInFrames], [0.25, 1.1], clamp)} />
      {lines.map((parts, i) => (
        <Sequence key={i} from={beats_(i * 4)} durationInFrames={beats_((i + 1) * 4) - beats_(i * 4)} layout="none">
          <AbsoluteFill
            style={{
              justifyContent: "center",
              transform: i === lines.length - 1 ? `scale(${1 + rush * 0.6})` : undefined,
              filter: i === lines.length - 1 ? `blur(${rush * 14}px)` : undefined,
              opacity: i === lines.length - 1 ? 1 - rush * 0.7 : 1,
            }}
          >
            <Caption parts={parts} top={740} size={150} />
          </AbsoluteFill>
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};

export const MOLLY_LINES: Part[][] = [
  [{ text: "it's 2am.", beat: 0 }, { text: "finals week.", beat: 2 }],
  [{ text: "8 hours", beat: 0, accent: true }, { text: "to go.", beat: 2 }],
  [{ text: "so make it", beat: 0 }, { text: "a race.", beat: 2, accent: true }],
];

/**
 * Three bars of type, then the near-silent pre-drop bar becomes a race start:
 * 3 · 2 · 1 on its first three beats, a held breath on the fourth.
 */
export const CountdownColdOpen: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const { beats: beats_ } = useTimeline();
  const countdownStart = beats_(12);
  const darken = interpolate(frame, [countdownStart - 4, countdownStart + 4], [0, 0.65], clamp);
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      <ColdBackground rush={0} darken={darken} />
      <GlowBackdrop base={false} y={50} strength={interpolate(frame, [0, countdownStart], [0.2, 0.7], clamp) * (1 - darken * 0.6)} />
      {MOLLY_LINES.map((parts, i) => (
        <Sequence key={i} from={beats_(i * 4)} durationInFrames={beats_((i + 1) * 4) - beats_(i * 4)} layout="none">
          <AbsoluteFill style={{ justifyContent: "center" }}>
            <Caption parts={parts} top={740} size={124} />
          </AbsoluteFill>
        </Sequence>
      ))}
      {["3", "2", "1"].map((n, i) => (
        <Sequence key={n} from={beats_(12 + i)} durationInFrames={beats_(13 + i) - beats_(12 + i)} layout="none">
          <CountNumber n={n} last={i === 2} />
        </Sequence>
      ))}
      {/* The 4th beat: a held breath — a ring tightens toward the drop. */}
      <Sequence from={beats_(15)} durationInFrames={durationInFrames - beats_(15)} layout="none">
        <BreathRing />
      </Sequence>
    </AbsoluteFill>
  );
};

const CountNumber: React.FC<{ n: string; last: boolean }> = ({ n, last }) => {
  const s = usePop(0, { damping: 11, stiffness: 340, mass: 0.5 });
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const fade = interpolate(frame, [durationInFrames - 3, durationInFrames], [1, 0.0], clamp);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <div
        style={{
          fontFamily,
          fontWeight: 900,
          fontSize: 620,
          lineHeight: 1,
          color: last ? C.orange : C.white,
          opacity: interpolate(s, [0, 0.2], [0, 1], clamp) * fade,
          transform: `scale(${interpolate(s, [0, 1], [2.4, 1])})`,
          textShadow: `-10px 0 rgba(255,30,70,0.7), 10px 0 rgba(0,225,255,0.7), 0 20px 80px rgba(0,0,0,0.6)`,
        }}
      >
        {n}
      </div>
      <Flash frames={5} color="rgba(255,255,255,0.25)" />
    </AbsoluteFill>
  );
};

const BreathRing: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const t = interpolate(frame, [0, durationInFrames], [0, 1], clamp);
  const size = interpolate(t, [0, 1], [1500, 120]);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <div
        style={{
          width: size,
          height: size,
          borderRadius: 9999,
          border: `${interpolate(t, [0, 1], [6, 26])}px solid ${C.orange}`,
          opacity: interpolate(t, [0, 0.2, 1], [0, 0.9, 1]),
          boxShadow: `0 0 ${60 * t}px ${C.orange}`,
        }}
      />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------
// Drops (2 bars)

const DropBackground: React.FC<{ rate?: number }> = ({ rate = 1.4 }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const bgScale = interpolate(frame, [0, durationInFrames], [1.22, 1.02]);
  return (
    <>
      <AbsoluteFill style={{ transform: `scale(${bgScale})`, filter: "brightness(0.78) saturate(1.15)" }}>
        <OffthreadVideo src={asset.runClean} trimBefore={8 * 30} playbackRate={rate} muted style={fill} />
      </AbsoluteFill>
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(ellipse at 50% 44%, rgba(13,15,23,0.72) 0%, rgba(13,15,23,0.25) 45%, rgba(13,15,23,0) 70%), linear-gradient(180deg, rgba(13,15,23,0.55) 0%, rgba(13,15,23,0) 30%, rgba(13,15,23,0) 70%, rgba(13,15,23,0.7) 100%)",
        }}
      />
    </>
  );
};

const Tagline: React.FC<{ fromBeat: number }> = ({ fromBeat }) => {
  const { beats: beats_ } = useTimeline();
  return (
    <Sequence from={beats_(fromBeat)} layout="none">
      <Caption
        top={1210}
        size={84}
        parts={[
          { text: "study to run", beat: 0 },
          { text: "across the world.", beat: 2, accent: true },
        ]}
      />
    </Sequence>
  );
};

/** HEADLOCK: flash, shake, R-O-A-M slams one letter per beat. */
export const Drop: React.FC = () => {
  const pulse = usePulse();
  const shake = useShake(34, 16);
  const { beats: beats_ } = useTimeline();
  const icon = usePop(0, { damping: 11, stiffness: 200 });
  return (
    <AbsoluteFill style={{ background: C.night, transform: shake }}>
      <DropBackground />
      <AbsoluteFill style={{ alignItems: "center", top: 520 }}>
        <Img
          src={asset.icon}
          style={{
            width: 210,
            height: 210,
            borderRadius: 48,
            boxShadow: "0 30px 80px rgba(0,0,0,0.5)",
            transform: `scale(${icon * (1 + pulse * 0.05)}) rotate(${(1 - icon) * -20}deg)`,
          }}
        />
        <div style={{ display: "flex", marginTop: 30, transform: `scale(${1 + pulse * 0.04})` }}>
          {"ROAM".split("").map((letter, i) => (
            <SlamLetter key={i} letter={letter} beat={i} />
          ))}
        </div>
      </AbsoluteFill>
      <Tagline fromBeat={4} />
      {[1, 2, 3].map((b) => (
        <Sequence key={b} from={beats_(b)} durationInFrames={8} layout="none">
          <Flash frames={6} color="rgba(255,255,255,0.35)" />
        </Sequence>
      ))}
      <Flash frames={10} />
    </AbsoluteFill>
  );
};

const SlamLetter: React.FC<{ letter: string; beat: number }> = ({ letter, beat }) => {
  const { beats: beats_ } = useTimeline();
  const s = usePop(beats_(beat), { damping: 10, stiffness: 320, mass: 0.6 });
  return (
    <div
      style={{
        fontFamily,
        fontWeight: 900,
        fontSize: 250,
        lineHeight: 1,
        letterSpacing: 4,
        color: C.white,
        opacity: interpolate(s, [0, 0.2], [0, 1], clamp),
        transform: `scale(${interpolate(s, [0, 1], [3.2, 1])}) rotate(${(1 - s) * (beat % 2 ? 14 : -14)}deg)`,
        textShadow: "0 12px 50px rgba(0,0,0,0.6)",
        width: letter === "M" ? 230 : 190,
        textAlign: "center",
      }}
    >
      {letter}
    </div>
  );
};

/** MOLLY TALK: "GO." fills the frame on the drop, then ROAM slams in on beat 3. */
export const GoDrop: React.FC = () => {
  const frame = useCurrentFrame();
  const { beats: beats_ } = useTimeline();
  const pulse = usePulse();
  const glitch = useGlitchFilter(1.4);
  const shake = useShake(48, 18);
  const go = usePop(0, { damping: 12, stiffness: 380, mass: 0.5 });
  const goOut = interpolate(frame, [beats_(2) - 3, beats_(2) + 3], [0, 1], clamp);
  const word = usePop(beats_(2), { damping: 11, stiffness: 300, mass: 0.6 });
  const icon = usePop(beats_(2) + 2, { damping: 12, stiffness: 220 });
  return (
    <AbsoluteFill style={{ background: "#000", transform: shake }}>
      <DropBackground rate={1.8} />
      {/* GO. */}
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", filter: glitch }}>
        <div
          style={{
            fontFamily,
            fontWeight: 900,
            fontSize: 470,
            lineHeight: 1,
            letterSpacing: -6,
            color: C.orange,
            opacity: interpolate(go, [0, 0.15], [0, 1], clamp) * (1 - goOut),
            transform: `scale(${interpolate(go, [0, 1], [2.6, 1], clamp) * (1 + goOut * 1.4)})`,
            textShadow: "0 20px 90px rgba(0,0,0,0.7)",
          }}
        >
          GO.
        </div>
      </AbsoluteFill>
      {/* ROAM */}
      <AbsoluteFill style={{ alignItems: "center", top: 560, filter: glitch }}>
        <Img
          src={asset.icon}
          style={{
            width: 200,
            height: 200,
            borderRadius: 46,
            boxShadow: "0 30px 80px rgba(0,0,0,0.5)",
            opacity: icon,
            transform: `scale(${icon * (1 + pulse * 0.06)})`,
          }}
        />
        <div
          style={{
            marginTop: 26,
            fontFamily,
            fontWeight: 900,
            fontSize: 280,
            lineHeight: 1,
            letterSpacing: 8,
            color: C.white,
            opacity: interpolate(word, [0, 0.15], [0, 1], clamp),
            transform: `scale(${interpolate(word, [0, 1], [3, 1], clamp) * (1 + pulse * 0.05)})`,
            textShadow: "0 14px 60px rgba(0,0,0,0.65)",
          }}
        >
          ROAM
        </div>
      </AbsoluteFill>
      <Tagline fromBeat={4} />
      <Sequence from={beats_(2)} durationInFrames={10} layout="none">
        <Flash frames={8} color="rgba(255,255,255,0.7)" />
      </Sequence>
      <Flash frames={10} />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------
// Feature scenes: caption on top, phone below, entering on the bar line

type Enter = "up" | "left" | "right" | "zoom";

export const FeatureScene: React.FC<{
  caption: Part[];
  enter?: Enter;
  tilt?: number;
  seed?: number;
  children: React.ReactNode;
  /** Extra layers drawn in phone-screen coordinates (highlights, taps). */
  overlay?: React.ReactNode;
  captionSize?: number;
}> = ({ caption, enter = "up", tilt = 0, seed = 1, children, overlay, captionSize = 96 }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const pulse = usePulse();
  const hit = useHit();
  const { glitch } = useLook();
  const glitchFilter = useGlitchFilter();
  const s = usePop(0, { damping: 15, stiffness: 150, mass: 0.8 });
  const drift = interpolate(frame, [0, durationInFrames], [1, 1.035]);
  const punch = glitch ? 1 + hit * 0.035 : 1 + pulse * 0.012;
  const enterTransform = {
    up: `translateY(${(1 - s) * 1100}px)`,
    left: `translateX(${(1 - s) * -1000}px) rotate(${(1 - s) * -14}deg)`,
    right: `translateX(${(1 - s) * 1000}px) rotate(${(1 - s) * 14}deg)`,
    zoom: `scale(${0.55 + 0.45 * s})`,
  }[enter];
  const rotY = tilt * (1 - interpolate(frame, [0, durationInFrames], [0, 0.6]));
  return (
    <AbsoluteFill>
      <GlowBackdrop />
      <RouteBackdrop seed={seed} />
      <Caption parts={caption} size={captionSize} />
      <AbsoluteFill style={{ alignItems: "center", top: PHONE_TOP, perspective: 2400 }}>
        <div
          style={{
            transform: `${enterTransform} scale(${drift * punch}) rotateY(${rotY}deg) rotateX(${Math.abs(tilt) * 0.25}deg)`,
            opacity: interpolate(s, [0, 0.15], [0, 1], clamp),
            filter: glitchFilter,
          }}
        >
          <Phone width={PHONE_W}>
            {children}
            {overlay}
          </Phone>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const Screen: React.FC<{ name: string }> = ({ name }) => <Img src={asset.screen(name)} style={fill} />;

/** Pulsing orange ring around a spot in a screenshot, beating on every beat. */
const BeatRing: React.FC<{ rect: { x: number; y: number; w: number; h: number } }> = ({ rect }) => {
  const frame = useCurrentFrame();
  const { beats: beats_ } = useTimeline();
  const beat = beats_(1);
  const phase = (frame % beat) / beat;
  const appear = interpolate(frame, [beats_(1), beats_(1) + 6], [0, 1], clamp);
  return (
    <div
      style={{
        position: "absolute",
        left: rect.x * SHOT_K - 8,
        top: rect.y * SHOT_K - 8,
        width: rect.w * SHOT_K + 16,
        height: rect.h * SHOT_K + 16,
        borderRadius: 22,
        border: `5px solid ${C.orange}`,
        boxShadow: `0 0 ${30 * (1 - phase)}px ${C.orange}`,
        transform: `scale(${1 + (1 - phase) * 0.06})`,
        opacity: appear,
      }}
    />
  );
};

export const DistanceScene: React.FC = () => (
  <FeatureScene
    seed={2}
    caption={[
      { text: "30 min of studying", beat: 0 },
      { text: "= a 5K.", beat: 2, accent: true },
    ]}
    overlay={<BeatRing rect={SETUP_5K_CHIP} />}
  >
    <Screen name="setup" />
  </FeatureScene>
);

export const LiveRunScene: React.FC = () => {
  const { beats: beats_ } = useTimeline();
  return (
    <AbsoluteFill>
      <FeatureScene seed={3} enter="right" tilt={-16} caption={[]}>
        <OffthreadVideo src={asset.runUi} trimBefore={30} playbackRate={1.3} muted style={fill} />
      </FeatureScene>
      <Sequence durationInFrames={beats_(4)} layout="none">
        <Caption
          parts={[
            { text: "real streets.", beat: 0 },
            { text: "in 3D.", beat: 2, accent: true },
          ]}
        />
      </Sequence>
      <Sequence from={beats_(4)} layout="none">
        <Caption
          parts={[
            { text: "every minute you study", beat: 0 },
            { text: "moves you.", beat: 2, accent: true },
          ]}
          size={88}
        />
      </Sequence>
    </AbsoluteFill>
  );
};

/** Zooms from the phone into the live street-view card. */
export const StreetViewScene: React.FC = () => {
  const zoom = usePop(2, { damping: 18, stiffness: 120 });
  const glitchFilter = useGlitchFilter(0.6);
  const z = interpolate(zoom, [0, 1], [1, 2.05]);
  const dropY = interpolate(zoom, [0, 1], [0, 240]);
  const cx = BEZEL + (STREET_CARD.x + STREET_CARD.w / 2) * CLIP_K;
  const cy = BEZEL + (STREET_CARD.y + STREET_CARD.h / 2) * CLIP_K;
  return (
    <AbsoluteFill>
      <GlowBackdrop y={45} />
      <RouteBackdrop seed={4} />
      <AbsoluteFill style={{ alignItems: "center", top: PHONE_TOP, filter: glitchFilter }}>
        <div style={{ transform: `translateY(${dropY}px) scale(${z})`, transformOrigin: `${cx}px ${cy}px` }}>
          <Phone width={PHONE_W}>
            <OffthreadVideo src={asset.runUi} trimBefore={5 * 30} muted style={fill} />
          </Phone>
        </div>
      </AbsoluteFill>
      <AbsoluteFill
        style={{ background: `linear-gradient(180deg, ${C.night} 0%, rgba(13,15,23,0.85) 22%, rgba(13,15,23,0) 34%)` }}
      />
      <Caption
        parts={[
          { text: "live street view", beat: 0 },
          { text: "as you go.", beat: 2, accent: true },
        ]}
      />
    </AbsoluteFill>
  );
};

export const ExploreScene: React.FC = () => {
  const { beats: beats_ } = useTimeline();
  return (
    <FeatureScene
      seed={5}
      enter="left"
      tilt={12}
      caption={[
        { text: "tap anywhere.", beat: 0 },
        { text: "run there.", beat: 2, accent: true },
      ]}
      overlay={
        <>
          <TapRipple x={EXPLORE_TAP.x * SHOT_K} y={EXPLORE_TAP.y * SHOT_K} delay={beats_(0.5)} />
          <TapRipple x={EXPLORE_TAP.x * SHOT_K} y={EXPLORE_TAP.y * SHOT_K} delay={beats_(2.5)} />
        </>
      }
    >
      <Screen name="explore" />
    </FeatureScene>
  );
};

export const JourneyScene: React.FC = () => (
  <FeatureScene
    seed={6}
    enter="zoom"
    caption={[
      { text: "a week of studying", beat: 0 },
      { text: "= Waterloo → Toronto.", beat: 2, accent: true },
    ]}
    captionSize={84}
  >
    <Screen name="journey" />
  </FeatureScene>
);

export const PassportScene: React.FC = () => (
  <FeatureScene
    seed={7}
    enter="right"
    tilt={-10}
    caption={[
      { text: "collect", beat: 0 },
      { text: "every city.", beat: 2, accent: true },
    ]}
  >
    <Screen name="passport" />
  </FeatureScene>
);

export const GroupScene: React.FC = () => (
  <FeatureScene
    seed={8}
    enter="up"
    caption={[
      { text: "group runs.", beat: 0 },
      { text: "same start.", beat: 1 },
      { text: "same finish.", beat: 2, accent: true },
    ]}
    captionSize={82}
  >
    <Screen name="lobby" />
  </FeatureScene>
);

export const ShopScene: React.FC = () => (
  <FeatureScene
    seed={9}
    enter="left"
    tilt={10}
    caption={[
      { text: "too slow?", beat: 0 },
      { text: "take the train.", beat: 2, accent: true },
    ]}
  >
    <Screen name="shop" />
  </FeatureScene>
);

// ---------------------------------------------------------------------------
// Share cards

const CARD_ASPECT = 1920 / 1080;

const Card: React.FC<{ style: "route" | "map" | "sticker"; width: number }> = ({ style, width }) => (
  <div
    style={{
      width,
      height: width * CARD_ASPECT,
      borderRadius: width * 0.06,
      overflow: "hidden",
      position: "relative",
      boxShadow: "0 40px 100px rgba(0,0,0,0.55)",
      background: C.night,
    }}
  >
    {style === "sticker" && (
      <OffthreadVideo src={asset.runClean} trimBefore={15 * 30} muted style={{ ...fill, position: "absolute" }} />
    )}
    <Img src={asset.card(style)} style={{ ...fill, position: "absolute" }} />
  </div>
);

export const CardsFanScene: React.FC = () => {
  const layout = [
    { style: "map" as const, x: -300, rot: -11, y: 70, beat: 1 },
    { style: "sticker" as const, x: 300, rot: 11, y: 70, beat: 2 },
    { style: "route" as const, x: 0, rot: 0, y: 0, beat: 0 },
  ];
  const { beats: beats_ } = useTimeline();
  const pulse = usePulse();
  const glitchFilter = useGlitchFilter(0.8);
  const punch = usePop(beats_(3), { damping: 9, stiffness: 300 });
  return (
    <AbsoluteFill>
      <GlowBackdrop y={60} strength={1.2} />
      <RouteBackdrop seed={10} />
      <Caption
        parts={[
          { text: "every session", beat: 0 },
          { text: "gets a run card.", beat: 2, accent: true },
        ]}
      />
      <AbsoluteFill style={{ top: 560, alignItems: "center", filter: glitchFilter }}>
        <div style={{ position: "relative", width: 1, height: 1, transform: `scale(${1 + punch * 0.03 + pulse * 0.01})` }}>
          {layout.map((c) => (
            <FanCard key={c.style} {...c} />
          ))}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const FanCard: React.FC<{ style: "route" | "map" | "sticker"; x: number; rot: number; y: number; beat: number }> = ({
  style,
  x,
  rot,
  y,
  beat,
}) => {
  const { beats: beats_ } = useTimeline();
  const s = usePop(beats_(beat), { damping: 13, stiffness: 190 });
  const w = style === "route" ? 420 : 360;
  return (
    <div
      style={{
        position: "absolute",
        left: x - w / 2,
        top: y + (1 - s) * 1200,
        transform: `rotate(${rot * s}deg)`,
        opacity: interpolate(s, [0, 0.1], [0, 1], clamp),
      }}
    >
      <Card style={style} width={w} />
    </div>
  );
};

export const CardHeroScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const glitchFilter = useGlitchFilter(0.8);
  const s = usePop(0, { damping: 16, stiffness: 140 });
  const w = interpolate(s, [0, 1], [420, 640]);
  const drift = interpolate(frame, [0, durationInFrames], [0, -40]);
  return (
    <AbsoluteFill>
      <GlowBackdrop y={62} strength={1.3} />
      <RouteBackdrop seed={11} />
      <Caption
        parts={[
          { text: "8 hours of studying", beat: 0 },
          { text: "= 80 km.", beat: 2, accent: true },
        ]}
        size={90}
      />
      <AbsoluteFill style={{ alignItems: "center", top: 520 + drift, filter: glitchFilter }}>
        <div style={{ transform: `rotate(${(1 - s) * -4}deg)` }}>
          <Card style="route" width={w} />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/** The transparent sticker over "your photo" — how it lands in a story. */
export const StickerScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const s = usePop(0, { damping: 12, stiffness: 200 });
  return (
    <AbsoluteFill style={{ background: C.night }}>
      <AbsoluteFill style={{ transform: `scale(${interpolate(frame, [0, durationInFrames], [1.15, 1.05])})` }}>
        <OffthreadVideo src={asset.runClean} trimBefore={16 * 30} muted style={fill} />
      </AbsoluteFill>
      <AbsoluteFill
        style={{ background: "linear-gradient(180deg, rgba(0,0,0,0.7) 0%, rgba(0,0,0,0.35) 22%, rgba(0,0,0,0) 40%)" }}
      />
      <AbsoluteFill style={{ transform: `scale(${interpolate(s, [0, 1], [1.4, 0.94])})`, opacity: s }}>
        <Img src={asset.card("sticker")} style={fill} />
      </AbsoluteFill>
      <Caption
        parts={[
          { text: "post it.", beat: 1 },
          { text: "flex it.", beat: 2, accent: true },
        ]}
        size={110}
      />
      <Flash frames={7} color="rgba(255,255,255,0.5)" />
    </AbsoluteFill>
  );
};

// ---------------------------------------------------------------------------
// End card

export const EndCard: React.FC = () => {
  const pulse = usePulse();
  const { beats: beats_ } = useTimeline();
  const icon = usePop(0, { damping: 11, stiffness: 160 });
  const word = usePop(beats_(1), { damping: 13, stiffness: 180 });
  const tag = usePop(beats_(2), { damping: 16 });
  const pill = usePop(beats_(4), { damping: 14 });
  return (
    <AbsoluteFill>
      <GlowBackdrop y={40} strength={1.5} />
      <RouteBackdrop seed={12} opacity={0.2} />
      <AbsoluteFill style={{ alignItems: "center", top: 470, fontFamily }}>
        <Img
          src={asset.icon}
          style={{
            width: 300,
            height: 300,
            borderRadius: 68,
            boxShadow: "0 40px 120px rgba(255,107,44,0.35), 0 30px 80px rgba(0,0,0,0.6)",
            transform: `scale(${icon * (1 + pulse * 0.04)})`,
          }}
        />
        <div
          style={{
            marginTop: 50,
            fontSize: 200,
            fontWeight: 900,
            color: C.white,
            letterSpacing: -2,
            lineHeight: 1,
            opacity: word,
            transform: `translateY(${(1 - word) * 60}px)`,
          }}
        >
          Roam
        </div>
        <div
          style={{
            marginTop: 26,
            fontSize: 58,
            fontWeight: 800,
            color: C.muted,
            opacity: tag,
            transform: `translateY(${(1 - tag) * 40}px)`,
          }}
        >
          study to run across the world.
        </div>
        <div
          style={{
            marginTop: 90,
            padding: "26px 54px",
            borderRadius: 999,
            border: `4px solid ${C.orange}`,
            color: C.white,
            fontSize: 46,
            fontWeight: 800,
            background: "rgba(255,107,44,0.14)",
            opacity: pill,
            transform: `scale(${0.8 + 0.2 * pill})`,
          }}
        >
          Coming soon to the App Store
        </div>
      </AbsoluteFill>
      <Flash frames={8} color="rgba(255,255,255,0.6)" />
    </AbsoluteFill>
  );
};
