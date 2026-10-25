import {
  mediaDevices,
  RTCPeerConnection,
  RTCSessionDescription
} from 'react-native-webrtc';

export type Personality = 'grounded' | 'warm' | 'expressive';
export type Listening = 'natural' | 'quick' | 'soft';
export type Voice = 'af_sarah' | 'af_bella' | 'am_adam' | 'am_michael';
export type VoiceState = 'idle' | 'connecting' | 'ready' | 'listening' | 'thinking' | 'speaking' | 'error';

export type VoicePreferences = {
  profile: Personality;
  listening: Listening;
  voice: Voice;
};

export type ConnectionOptions = {
  serverUrl: string;
  pairingCode: string;
  preferences: VoicePreferences;
};

type Events = {
  onStatus: (status: VoiceState) => void;
  onText: (text: string) => void;
  onError: (message: string) => void;
};

export function validateServerUrl(raw: string): string {
  const value = raw.trim().replace(/\/+$/, '');
  const https = /^https:\/\/[^/?#\s]+(?::\d+)?$/i;
  const lan = /^http:\/\/(localhost|127\.0\.0\.1|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(?::\d+)?$/i;
  if (!https.test(value) && !lan.test(value)) {
    throw new Error('Use a local address like http://192.168.1.20:8787, or an HTTPS address.');
  }
  return value;
}

async function waitForIceGathering(pc: RTCPeerConnection, timeoutMs = 8000) {
  if (pc.iceGatheringState === 'complete') return;
  await new Promise<void>((resolve) => {
    let done = false;
    let timer: ReturnType<typeof setTimeout>;
    const finish = () => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      (pc as any).removeEventListener('icegatheringstatechange', check);
      resolve();
    };
    const check = () => { if (pc.iceGatheringState === 'complete') finish(); };
    // This native package implements EventTarget but its declaration does not expose inherited listeners.
    (pc as any).addEventListener('icegatheringstatechange', check);
    timer = setTimeout(finish, timeoutMs);
    check();
  });
}

export class VoiceConnection {
  private pc: RTCPeerConnection | null = null;
  private stream: Awaited<ReturnType<typeof mediaDevices.getUserMedia>> | null = null;
  private channel: ReturnType<RTCPeerConnection['createDataChannel']> | null = null;
  private generation = 0;
  private muted = false;

  constructor(private events: Events) {}

  async connect(options: ConnectionOptions) {
    this.disconnect();
    const generation = ++this.generation;
    const baseUrl = validateServerUrl(options.serverUrl);
    if (options.pairingCode.length < 12) throw new Error('The pairing code must have at least 12 characters.');
    this.events.onStatus('connecting');

    try {
      const stream = await mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        },
        video: false
      } as any);
      if (this.generation !== generation) { stream.getTracks().forEach(t => t.stop()); return; }
      this.stream = stream;

      // LAN-only peer: no third-party STUN or paid provider required.
      const pc = new RTCPeerConnection({ iceServers: [] });
      this.pc = pc;
      stream.getAudioTracks().forEach(track => pc.addTrack(track, stream));

      (pc as any).addEventListener('connectionstatechange', () => {
        if (this.generation !== generation) return;
        if (pc.connectionState === 'connected') this.events.onStatus('ready');
        if (pc.connectionState === 'failed' || pc.connectionState === 'closed') {
          this.events.onError('The voice connection ended. Tap Connect to try again.');
          this.disconnect();
        }
      });

      // The remote audio track is rendered by the native WebRTC audio engine.
      const dc = pc.createDataChannel('oai-events');
      this.channel = dc;
      (dc as any).addEventListener('message', (message: any) => this.handleEvent(message.data));
      (dc as any).addEventListener('open', () => {
        if (this.generation === generation) this.events.onStatus('ready');
      });

      const offer = await pc.createOffer({ offerToReceiveAudio: true, offerToReceiveVideo: false });
      await pc.setLocalDescription(offer);
      await waitForIceGathering(pc);
      if (this.generation !== generation) return;
      const sdp = pc.localDescription?.sdp;
      if (!sdp) throw new Error('Your phone could not create an audio connection.');

      const response = await fetch(`${baseUrl}/api/session`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${options.pairingCode}`
        },
        body: JSON.stringify({ sdp, preferences: options.preferences })
      });
      if (!response.ok) {
        let message = `The computer returned error ${response.status}.`;
        try { message = (await response.json()).error || message; } catch {}
        throw new Error(message);
      }
      const answer = await response.text();
      if (this.generation !== generation) return;
      await pc.setRemoteDescription(new RTCSessionDescription({ type: 'answer', sdp: answer }));
    } catch (error: any) {
      if (this.generation === generation) {
        const message = error?.message || 'Could not connect to the live voice service.';
        this.events.onError(message);
        this.disconnect();
      }
    }
  }

  setMuted(muted: boolean) {
    this.muted = muted;
    this.stream?.getAudioTracks().forEach(track => { track.enabled = !muted; });
  }

  get isMuted() { return this.muted; }

  disconnect() {
    ++this.generation;
    this.channel?.close();
    this.channel = null;
    this.pc?.close();
    this.pc = null;
    this.stream?.getTracks().forEach(t => t.stop());
    this.stream = null;
    this.muted = false;
    this.events.onStatus('idle');
  }

  private handleEvent(raw: string) {
    let event: any;
    try { event = JSON.parse(raw); } catch { return; }
    switch (event.type) {
      case 'input_audio_buffer.speech_started':
        this.events.onStatus('listening');
        break;
      case 'input_audio_buffer.speech_stopped':
        this.events.onStatus('thinking');
        break;
      case 'response.created':
      case 'response.output_audio.delta':
      case 'response.audio.delta':
        this.events.onStatus('speaking');
        break;
      case 'response.done':
        this.events.onStatus('ready');
        break;
      case 'response.output_audio_transcript.delta':
      case 'response.audio_transcript.delta':
        if (typeof event.delta === 'string') this.events.onText(event.delta);
        break;
      case 'conversation.item.input_audio_transcription.completed':
        if (typeof event.transcript === 'string') this.events.onText(`\nYou: ${event.transcript}\nAURA: `);
        break;
      case 'error':
        this.events.onError(event.error?.message || 'The realtime service reported an error.');
        break;
    }
  }
}

