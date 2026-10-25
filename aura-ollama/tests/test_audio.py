import asyncio
import unittest

import numpy as np
from local_server.audio import SpeechGate, OutgoingAudio, INPUT_FRAME
from local_server.audio import SpeechTurn
from local_server.personality import Preferences
from local_server.session import LocalConversation


class AudioGateTests(unittest.TestCase):
    def test_detects_loud_audio_then_pauses(self):
        gate = SpeechGate("quick")
        voice = np.full(INPUT_FRAME, 11_000, dtype=np.int16)
        silence = np.zeros(INPUT_FRAME, dtype=np.int16)
        events = []
        for _ in range(20):
            events.extend(gate.push(voice))
        for _ in range(40):
            events.extend(gate.push(silence))
        kinds = [kind for kind, _ in events]
        self.assertIn("start", kinds)
        self.assertIn("end", kinds)
        self.assertGreater([payload for kind, payload in events if kind == "end"][0].duration, 0.3)

    def test_soft_mode_has_lower_energy_threshold(self):
        self.assertLess(SpeechGate("soft").energy_threshold, SpeechGate("natural").energy_threshold)


class FakeRecognizer:
    async def transcribe(self, _):
        return "Hello how are you"


class FakeBrain:
    async def stream(self, messages):
        assert messages[-1]["content"] == "Hello how are you"
        for text in ("I am doing well, ", "thanks for asking."):
            yield text


class FakeVoice:
    async def speak(self, phrase, voice, speed):
        assert voice == "af_sarah"
        return np.zeros(2400, dtype=np.float32), 24000


class FakeChannel:
    readyState = "open"
    def __init__(self):
        self.events = []
    def send(self, data):
        import json
        self.events.append(json.loads(data))


class PipelineTests(unittest.IsolatedAsyncioTestCase):
    async def test_turn_streams_text_and_speech_locally(self):
        session = LocalConversation(Preferences(), FakeRecognizer(), FakeVoice(), FakeBrain())
        channel = FakeChannel()
        session.set_channel(channel)
        await session._reply(SpeechTurn(np.zeros(3200, dtype=np.int16), 0.01, 0.2), session.epoch)
        events = [event["type"] for event in channel.events]
        self.assertIn("response.created", events)
        self.assertIn("response.output_audio_transcript.delta", events)
        self.assertIn("response.done", events)
        self.assertEqual(len(session.history), 2)
        self.assertGreater(session.outgoing.queue.qsize(), 0)
        await session.close()

    async def test_interruption_clears_queued_audio(self):
        outgoing = OutgoingAudio()
        await outgoing.play(np.zeros(4800, dtype=np.float32), 48000, outgoing.version)
        self.assertGreater(outgoing.queue.qsize(), 0)
        outgoing.interrupt()
        self.assertEqual(outgoing.queue.qsize(), 0)
        outgoing.stop()

    async def test_outgoing_produces_valid_audio_frame(self):
        outgoing = OutgoingAudio()
        await outgoing.play(np.ones(960, dtype=np.float32) * 0.2, 48000, outgoing.version)
        frame = await outgoing.recv()
        self.assertEqual(frame.sample_rate, 48000)
        self.assertEqual(frame.samples, 960)
        self.assertEqual(frame.pts, 0)
        outgoing.stop()

