import unittest
from fastapi.testclient import TestClient
from local_server.app import create_app
from local_server.settings import Settings


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(create_app(Settings(pairing_code="a-long-secret-code")))

    def test_health(self):
        response = self.client.get('/health')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['provider'], 'ollama')

    def test_pairing_required(self):
        response = self.client.post('/api/session', json={'sdp': 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'})
        self.assertEqual(response.status_code, 401)

    def test_invalid_audio_offer(self):
        response = self.client.post('/api/session', json={'sdp': 'not an offer'}, headers={'Authorization': 'Bearer a-long-secret-code'})
        self.assertEqual(response.status_code, 400)


if __name__ == '__main__':
    unittest.main()

