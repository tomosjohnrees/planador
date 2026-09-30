"""Generate the two short, self-contained timer signals bundled with Planador."""

import math
import struct
import sys
import wave
from pathlib import Path


SAMPLE_RATE = 44_100


def write_chime(path: Path, notes: list[tuple[float, float]]) -> None:
    duration = max(start for start, _ in notes) + 0.95
    samples = bytearray()
    for index in range(int(duration * SAMPLE_RATE)):
        time = index / SAMPLE_RATE
        value = 0.0
        for start, frequency in notes:
            age = time - start
            if 0 <= age < 0.95:
                attack = min(1.0, age / 0.015)
                envelope = attack * math.exp(-2.9 * age)
                fundamental = math.sin(2 * math.pi * frequency * age)
                overtone = 0.22 * math.sin(4 * math.pi * frequency * age)
                value += 0.52 * envelope * (fundamental + overtone)
        sample = max(-1.0, min(1.0, value))
        samples.extend(struct.pack("<h", round(sample * 32_767)))

    with wave.open(str(path), "wb") as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(SAMPLE_RATE)
        sound.writeframes(samples)


output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
write_chime(output / "FocusComplete.wav", [(0.0, 659.25), (0.46, 880.0), (0.92, 1174.66)])
write_chime(output / "BreakComplete.wav", [(0.0, 987.77), (0.50, 783.99), (1.00, 659.25)])
