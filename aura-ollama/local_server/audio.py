"""Local 16 kHz listening and 48 kHz WebRTC playback (20 ms frames)."""
from collections import deque
from dataclasses import dataclass
from fractions import Fraction
import asyncio
import math
import time

import av
from aiortc import MediaStreamTrack
import numpy as np
from scipy.signal import resample_poly
import webrtcvad


INPUT_RATE = 16_000
OUTPUT_RATE = 48_000
INPUT_FRAME = 320        # 20 ms at 16 kHz
OUTPUT_FRAME = 960       # 20 ms at 48 kHz


@dataclass
class SpeechTurn:
    pcm: np.ndarray
    rms: float
    duration: float


class SpeechGate:
    """Small frame-based VAD with leading audio and a pause allowance.

    It cannot guarantee whispered speech; soft mode trades accuracy in noise
    for a lower activation level and longer pauses.
    """

    def __init__(self, mode="natural"):
        mode = mode if mode in {"natural", "quick", "soft"} else "natural"
        self.vad = webrtcvad.Vad(1 if mode == "soft" else 2)
        self.energy_threshold = {"natural": 0.022, "quick": 0.023, "soft": 0.008}[mode]
        self.silence_limit = {"natural": 36, "quick": 23, "soft": 48}[mode]
        self.preroll = deque(maxlen=15)
        self.carry = np.empty(0, dtype=np.int16)
        self.recording = False
        self.speech_streak = 0
        self.silence_streak = 0
        self.collected = []
        self.loudness = []

    def push(self, samples):
        pcm = np.asarray(samples, dtype=np.int16).reshape(-1)
        self.carry = np.concatenate((self.carry, pcm))
        events = []
        while len(self.carry) >= INPUT_FRAME:
            frame, self.carry = self.carry[:INPUT_FRAME], self.carry[INPUT_FRAME:]
            events.extend(self._frame(frame.copy()))
        return events

    def _frame(self, frame):
        rms = float(np.sqrt(np.mean(frame.astype(np.float32) ** 2)) / 32768)
        try:
            speech = self.vad.is_speech(frame.tobytes(), INPUT_RATE) or rms >= self.energy_threshold
        except Exception:
            speech = rms >= self.energy_threshold

        if not self.recording:
            self.preroll.append(frame)
            self.speech_streak = self.speech_streak + 1 if speech else 0
            if self.speech_streak < 2:
                return []
            self.recording = True
            self.collected = list(self.preroll)
            self.loudness = [rms]
            self.silence_streak = 0
            return [("start", None)]

        self.collected.append(frame)
        self.loudness.append(rms)
        self.silence_streak = 0 if speech else self.silence_streak + 1
        # Keep a single utterance from growing indefinitely.
        if self.silence_streak < self.silence_limit and len(self.collected) < 1_000:
            return []

        collected = np.concatenate(self.collected)
        average_rms = float(sum(self.loudness) / max(1, len(self.loudness)))
        result = SpeechTurn(collected, average_rms, len(collected) / INPUT_RATE)
        self.recording = False
        self.speech_streak = 0
        self.silence_streak = 0
        self.collected = []
        self.loudness = []
        self.preroll.clear()
        return [("end", result)] if result.duration >= 0.23 else []


class IncomingAudio:
    def __init__(self, mode="natural"):
        self.resampler = av.AudioResampler(format="s16", layout="mono", rate=INPUT_RATE)
        self.gate = SpeechGate(mode)

    def add_frame(self, frame):
        events = []
        for converted in self.resampler.resample(frame):
            data = converted.to_ndarray().reshape(-1).astype(np.int16)
            events.extend(self.gate.push(data))
        return events


class OutgoingAudio(MediaStreamTrack):
    """Always emits audio frames. Silent between generated speech segments."""

    kind = "audio"

    def __init__(self):
        super().__init__()
        self.queue = asyncio.Queue(maxsize=220)
        self.version = 0
        self.pts = 0
        self.started = None

    def interrupt(self):
        self.version += 1
        self.queue = asyncio.Queue(maxsize=220)

    async def play(self, samples: np.ndarray, rate: int, version: int):
        if rate <= 0:
            return
        samples = np.asarray(samples, dtype=np.float32).reshape(-1)
        if rate != OUTPUT_RATE:
            gcd = math.gcd(rate, OUTPUT_RATE)
            samples = resample_poly(samples, OUTPUT_RATE // gcd, rate // gcd)
        pcm = np.clip(samples, -1.0, 1.0)
        pcm = (pcm * 32767).astype(np.int16)
        remainder = len(pcm) % OUTPUT_FRAME
        if remainder:
            pcm = np.pad(pcm, (0, OUTPUT_FRAME - remainder))
        for i in range(0, len(pcm), OUTPUT_FRAME):
            if version != self.version:
                return
            await self.queue.put(pcm[i:i + OUTPUT_FRAME].copy())

    async def recv(self):
        if self.readyState != "live":
            raise asyncio.CancelledError("Audio track stopped")
        if self.started is None:
            self.started = time.monotonic()
        else:
            target = self.started + self.pts / OUTPUT_RATE
            delay = target - time.monotonic()
            if delay > 0:
                await asyncio.sleep(delay)
        try:
            pcm = self.queue.get_nowait()
        except asyncio.QueueEmpty:
            pcm = np.zeros(OUTPUT_FRAME, dtype=np.int16)
        output = av.AudioFrame.from_ndarray(pcm.reshape(1, -1), format="s16", layout="mono")
        output.sample_rate = OUTPUT_RATE
        output.pts = self.pts
        output.time_base = Fraction(1, OUTPUT_RATE)
        self.pts += OUTPUT_FRAME
        return output

