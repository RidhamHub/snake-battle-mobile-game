"""Generate the game's sound effects and music loop as 16-bit mono WAV files.

Run from the repo root:  python tools/generate_audio.py
Output goes straight into assets/audio/.

Everything is synthesised from scratch so the assets stay tiny, license-free
and tonally consistent with each other.
"""
import math
import os
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
os.makedirs(OUT, exist_ok=True)


def write_wav(name, samples):
    """Write float samples in [-1, 1] to a 16-bit mono WAV."""
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))
    print(f"{name}: {len(samples)/SR:.2f}s  {os.path.getsize(path)/1024:.1f} KB")


def env_ad(n, attack=0.005, decay=None, curve=2.2):
    """Attack/decay envelope of length n samples."""
    a = max(1, int(attack * SR))
    out = []
    for i in range(n):
        if i < a:
            out.append(i / a)
        else:
            t = (i - a) / max(1, (n - a))
            out.append((1.0 - t) ** curve)
    return out


def square(phase, duty=0.5):
    return 1.0 if (phase % 1.0) < duty else -1.0


def tri(phase):
    p = phase % 1.0
    return 4.0 * abs(p - 0.5) - 1.0


def tone(freq_fn, dur, wave_fn=square, amp=0.5, env=None, duty=0.5, detune=0.0):
    """Render a tone whose frequency is a function of normalised time."""
    n = int(dur * SR)
    e = env if env is not None else env_ad(n)
    out = []
    ph = 0.0
    ph2 = 0.0
    for i in range(n):
        t = i / n
        f = freq_fn(t)
        ph += f / SR
        ph2 += (f * (1 + detune)) / SR
        if wave_fn is square:
            v = square(ph, duty)
            if detune:
                v = 0.6 * v + 0.4 * square(ph2, duty)
        else:
            v = wave_fn(ph)
            if detune:
                v = 0.6 * v + 0.4 * wave_fn(ph2)
        out.append(v * amp * e[i])
    return out


def noise(dur, amp=0.5, env=None, lowpass=0.35):
    """Cheap filtered noise, used for the impact sounds."""
    import random

    rnd = random.Random(1234)
    n = int(dur * SR)
    e = env if env is not None else env_ad(n, 0.001, curve=2.5)
    out = []
    prev = 0.0
    for i in range(n):
        white = rnd.uniform(-1, 1)
        prev = prev + lowpass * (white - prev)
        out.append(prev * amp * e[i])
    return out


def mix(*layers):
    n = max(len(l) for l in layers)
    out = [0.0] * n
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    return out


def pad(samples, dur):
    n = int(dur * SR)
    return samples + [0.0] * max(0, n - len(samples))


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


# ── eat: short upward blip ───────────────────────────────────────────────
write_wav("eat.wav", tone(lambda t: 620 + 380 * t, 0.075, amp=0.42, duty=0.5))

# ── combo: brighter two-step blip for a running combo ────────────────────
write_wav(
    "combo.wav",
    seq(
        tone(lambda t: 780, 0.045, amp=0.36, duty=0.25),
        tone(lambda t: 1180, 0.07, amp=0.36, duty=0.25),
    ),
)

# ── golden: rising arpeggio sparkle ──────────────────────────────────────
write_wav(
    "golden.wav",
    seq(
        tone(lambda t: 784, 0.055, amp=0.32, duty=0.4),
        tone(lambda t: 988, 0.055, amp=0.32, duty=0.4),
        tone(lambda t: 1318, 0.055, amp=0.32, duty=0.4),
        tone(lambda t: 1568, 0.13, amp=0.34, duty=0.4, detune=0.006),
    ),
)

# ── power: warm swell with a shimmer on top ──────────────────────────────
n_pow = int(0.34 * SR)
write_wav(
    "power.wav",
    mix(
        tone(lambda t: 320 + 500 * t, 0.34, wave_fn=tri, amp=0.38, env=env_ad(n_pow, 0.02, curve=1.6)),
        tone(lambda t: 960 + 700 * t, 0.34, amp=0.16, duty=0.2, env=env_ad(n_pow, 0.05, curve=2.0)),
    ),
)

# ── kill: punchy descending hit ──────────────────────────────────────────
n_kill = int(0.3 * SR)
write_wav(
    "kill.wav",
    mix(
        tone(lambda t: 420 * (1 - 0.62 * t), 0.3, wave_fn=tri, amp=0.5, env=env_ad(n_kill, 0.002, curve=2.4)),
        noise(0.16, amp=0.34, lowpass=0.5),
    ),
)

