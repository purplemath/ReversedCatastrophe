# -*- coding: utf-8 -*-
## 程序生成占位音效（纯标准库，无依赖）→ assets/sfx/*.wav
## 用法：python tools/gen_sfx.py
import math
import os
import random
import struct
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sfx")


def write_wav(name: str, samples: list) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, s))
            frames += struct.pack("<h", int(v * 32000))
        w.writeframes(bytes(frames))
    print("wrote", path, len(samples) / SR, "s")


def env_decay(i: int, n: int, k: float = 5.0) -> float:
    return math.exp(-k * i / n)


def tone(freq_start: float, freq_end: float, dur: float, vol: float = 0.5, k: float = 4.0) -> list:
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        f = freq_start + (freq_end - freq_start) * (i / n)
        phase += 2 * math.pi * f / SR
        out.append(math.sin(phase) * vol * env_decay(i, n, k))
    return out


def noise(dur: float, vol: float = 0.5, k: float = 5.0, lp: int = 1) -> list:
    n = int(SR * dur)
    out = []
    prev = 0.0
    rnd = random.Random(42)
    for i in range(n):
        v = rnd.uniform(-1, 1)
        for _ in range(lp):  # 简易低通
            v = (v + prev) * 0.5
        prev = v
        out.append(v * vol * env_decay(i, n, k))
    return out


def mix(*layers) -> list:
    n = max(len(x) for x in layers)
    out = [0.0] * n
    for layer in layers:
        for i, v in enumerate(layer):
            out[i] += v
    peak = max(1e-6, max(abs(v) for v in out))
    if peak > 0.95:
        out = [v * 0.95 / peak for v in out]
    return out


def seq(*parts) -> list:
    out = []
    for p in parts:
        out += p
    return out


# 入水：噪声拍击 + 低频下坠
write_wav("splash", mix(noise(0.30, 0.8, 9.0, 2), tone(180, 90, 0.25, 0.3, 6.0)))
# 存档：明亮双音
write_wav("checkpoint", seq(tone(880, 880, 0.08, 0.4, 3.0), tone(1320, 1320, 0.12, 0.4, 4.0)))
# 获救：上行琶音
write_wav("rescue", seq(tone(523, 523, 0.12, 0.4, 3.0), tone(659, 659, 0.12, 0.4, 3.0),
                        tone(784, 784, 0.20, 0.45, 3.5)))
# 回溯：倒吸感噪声 + 下滑音
write_wav("rewind", mix(noise(0.55, 0.5, 2.0, 3), tone(420, 140, 0.55, 0.35, 2.0)))
# 知识卡：柔和双音
write_wav("card", seq(tone(990, 990, 0.10, 0.3, 3.0), tone(1480, 1480, 0.25, 0.3, 4.5)))
# 溺水：低沉下坠
write_wav("drown", mix(tone(220, 90, 0.6, 0.5, 3.0), noise(0.6, 0.25, 3.0, 4)))
