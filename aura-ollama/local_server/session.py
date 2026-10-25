"""A conversational audio session. Nothing here can operate outside tools."""
import asyncio
import json
import logging
from aiortc.mediastreams import MediaStreamError

from .audio import IncomingAudio, OutgoingAudio
from .personality import delivery_note, system_prompt, voice_speed
from .phrases import PhraseBuffer

logger = logging.getLogger("aura.session")


class LocalConversation:
    def __init__(self, preferences, recognizer, voice_engine, brain):
        self.preferences = preferences
        self.recognizer = recognizer
        self.voice_engine = voice_engine
        self.brain = brain
        self.incoming = IncomingAudio(preferences.listening)
        self.outgoing = OutgoingAudio()
        self.channel = None
        self.history = []
        self.epoch = 0
        self.work = None
        self.consume_task = None
        self.closed = False

    def set_channel(self, channel):
        self.channel = channel

    def notify(self, event_type, **kwargs):
        if self.channel and self.channel.readyState == "open":
            try:
                self.channel.send(json.dumps({"type": event_type, **kwargs}))
            except Exception:
                pass

    def start_listening(self, track):
        if self.consume_task is None:
            self.consume_task = asyncio.create_task(self._consume(track))

    async def _consume(self, track):
        try:
            while not self.closed:
                frame = await track.recv()
                for kind, speech in self.incoming.add_frame(frame):
                    if kind == "start":
                        self._interrupt()
                        self.notify("input_audio_buffer.speech_started")
                    elif kind == "end" and speech is not None:
                        self.notify("input_audio_buffer.speech_stopped")
                        self.work = asyncio.create_task(self._reply(speech, self.epoch))
        except asyncio.CancelledError:
            pass
        except MediaStreamError:
            # Normal when a WebRTC microphone track ends or the user hangs up.
            pass
        except Exception as error:
            if not self.closed:
                logger.exception("Incoming audio failed")
                self.notify("error", error={"message": "The microphone stream stopped."})

    def _interrupt(self):
        self.epoch += 1
        self.outgoing.interrupt()
        if self.work and not self.work.done():
            self.work.cancel()
        self.work = None

    async def _reply(self, turn, epoch):
        try:
            self.notify("aura.status", message="Understanding speech")
            transcript = await self.recognizer.transcribe(turn.pcm)
            if epoch != self.epoch or self.closed:
                return
            if not transcript:
                self.notify("response.done")
                return

            # The user text is a visible diagnostic. It is held in RAM only.
            self.notify("conversation.item.input_audio_transcription.completed", transcript=transcript)
            note = delivery_note(turn.rms, len(transcript.split()), turn.duration)
            messages = [{"role": "system", "content": system_prompt(self.preferences, note)}]
            messages.extend(self.history[-12:])
            messages.append({"role": "user", "content": transcript})

            self.notify("response.created")
            buffer = PhraseBuffer(min_chars=28, max_chars=110)
            whole_response = ""
            quiet = turn.rms < 0.012
            current_speed = voice_speed(self.preferences, transcript, quiet)

            async for token in self.brain.stream(messages):
                if epoch != self.epoch or self.closed:
                    return
                whole_response += token
                self.notify("response.output_audio_transcript.delta", delta=token)
                for phrase in buffer.add(token):
                    await self._speak_phrase(phrase, current_speed, epoch)

            for phrase in buffer.finish():
                await self._speak_phrase(phrase, current_speed, epoch)
            if epoch == self.epoch and not self.closed:
                self.history.extend([
                    {"role": "user", "content": transcript},
                    {"role": "assistant", "content": whole_response.strip()},
                ])
                self.history = self.history[-12:]
                self.notify("response.done")
        except asyncio.CancelledError:
            pass
        except Exception:
            logger.exception("Local pipeline error")
            self.notify("error", error={"message": "A local model failed. Check the PC terminal and model downloads."})
            self.notify("response.done")

    async def _speak_phrase(self, phrase, speed, epoch):
        if epoch != self.epoch or self.closed:
            return
        self.notify("aura.status", message="Synthesizing voice")
        samples, rate = await self.voice_engine.speak(phrase, self.preferences.voice, speed)
        if epoch == self.epoch and not self.closed:
            await self.outgoing.play(samples, rate, self.outgoing.version)

    async def close(self):
        self.closed = True
        self._interrupt()
        if self.consume_task:
            self.consume_task.cancel()
        self.outgoing.stop()
        self.history.clear()

