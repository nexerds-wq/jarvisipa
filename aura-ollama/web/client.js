(() => {
  'use strict';
  const byId = id => document.getElementById(id);
  const ui = { connect: byId('connect'), mute: byId('mute'), profile: byId('profile'),
    voice: byId('voice'), listening: byId('listening'), pairing: byId('pairing'),
    error: byId('error'), status: byId('status'), dot: byId('dot'), guidance: byId('guidance'),
    transcript: byId('transcript'), orb: byId('orbZone'), audio: byId('remoteAudio') };
  let peer = null;
  let stream = null;
  let muted = false;
  let active = false;
  let spokenText = '';
  let lastHeard = '';

  function setState(state) {
    ui.status.textContent = state.toUpperCase();
    ui.dot.classList.toggle('online', state !== 'idle' && state !== 'error');
    ui.orb.dataset.state = state;
    ui.guidance.textContent = ({ idle: 'Private conversations, powered by your computer.',
      connecting: 'Preparing the local audio connection…', ready: 'Go ahead. Talk naturally.',
      listening: 'I hear you. Take your time.', thinking: 'Understanding what you said…',
      speaking: 'You can interrupt while AURA is speaking.', error: 'Check your computer and try again.' })[state] || state;
  }

  function displayTranscript() {
    ui.transcript.hidden = !(spokenText || lastHeard);
    ui.transcript.textContent = (lastHeard ? `You: ${lastHeard}\n\n` : '') + (spokenText ? `AURA: ${spokenText.slice(-500)}` : '');
    ui.transcript.style.whiteSpace = 'pre-wrap';
  }

  function handleEvent(raw) {
    let data;
    try { data = JSON.parse(raw); } catch { return; }
    if (data.type === 'input_audio_buffer.speech_started') setState('listening');
    if (data.type === 'input_audio_buffer.speech_stopped') setState('thinking');
    if (data.type === 'response.created') { spokenText = ''; setState('speaking'); }
    if (data.type === 'response.done') setState('ready');
    if (data.type === 'conversation.item.input_audio_transcription.completed') {
      lastHeard = data.transcript || ''; displayTranscript();
    }
    if (data.type === 'response.output_audio_transcript.delta') {
      spokenText += data.delta || ''; displayTranscript();
    }
    if (data.type === 'error') showError(data.error?.message || 'The local model reported a problem.');
  }

  function showError(text) {
    ui.error.hidden = false;
    ui.error.textContent = text;
  }

  async function waitForIce(pc) {
    if (pc.iceGatheringState === 'complete') return;
    await new Promise(resolve => {
      const finish = () => { pc.removeEventListener('icegatheringstatechange', check); clearTimeout(timer); resolve(); };
      const check = () => { if (pc.iceGatheringState === 'complete') finish(); };
      const timer = setTimeout(finish, 8000);
      pc.addEventListener('icegatheringstatechange', check);
      check();
    });
  }

  async function start() {
    if (!ui.pairing.value.trim()) { showError('Enter the pairing code from your PC first.'); return; }
    ui.error.hidden = true;
    setState('connecting');
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }, video: false
      });
      peer = new RTCPeerConnection({ iceServers: [] });
      peer.addTrack(stream.getAudioTracks()[0], stream);
      peer.ontrack = event => {
        ui.audio.srcObject = event.streams[0];
        ui.audio.play().catch(() => showError('Tap the screen to allow sound playback.'));
      };
      peer.onconnectionstatechange = () => {
        if (peer && ['failed', 'closed'].includes(peer.connectionState)) {
          showError('The local audio link was disconnected.'); stop();
        }
      };
      const channel = peer.createDataChannel('aura-events');
      channel.onmessage = event => handleEvent(event.data);
      channel.onopen = () => setState('ready');
      const offer = await peer.createOffer({ offerToReceiveAudio: true });
      await peer.setLocalDescription(offer);
      await waitForIce(peer);
      const response = await fetch('/api/session', {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${ui.pairing.value.trim()}` },
        body: JSON.stringify({ sdp: peer.localDescription.sdp,
          preferences: { profile: ui.profile.value, listening: ui.listening.value, voice: ui.voice.value } })
      });
      if (!response.ok) {
        let details = `Server error ${response.status}`;
        try { const result = await response.json(); details = result.detail || details; } catch {}
        throw new Error(details);
      }
      await peer.setRemoteDescription({ type: 'answer', sdp: await response.text() });
      active = true;
      ui.connect.textContent = '■  End conversation';
      ui.mute.hidden = false;
      [ui.profile, ui.listening, ui.voice].forEach(el => { el.disabled = true; });
    } catch (error) {
      stop();
      setState('error');
      showError(error.message || 'Could not start local voice.');
    }
  }

  function stop() {
    active = false;
    peer?.close(); peer = null;
    stream?.getTracks().forEach(t => t.stop()); stream = null;
    ui.audio.srcObject = null;
    ui.connect.textContent = '●  Start conversation';
    ui.mute.hidden = true;
    muted = false;
    [ui.profile, ui.listening, ui.voice].forEach(el => { el.disabled = false; });
    setState('idle');
  }

  ui.connect.addEventListener('click', () => active ? stop() : start());
  ui.mute.addEventListener('click', () => {
    muted = !muted;
    stream?.getAudioTracks().forEach(t => { t.enabled = !muted; });
    ui.mute.textContent = muted ? '◌  Unmute microphone' : '◉  Mute microphone';
  });
  window.addEventListener('beforeunload', stop);
  setState('idle');
})();

