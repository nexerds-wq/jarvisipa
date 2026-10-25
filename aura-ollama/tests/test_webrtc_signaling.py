"""A real in-process WebRTC offer/answer check; no model downloads required."""
import asyncio
import unittest

import httpx
from aiortc import AudioStreamTrack, RTCPeerConnection, RTCSessionDescription

from local_server.app import create_app
from local_server.settings import Settings


class WebRTCHandshakeTests(unittest.IsolatedAsyncioTestCase):
    async def test_offer_answer_connects_audio_and_datachannel(self):
        app = create_app(Settings(pairing_code="local-test-secret-code"))
        client_pc = RTCPeerConnection()
        channel = client_pc.createDataChannel("aura-events")
        client_pc.addTrack(AudioStreamTrack())
        try:
            offer = await client_pc.createOffer()
            await client_pc.setLocalDescription(offer)
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://testserver") as client:
                response = await client.post("/api/session", json={
                    "sdp": client_pc.localDescription.sdp,
                    "preferences": {"profile": "warm", "voice": "af_sarah"}
                }, headers={"Authorization": "Bearer local-test-secret-code"}, timeout=15)
            self.assertEqual(response.status_code, 200, response.text)
            await client_pc.setRemoteDescription(RTCSessionDescription(sdp=response.text, type="answer"))
            for _ in range(80):
                if client_pc.connectionState == "connected" and channel.readyState == "open":
                    break
                await asyncio.sleep(0.1)
            self.assertEqual(client_pc.connectionState, "connected")
            self.assertEqual(channel.readyState, "open")
        finally:
            await client_pc.close()
            await app.state.runtime.close()

