#!/usr/bin/env python3
"""Beat / section analysis for the launch-video soundtrack. Stdlib only (plus ffmpeg).

    python3 marketing/analyze_song.py song.mp3 out.json

Writes tempo, a beat grid, bar (downbeat) times, kick hits, a per-bar energy map
and 30 fps envelopes used to drive cuts and audio-reactive motion in Remotion.
"""
import array
import json
import math
import subprocess
import sys

SR = 11025          # analysis sample rate
HOP = 256           # ~23 ms envelope frames
ENV_FPS = SR / HOP  # ~43.07 envelope frames per second
VIDEO_FPS = 30


def decode(path, filt=None):
    af = f"{filt},aresample={SR}" if filt else f"aresample={SR}"
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-af", af, "-ac", "1", "-f", "s16le", "-"],
                         capture_output=True, check=True).stdout
    a = array.array("h")
    a.frombytes(raw)
    return a


def rms_envelope(samples):
    out = []
    for i in range(len(samples) // HOP):
        seg = samples[i * HOP:(i + 1) * HOP]
        out.append(math.sqrt(sum(x * x for x in seg) / HOP) / 32768)
    return out


def onset_strength(env):
    """Positive log-energy rise relative to the previous few frames."""
    eps = 1e-4
    out = [0.0] * len(env)
    for i in range(3, len(env)):
        prev = sum(env[i - 3:i]) / 3
        out[i] = max(0.0, math.log(env[i] + eps) - math.log(prev + eps))
    return out


def sample_at(sig, pos):
    i = int(pos)
    if i < 0 or i + 1 >= len(sig):
        return 0.0
    t = pos - i
    return sig[i] * (1 - t) + sig[i + 1] * t


def grid_score(onset, bpm, phase):
    period = ENV_FPS * 60 / bpm
    s, pos = 0.0, phase
    while pos < len(onset) - 1:
        # take the best value within ±1 frame to tolerate tiny drift
        s += max(sample_at(onset, pos - 1), sample_at(onset, pos), sample_at(onset, pos + 1))
        pos += period
    return s


def best_phase(onset, bpm, step=0.5):
    period = ENV_FPS * 60 / bpm
    best = (0.0, -1.0)
    ph = 0.0
    while ph < period:
        sc = grid_score(onset, bpm, ph)
        if sc > best[1]:
            best = (ph, sc)
        ph += step
    return best


def main():
    path, out_path = sys.argv[1], sys.argv[2]
    full = rms_envelope(decode(path))
    kick = rms_envelope(decode(path, "lowpass=f=150,lowpass=f=150"))
    high = rms_envelope(decode(path, "highpass=f=1800"))
    n = min(len(full), len(kick), len(high))
    full, kick, high = full[:n], kick[:n], high[:n]
    duration = n / ENV_FPS

    on_kick, on_high = onset_strength(kick), onset_strength(high)
    onset = [on_kick[i] * 0.65 + on_high[i] * 0.35 for i in range(n)]

    # --- tempo: autocorrelation, then fine comb search -----------------------
    mean = sum(onset) / n
    o = [x - mean for x in onset]
    ac = {}
    for lag in range(int(ENV_FPS * 60 / 200), int(ENV_FPS * 60 / 55) + 1):
        ac[lag] = sum(o[i] * o[i + lag] for i in range(n - lag))
    top = sorted(ac, key=ac.get, reverse=True)[:5]
    candidates = sorted({round(ENV_FPS * 60 / lag, 1) for lag in top})
    print("autocorrelation tempo candidates:", candidates)

    scored = []
    for c in candidates:
        for mult in (0.5, 1, 2):
            base = c * mult
            if not 60 <= base <= 200:
                continue
            best = (base, 0.0, -1.0)
            b = base - 1.5
            while b <= base + 1.5:
                ph, sc = best_phase(onset, b, step=1.0)
                # normalise by number of beats so faster grids don't win just by count
                norm = sc / (duration * b / 60)
                if norm > best[2]:
                    best = (b, ph, norm)
                b += 0.05
            scored.append(best)
    scored.sort(key=lambda x: x[2], reverse=True)
    for b, ph, sc in scored[:6]:
        print(f"  grid {b:7.2f} bpm  phase {ph / ENV_FPS:6.3f}s  score/beat {sc:.4f}")

    # Prefer a musically sensible tempo (80–180 bpm). But half-time tracks (trap,
    # dubstep at 140–150) often score far better on a 70–75 bpm grid; when an
    # out-of-range grid wins by a wide margin, double it instead of discarding it.
    sensible = [s for s in scored if 80 <= s[0] <= 180]
    best = scored[0]
    if "--bpm" in sys.argv:
        bpm = float(sys.argv[sys.argv.index("--bpm") + 1])
        phase, _ = best_phase(onset, bpm, step=0.25)
        print(f"tempo forced to {bpm} bpm")
    elif sensible and (best in sensible or best[2] < 1.3 * sensible[0][2]):
        bpm = sensible[0][0]
        phase, _ = best_phase(onset, bpm, step=0.25)
    else:
        bpm = best[0]
        phase, _ = best_phase(onset, bpm, step=0.25)
        while bpm < 100:
            bpm *= 2
        phase %= ENV_FPS * 60 / bpm
        print(f"half-time grid {best[0]:.2f} bpm wins clearly → using {bpm:.2f} bpm")
    period = ENV_FPS * 60 / bpm
    beats = []
    pos = phase
    while pos < n:
        beats.append(pos / ENV_FPS)
        pos += period

    # --- downbeats ---------------------------------------------------------------
    # Sections (breakdowns, drops) start on bar lines, so the right downbeat phase
    # is the one where bar-to-bar kick energy changes most sharply. Override with
    # --downbeat <seconds> to force a bar line through a specific moment.
    def kick_avg(t0, t1):
        a, b = int(t0 * ENV_FPS), max(int(t0 * ENV_FPS) + 1, int(t1 * ENV_FPS))
        seg = kick[a:b]
        return sum(seg) / len(seg) if seg else 0.0
    bar_len = 4 * 60 / bpm
    phase_scores = []
    for k in range(4):
        starts = beats[k::4]
        e = [kick_avg(t, t + bar_len) for t in starts]
        phase_scores.append(sum(abs(e[i] - e[i - 1]) for i in range(1, len(e))))
    k0 = max(range(4), key=lambda k: phase_scores[k])
    if "--downbeat" in sys.argv:
        anchor = float(sys.argv[sys.argv.index("--downbeat") + 1])
        nearest = min(range(len(beats)), key=lambda i: abs(beats[i] - anchor))
        k0 = nearest % 4
    bars = beats[k0::4]
    print(f"\nchosen tempo {bpm:.2f} bpm, first beat {beats[0]:.3f}s, downbeat offset {k0} (boundary scores {[round(s, 4) for s in phase_scores]})")

    # --- per-bar energy map ---------------------------------------------------
    def avg(sig, t0, t1):
        a, b = int(t0 * ENV_FPS), max(int(t0 * ENV_FPS) + 1, int(t1 * ENV_FPS))
        seg = sig[a:b]
        return sum(seg) / len(seg) if seg else 0.0

    bar_info = []
    mx = max(avg(full, t, t + bar_len) for t in bars) or 1
    mk = max(avg(kick, t, t + bar_len) for t in bars) or 1
    mh = max(avg(high, t, t + bar_len) for t in bars) or 1
    print("\nbar   time    full                  kick                  high")
    for i, t in enumerate(bars):
        f, k, h = avg(full, t, t + bar_len) / mx, avg(kick, t, t + bar_len) / mk, avg(high, t, t + bar_len) / mh
        bar_info.append({"index": i, "time": round(t, 3), "full": round(f, 3), "kick": round(k, 3), "high": round(h, 3)})
        print(f"{i:3d} {t:7.2f}s  {'#' * int(f * 20):20s}  {'#' * int(k * 20):20s}  {'#' * int(h * 20):20s}")

    # --- drops: biggest energy jumps between consecutive 2-bar windows --------
    jumps = []
    for i in range(2, len(bar_info) - 2):
        before = (bar_info[i - 2]["full"] + bar_info[i - 1]["full"]) / 2
        after = (bar_info[i]["full"] + bar_info[i + 1]["full"]) / 2
        kb = (bar_info[i - 2]["kick"] + bar_info[i - 1]["kick"]) / 2
        ka = (bar_info[i]["kick"] + bar_info[i + 1]["kick"]) / 2
        jumps.append((after - before + (ka - kb) * 0.7, i))
    jumps.sort(reverse=True)
    drops = [{"bar": i, "time": bar_info[i]["time"], "strength": round(s, 3)} for s, i in jumps[:6]]
    print("\nbiggest energy rises (drop candidates):")
    for d in drops:
        print(f"  bar {d['bar']:3d} at {d['time']:7.2f}s  (+{d['strength']:.3f})")

    # --- kick hits (for flashes / punches) -------------------------------------
    hits = []
    thresh_win = int(ENV_FPS * 1.5)
    for i in range(2, n - 2):
        v = on_kick[i]
        if v < 0.35 or v < on_kick[i - 1] or v < on_kick[i + 1]:
            continue
        local = on_kick[max(0, i - thresh_win):i + thresh_win]
        if v >= 1.6 * (sum(local) / len(local)) and (not hits or i / ENV_FPS - hits[-1] > 0.12):
            hits.append(round(i / ENV_FPS, 3))

    # --- 30 fps envelopes for audio-reactive motion ----------------------------
    def to_video(sig):
        m = max(sig) or 1
        frames = int(duration * VIDEO_FPS)
        return [round(sample_at(sig, f / VIDEO_FPS * ENV_FPS) / m, 3) for f in range(frames)]

    # Transient "hit" envelope: kick onsets with a fast decay. Unlike the raw kick
    # level it punches on every hit even when an 808 sustains underneath.
    frames = int(duration * VIDEO_FPS)
    raw_hits = []
    for f in range(frames):
        a, b = int(f / VIDEO_FPS * ENV_FPS), int((f + 1) / VIDEO_FPS * ENV_FPS) + 1
        raw_hits.append(max(on_kick[a:b]) if a < len(on_kick) else 0.0)
    ref = sorted(raw_hits)[int(len(raw_hits) * 0.98)] or 1
    hit_env, level = [], 0.0
    for v in raw_hits:
        level = max(min(v / ref, 1.0), level * 0.72)
        hit_env.append(round(level, 3))

    json.dump({
        "duration": round(duration, 3),
        "bpm": round(bpm, 3),
        "beats": [round(b, 3) for b in beats],
        "bars": [round(b, 3) for b in bars],
        "barInfo": bar_info,
        "drops": drops,
        "kickHits": hits,
        "fps": VIDEO_FPS,
        "kickEnvelope": to_video(kick),
        "energyEnvelope": to_video(full),
        "hitEnvelope": hit_env,
    }, open(out_path, "w"))
    print(f"\nwrote {out_path}: {len(beats)} beats, {len(bars)} bars, {len(hits)} kick hits")


if __name__ == "__main__":
    main()
