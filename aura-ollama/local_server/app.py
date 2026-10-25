"""Private LAN WebRTC gateway. All voice inference happens on this computer."""
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from pathlib import Path
import asyncio
import hmac
import json
import logging
import time

from aiortc import RTCPeerConnection, RTCSessionDescription
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, PlainTextResponse

from .inference import KokoroVoice, OllamaBrain, WhisperRecognizer
from .personality import Preferences
from .session import LocalConversation
from .settings import Settings, ROOT

logger = logging.getLogger("aura.gateway")


class Runtime:
    def __init__(self, settings):
        self.settings = settings
        self.recognizer = WhisperRecognizer(settings)
        self.voice_engine = KokoroVoice(settings)
        self.brain = OllamaBrain(settings)
        self.peers = set()
        self.sessions = {}
        self.rate_limits = defaultdict(deque)

    async def close(self):
        for session in list(self.sessions.values()):
            await session.close()
        await asyncio.gather(*(pc.close() for pc in list(self.peers)), return_exceptions=True)
        self.sessions.clear()
        self.peers.clear()


def create_app(settings):
    runtime = Runtime(settings)
    @asynccontextmanager
    async def lifespan(_app):
        try:
            yield
        finally:
            await runtime.close()

    app = FastAPI(title="AURA Local Voice", docs_url=None, redoc_url=None,
                  openapi_url=None, lifespan=lifespan)
    app.state.runtime = runtime

    @app.get("/")
    async def web_client():
        return FileResponse(ROOT / "web" / "index.html")

    @app.get("/client.js")
    async def web_script():
        return FileResponse(ROOT / "web" / "client.js", media_type="application/javascript")

    @app.get("/health")
    async def health():
        return {
            "ok": True, "service": "AURA Local Voice", "provider": "ollama",
            "model": settings.ollama_model,
            "voice_models_present": Path(settings.kokoro_model_path).is_file() and Path(settings.kokoro_voices_path).is_file(),
        }

    @app.post("/api/session")
    async def offer(request: Request):
        provided = request.headers.get("authorization", "")
        expected = "Bearer " + settings.pairing_code
        if not hmac.compare_digest(provided, expected):
            raise HTTPException(401, "Pairing code is incorrect")
        ip = request.client.host if request.client else "unknown"
        history = runtime.rate_limits[ip]
        now = time.monotonic()
        while history and now - history[0] > 60:
            history.popleft()
        if len(history) >= 6:
            raise HTTPException(429, "Too many sessions. Wait one minute.")
        history.append(now)

        raw = await request.body()
        if len(raw) > 96_000:
            raise HTTPException(413, "SDP request too large")
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, UnicodeDecodeError):
            raise HTTPException(400, "Invalid JSON")
        sdp = data.get("sdp") if isinstance(data, dict) else None
        if not isinstance(sdp, str) or not sdp.startswith("v=") or "m=audio" not in sdp:
            raise HTTPException(400, "Valid audio SDP offer required")
        prefs = Preferences.parse(data.get("preferences"))
        pc = RTCPeerConnection()
        session = LocalConversation(prefs, runtime.recognizer, runtime.voice_engine, runtime.brain)
        runtime.peers.add(pc)
        runtime.sessions[pc] = session

        @pc.on("datachannel")
        def on_datachannel(channel):
            session.set_channel(channel)
            @channel.on("open")
            def on_open():
                session.notify("aura.status", message="Ready to listen")

        @pc.on("track")
        def on_track(track):
            if track.kind == "audio":
                session.start_listening(track)

        @pc.on("connectionstatechange")
        async def on_connection_state():
            if pc.connectionState in ("failed", "closed"):
                await session.close()
                runtime.peers.discard(pc)
                runtime.sessions.pop(pc, None)

        try:
            await pc.setRemoteDescription(RTCSessionDescription(sdp=sdp, type="offer"))
            pc.addTrack(session.outgoing)
            answer = await pc.createAnswer()
            await pc.setLocalDescription(answer)
            if not pc.localDescription:
                raise RuntimeError("Could not generate an SDP answer")
            return PlainTextResponse(pc.localDescription.sdp, media_type="application/sdp")
        except Exception as error:
            logger.exception("SDP setup failed")
            await session.close()
            await pc.close()
            runtime.peers.discard(pc)
            runtime.sessions.pop(pc, None)
            raise HTTPException(500, "Local audio session failed to start") from error

    return app


def app_factory():
    """Uvicorn factory: configuration is validated only when the server starts."""
    return create_app(Settings.from_env())

