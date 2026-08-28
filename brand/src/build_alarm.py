"""Builds the new-order alarm.

The spec calls this the single most important feature in MerchantApp, and the sound is
the whole feature: a merchant who does not hear an order does not cook it, and the
customer waits for food nobody started. Everything below follows from where it has to be
heard — a kitchen, over an extractor fan, from a phone on a shelf across the room.

Why generate rather than pick one:

- **Two alternating tones, not one.** A steady tone reads as machinery and the ear stops
  hearing it within seconds. An interval that keeps moving does not habituate.
- **Around 1 kHz.** Small phone speakers have almost no output below ~400 Hz, so a
  "serious" low tone is inaudible on the device that has to play it. 1 kHz sits where a
  phone speaker is loudest and where human hearing is most sensitive.
- **Square-ish, not a pure sine.** The harmonics survive a cheap speaker and a noisy
  room; a sine disappears into extractor noise.
- **Short bursts with gaps.** A continuous sound is one thing to ignore; a repeating one
  keeps re-triggering attention. The gaps are also what lets a person locate the phone.
- **A hard fade at each edge.** Cutting a waveform mid-cycle clicks, and a click on every
  repetition is what makes an alarm sound cheap.

It loops seamlessly, so Android's notification channel can repeat it for as long as the
order goes unopened.

    python brand/src/build_alarm.py
"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "audio"

RATE = 44_100
# Normalised to this after mixing, rather than applied per-tone. Three harmonics never
# peak together, so scaling each one leaves the file several dB quieter than it could be
# — and several dB is the difference between hearing this over an extractor fan and not.
# Short of 1.0 because clipping on a small speaker is distortion, not volume.
PEAK = 0.95

# The pair. A minor third apart — close enough to read as one alarm, far enough that the
# change is unmistakable.
LOW_HZ = 988.0
HIGH_HZ = 1174.0

BEEP_MS = 150
GAP_MS = 110
REST_MS = 620  # Between groups. Long enough to hear somebody answer, short enough to nag.
EDGE_MS = 6  # Fade in and out of every beep, so nothing clicks.


def tone(frequency: float, milliseconds: int) -> list[float]:
    """One beep: a fundamental plus its odd harmonics, faded at both edges."""
    samples = int(RATE * milliseconds / 1000)
    edge = max(1, int(RATE * EDGE_MS / 1000))
    out: list[float] = []

    for i in range(samples):
        t = i / RATE
        # Odd harmonics only, falling off — the shape of a soft square wave. It carries
        # through noise the way a sine does not, without the harshness of a real square.
        value = (
            math.sin(2 * math.pi * frequency * t)
            + 0.33 * math.sin(2 * math.pi * frequency * 3 * t)
            + 0.16 * math.sin(2 * math.pi * frequency * 5 * t)
        ) / 1.49

        if i < edge:
            value *= i / edge
        elif i > samples - edge:
            value *= (samples - i) / edge

        out.append(value)

    return out


def silence(milliseconds: int) -> list[float]:
    return [0.0] * int(RATE * milliseconds / 1000)


def build() -> list[float]:
    """Two rising pairs, then a rest. The whole thing tiles against itself."""
    pattern: list[float] = []
    for _ in range(2):
        pattern += tone(LOW_HZ, BEEP_MS)
        pattern += silence(GAP_MS)
        pattern += tone(HIGH_HZ, BEEP_MS)
        pattern += silence(GAP_MS)
    pattern += silence(REST_MS)

    loudest = max(abs(s) for s in pattern)
    return [s * PEAK / loudest for s in pattern]


def write_wav(samples: list[float], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(
            b"".join(
                struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
            )
        )


def main() -> None:
    samples = build()
    target = OUT / "new_order.wav"
    write_wav(samples, target)

    seconds = len(samples) / RATE
    print(f"  {target.relative_to(HERE.parent.parent)}  {seconds:.2f}s  loops seamlessly")
    print("  Copy to each app's android/app/src/main/res/raw/new_order.wav")


if __name__ == "__main__":
    main()
