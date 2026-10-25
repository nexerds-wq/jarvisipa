"""Replaceable local brain, speech recognizer, and voice modules."""
import asyncio
import json
import threading

import httpx
import numpy as np


class WhisperRecognizer:
    def __init__(self, settings):
        self.settings = settings
        self.model = None
        self.lock = threading.Lock()

    def transcribe_sync(self, samples):
        from faster_whisper import WhisperModel
        with self.lock:
            if self.model is None:
                self.model = WhisperModel(
                    self.settings.whisper_model,
                    device=self.settings.whisper_device,
                    compute_type=self.settings.whisper_compute_type,
                )
            audio = np.asarray(samples, dtype=np.float32) / 32768.0
            segments, _ = self.model.transcribe(
                audio, beam_size=1, vad_filter=False,
                condition_on_previous_text=False,
            )
            return " ".join(part.text.strip() for part in segments).strip()

    async def transcribe(self, samples):
        return await asyncio.to_thread(self.transcribe_sync, samples)


class KokoroVoice:
    def __init__(self, settings):
        self.settings = settings
        self.engine = None
        self.lock = threading.Lock()

    def speak_sync(self, phrase, voice, speed):
        from kokoro_onnx import Kokoro
        with self.lock:
            if self.engine is None:
                self.engine = Kokoro(self.settings.kokoro_model_path, self.settings.kokoro_voices_path)
            samples, rate = self.engine.create(phrase, voice=voice, speed=speed, lang="en-us")
            return np.asarray(samples, dtype=np.float32), int(rate)

    async def speak(self, phrase, voice, speed):
        return await asyncio.to_thread(self.speak_sync, phrase, voice, speed)


class OllamaBrain:
    def __init__(self, settings):
        self.settings = settings

    async def stream(self, messages):
        timeout = httpx.Timeout(connect=10, read=None, write=30, pool=10)
        async with httpx.AsyncClient(base_url=self.settings.ollama_url, timeout=timeout) as client:
            async with client.stream("POST", "/api/chat", json={
                "model": self.settings.ollama_model,
                "messages": messages,
                "stream": True,
                "think": False,
                "keep_alive": "15m",
                "options": {"temperature": 0.8, "num_predict": 220}
            }) as response:
                response.raise_for_status()
                async for line in response.aiter_lines():
                    if not line:
                        continue
                    packet = json.loads(line)
                    token = packet.get("message", {}).get("content", "")
                    if token:
                        yield token
                    if packet.get("done"):
                        break