# ── death: long falling tone with a thud ─────────────────────────────────
n_death = int(0.75 * SR)
write_wav(
    "death.wav",
    mix(
        tone(lambda t: 300 * (1 - 0.72 * t), 0.75, wave_fn=tri, amp=0.45, env=env_ad(n_death, 0.004, curve=1.8)),
        tone(lambda t: 150 * (1 - 0.6 * t), 0.75, amp=0.22, duty=0.5, env=env_ad(n_death, 0.01, curve=2.2)),
        noise(0.3, amp=0.22, lowpass=0.22),
    ),
)

# ── click: tiny UI tick ──────────────────────────────────────────────────
write_wav("click.wav", tone(lambda t: 1400, 0.028, amp=0.3, duty=0.15))


# ── bgm: 8-bar chiptune loop ─────────────────────────────────────────────
def note(midi):
    return 440.0 * (2 ** ((midi - 69) / 12.0))


BPM = 124
BEAT = 60.0 / BPM
STEP = BEAT / 2  # eighth notes

# A minor groove: Am - F - C - G
CHORDS = [
    [57, 60, 64],  # Am
    [53, 57, 60],  # F
    [48, 52, 55],  # C
    [55, 59, 62],  # G
]

LEAD = [
    [69, 72, 76, 72, 69, 72, 76, 79],
    [65, 69, 72, 69, 65, 69, 72, 77],
    [64, 67, 72, 67, 64, 67, 72, 76],
    [67, 71, 74, 71, 67, 71, 74, 79],
]

total_steps = len(CHORDS) * 8 * 2  # two passes through the progression
loop_len = int(total_steps * STEP * SR)
buf = [0.0] * (loop_len + SR // 2)


def add_at(samples, start):
    for i, v in enumerate(samples):
        idx = start + i
        if idx < len(buf):
            buf[idx] += v


for pass_i in range(2):
    for bar, chord in enumerate(CHORDS):
        bar_start = ((pass_i * len(CHORDS)) + bar) * 8

        # Bass: root on every beat, octave down.
        for beat in range(4):
            start = int((bar_start + beat * 2) * STEP * SR)
            f = note(chord[0] - 12)
            d = STEP * 1.7
            nb = int(d * SR)
            add_at(
                tone(lambda t, f=f: f, d, wave_fn=tri, amp=0.30, env=env_ad(nb, 0.006, curve=1.5)),
                start,
            )

        # Arp: chord tones on the offbeats, quiet.
        for step in range(8):
            start = int((bar_start + step) * STEP * SR)
            f = note(chord[step % len(chord)] + 12)
            d = STEP * 0.85
            na = int(d * SR)
            add_at(
                tone(lambda t, f=f: f, d, amp=0.085, duty=0.25, env=env_ad(na, 0.004, curve=2.2)),
                start,
            )

        # Lead: only on the second pass so the loop has a lift.
        if pass_i == 1:
            for step, m in enumerate(LEAD[bar]):
                start = int((bar_start + step) * STEP * SR)
                d = STEP * 0.9
                nl = int(d * SR)
                add_at(
                    tone(lambda t, f=note(m): f, d, amp=0.13, duty=0.4, env=env_ad(nl, 0.005, curve=1.9)),
                    start,
                )

        # Hats on every eighth, kick on 1 and 3.
        for step in range(8):
            start = int((bar_start + step) * STEP * SR)
            add_at(noise(0.035, amp=0.05, lowpass=0.85), start)
        for beat in (0, 4):
            start = int((bar_start + beat) * STEP * SR)
            nk = int(0.12 * SR)
            add_at(
                tone(lambda t: 110 * (1 - 0.55 * t), 0.12, wave_fn=tri, amp=0.34,
                     env=env_ad(nk, 0.002, curve=2.6)),
                start,
            )

# Fold the decay tail back over the loop start so it repeats seamlessly.
tail = buf[loop_len:]
loop = buf[:loop_len]
for i, v in enumerate(tail):
    if i < len(loop):
        loop[i] += v

peak = max(abs(v) for v in loop) or 1.0
loop = [v / peak * 0.82 for v in loop]

write_wav("bgm_loop.wav", loop)
print("done")
