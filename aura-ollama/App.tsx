import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Animated,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  View
} from 'react-native';
import * as SecureStore from 'expo-secure-store';
import {
  Listening, Personality, Voice, VoiceConnection, VoicePreferences, VoiceState
} from './src/realtime';

const PROFILE_OPTIONS: { id: Personality; title: string; detail: string }[] = [
  { id: 'grounded', title: 'Grounded', detail: 'Calm & thoughtful' },
  { id: 'warm', title: 'Warm', detail: 'Gentle & natural' },
  { id: 'expressive', title: 'Expressive', detail: 'Lively & playful' }
];
const VOICE_OPTIONS: Voice[] = ['af_sarah', 'af_bella', 'am_adam', 'am_michael'];
const LISTENING_OPTIONS: { id: Listening; title: string; detail: string }[] = [
  { id: 'natural', title: 'Natural', detail: 'Comfortable pauses' },
  { id: 'quick', title: 'Fast', detail: 'Quicker turn-taking' },
  { id: 'soft', title: 'Soft voice', detail: 'More sensitive to quiet speech' }
];

function StatusPill({ status }: { status: VoiceState }) {
  const label = {
    idle: 'OFFLINE', connecting: 'CONNECTING', ready: 'CONNECTED',
    listening: 'LISTENING', thinking: 'PROCESSING', speaking: 'SPEAKING', error: 'ERROR'
  }[status];
  const active = !['idle', 'error'].includes(status);
  return (
    <View style={styles.statusPill}>
      <View style={[styles.statusDot, { backgroundColor: active ? '#6EFFC3' : '#8190AD' }]} />
      <Text style={styles.statusText}>{label}</Text>
    </View>
  );
}

function SectionTitle({ eyebrow, title }: { eyebrow: string; title: string }) {
  return (
    <View style={styles.sectionHeader}>
      <Text style={styles.eyebrow}>{eyebrow}</Text>
      <Text style={styles.sectionTitle}>{title}</Text>
    </View>
  );
}

function AuraOrb({ status }: { status: VoiceState }) {
  const pulse = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const loop = Animated.loop(Animated.sequence([
      Animated.timing(pulse, { toValue: 1, duration: 1700, useNativeDriver: true }),
      Animated.timing(pulse, { toValue: 0, duration: 1700, useNativeDriver: true })
    ]));
    loop.start();
    return () => loop.stop();
  }, [pulse]);

  const speaking = status === 'speaking';
  const listening = status === 'listening';
  const working = status !== 'idle' && status !== 'error';
  const scale = pulse.interpolate({ inputRange: [0, 1], outputRange: [1, speaking ? 1.15 : listening ? 1.1 : 1.055] });
  const opacity = pulse.interpolate({ inputRange: [0, 1], outputRange: [0.2, speaking ? 0.8 : 0.52] });

  return (
    <View style={styles.orbFrame}>
      <Animated.View style={[styles.ringOuter, { transform: [{ scale }], opacity }]} />
      <View style={styles.ringMiddle} />
      <Animated.View style={[styles.orbGlow, { transform: [{ scale }] }]} />
      <View style={[styles.orb, !working && styles.orbDim]}>
        <View style={styles.orbHighlight} />
        <Text style={styles.orbLetter}>A</Text>
      </View>
      <View style={styles.orbLabelWrap}>
        <Text style={styles.orbLabel}>{speaking ? 'AURA IS RESPONDING' : listening ? 'I HEAR YOU' : working ? 'I’M HERE' : 'VOICE COMPANION'}</Text>
      </View>
    </View>
  );
}

export default function App() {
  const [status, setStatus] = useState<VoiceState>('idle');
  const [error, setError] = useState('');
  const [serverUrl, setServerUrl] = useState('');
  const [pairingCode, setPairingCode] = useState('');
  const [profile, setProfile] = useState<Personality>('warm');
  const [voice, setVoice] = useState<Voice>('af_sarah');
  const [listening, setListening] = useState<Listening>('natural');
  const [muted, setMuted] = useState(false);
  const [showSetup, setShowSetup] = useState(true);
  const [transcript, setTranscript] = useState('');
  const connection = useRef<VoiceConnection | null>(null);

  useEffect(() => {
    connection.current = new VoiceConnection({
      onStatus: setStatus,
      onText: delta => setTranscript(current => (current + delta).slice(-280)),
      onError: setError
    });
    let live = true;
    Promise.all([
      SecureStore.getItemAsync('aura.serverUrl'),
      SecureStore.getItemAsync('aura.pairingCode')
    ]).then(([savedServer, savedCode]) => {
      if (!live) return;
      if (savedServer) setServerUrl(savedServer);
      if (savedCode) setPairingCode(savedCode);
    }).catch(() => {});
    return () => { live = false; connection.current?.disconnect(); connection.current = null; };
  }, []);

  const connected = status !== 'idle' && status !== 'error';
  const busy = status === 'connecting';
  const prefs: VoicePreferences = useMemo(() => ({ profile, voice, listening }), [profile, voice, listening]);

  async function toggleCall() {
    if (connected) {
      connection.current?.disconnect();
      setMuted(false);
      setTranscript('');
      return;
    }
    setError('');
    setTranscript('');
    try {
      if (!serverUrl.trim() || !pairingCode.trim()) throw new Error('Enter your computer address and pairing code first.');
      await Promise.all([
        SecureStore.setItemAsync('aura.serverUrl', serverUrl.trim()),
        SecureStore.setItemAsync('aura.pairingCode', pairingCode.trim())
      ]);
      setShowSetup(false);
      await connection.current?.connect({ serverUrl, pairingCode: pairingCode.trim(), preferences: prefs });
    } catch (err: any) { setError(err?.message || 'Connection failed'); }
  }

  function toggleMute() {
    connection.current?.setMuted(!muted);
    setMuted(!muted);
  }

  const guidance = {
    idle: 'A conversation that feels less like talking to a machine.',
    connecting: 'Preparing a live audio connection…',
    ready: 'Go ahead. Just talk naturally.',
    listening: 'I’m listening. Take your time.',
    thinking: 'Let me think about that…',
    speaking: 'You can interrupt whenever you want.',
    error: 'Let’s try connecting again.'
  }[status];

  return (
    <SafeAreaView style={styles.safe}>
      <StatusBar barStyle="light-content" backgroundColor="#060C18" />
      <KeyboardAvoidingView style={styles.full} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={styles.page} keyboardShouldPersistTaps="handled">
          <View style={styles.topLine}>
            <View>
              <Text style={styles.brand}>AURA<Text style={styles.brandMark}>.</Text></Text>
              <Text style={styles.brandSub}>OLLAMA • LOCAL VOICE</Text>
            </View>
            <StatusPill status={status} />
          </View>

          <View style={styles.hero}>
            <AuraOrb status={status} />
            <Text style={styles.heroTitle}>A voice that <Text style={styles.heroAccent}>feels alive.</Text></Text>
            <Text style={styles.heroDescription}>{guidance}</Text>
            {!!transcript && <Text style={styles.transcript} numberOfLines={3}>{transcript}</Text>}
          </View>

          {!!error && (
            <View style={styles.errorBox}>
              <Text style={styles.errorTitle}>Connection issue</Text>
              <Text style={styles.errorText}>{error}</Text>
            </View>
          )}

          <Pressable onPress={toggleCall} style={({ pressed }) => [styles.primaryButton, pressed && styles.pressed]}>
            {busy ? <ActivityIndicator color="#061526" /> : <Text style={styles.primaryIcon}>{connected ? '■' : '●'}</Text>}
            <Text style={styles.primaryText}>{busy ? 'Connecting…' : connected ? 'End conversation' : 'Start conversation'}</Text>
          </Pressable>

          {connected && !busy && (
            <Pressable onPress={toggleMute} style={styles.muteButton}>
              <Text style={styles.muteText}>{muted ? '◌  Microphone muted — tap to unmute' : '◉  Microphone on — tap to mute'}</Text>
            </Pressable>
          )}

          <View style={styles.card}>
            <SectionTitle eyebrow="01 / PERSONALITY" title="How should AURA feel?" />
            <View style={styles.optionRows}>
              {PROFILE_OPTIONS.map(item => (
                <Pressable key={item.id} disabled={connected} onPress={() => setProfile(item.id)}
                  style={[styles.choice, profile === item.id && styles.choiceSelected, connected && styles.locked]}>
                  <View style={styles.choiceCopy}>
                    <Text style={[styles.choiceTitle, profile === item.id && styles.selectedText]}>{item.title}</Text>
                    <Text style={styles.choiceDetail}>{item.detail}</Text>
                  </View>
                  <View style={[styles.selectCircle, profile === item.id && styles.selectCircleOn]} />
                </Pressable>
              ))}
            </View>
          </View>

          <View style={styles.card}>
            <SectionTitle eyebrow="02 / VOICE" title="Choose a natural voice" />
            <View style={styles.voiceRow}>
              {VOICE_OPTIONS.map(item => (
                <Pressable key={item} disabled={connected} onPress={() => setVoice(item)}
                  style={[styles.voiceChip, voice === item && styles.voiceChipOn, connected && styles.locked]}>
                    <Text style={[styles.voiceChipText, voice === item && styles.selectedText]}>{item.split('_')[1]}</Text>
                </Pressable>
              ))}
            </View>
            <Text style={styles.helper}>Free offline Kokoro voices. You can switch voices between conversations.</Text>
          </View>

          <View style={styles.card}>
            <SectionTitle eyebrow="03 / LISTENING" title="Hear me how I speak" />
            {LISTENING_OPTIONS.map(item => (
              <Pressable key={item.id} disabled={connected} onPress={() => setListening(item.id)}
                style={[styles.listeningChoice, listening === item.id && styles.listeningChoiceOn, connected && styles.locked]}>
                <View>
                  <Text style={styles.choiceTitle}>{item.title}</Text>
                  <Text style={styles.choiceDetail}>{item.detail}</Text>
                </View>
                <View style={[styles.selectCircle, listening === item.id && styles.selectCircleOn]} />
              </Pressable>
            ))}
            <Text style={styles.helper}>Soft voice mode listens more carefully but can react to background noise. No recognizer understands every whisper.</Text>
          </View>

          <View style={styles.card}>
            <Pressable onPress={() => setShowSetup(!showSetup)} style={styles.setupHeader}>
              <View>
                <Text style={styles.eyebrow}>04 / CONNECTION</Text>
                <Text style={styles.sectionTitle}>Your computer</Text>
              </View>
              <Text style={styles.expand}>{showSetup ? '−' : '+'}</Text>
            </Pressable>
            {showSetup && (
              <View style={styles.setupFields}>
                <Text style={styles.fieldLabel}>SERVER ADDRESS</Text>
                <TextInput style={styles.input} value={serverUrl} onChangeText={setServerUrl}
                  editable={!connected} placeholder="http://192.168.1.20:8787" placeholderTextColor="#60708C"
                  autoCapitalize="none" autoCorrect={false} keyboardType="url" />
                <Text style={styles.fieldLabel}>PAIRING CODE</Text>
                <TextInput style={styles.input} value={pairingCode} onChangeText={setPairingCode}
                  editable={!connected} placeholder="Your secret pairing code" placeholderTextColor="#60708C"
                  autoCapitalize="none" autoCorrect={false} secureTextEntry />
                <Text style={styles.helper}>Use the PC’s local IP address. Keep both devices on the same trusted Wi-Fi network.</Text>
              </View>
            )}
          </View>

          <Text style={styles.footer}>NO TASK TOOLS  ·  NO CAMERA  ·  CONVERSATION ONLY</Text>
          <Text style={styles.footerSmall}>AURA simulates emotional expression. It does not have human feelings. Your PC processes speech locally with Ollama, Whisper, and Kokoro.</Text>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const C = {
  background: '#060C18', card: '#101B2C', border: '#26344D', pale: '#F5F9FF',
  muted: '#92A3BC', aqua: '#7CF3D3', blue: '#7DABFF'
};

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: C.background },
  full: { flex: 1 },
  page: { paddingHorizontal: 21, paddingTop: 17, paddingBottom: 52 },
  topLine: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  brand: { color: C.pale, fontWeight: '800', letterSpacing: 5, fontSize: 24 },
  brandMark: { color: C.aqua },
  brandSub: { color: '#6881A6', fontWeight: '700', fontSize: 9, letterSpacing: 3.3, marginTop: 4 },
  statusPill: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 11, paddingHorizontal: 13,
    backgroundColor: '#111C2C', borderColor: '#24354B', borderWidth: 1, borderRadius: 50 },
  statusDot: { width: 7, height: 7, borderRadius: 7 },
  statusText: { fontSize: 10, color: '#B8C7DC', fontWeight: '800', letterSpacing: 1.1 },
  hero: { alignItems: 'center', marginTop: 12, paddingBottom: 18 },
  orbFrame: { width: 296, height: 286, justifyContent: 'center', alignItems: 'center' },
  ringOuter: { width: 244, height: 244, borderRadius: 122, borderWidth: 1, borderColor: C.aqua,
    position: 'absolute', backgroundColor: '#1B6D76' },
  ringMiddle: { width: 214, height: 214, borderRadius: 107, borderWidth: 1, borderColor: '#3C728A', position: 'absolute' },
  orbGlow: { width: 166, height: 166, borderRadius: 85, position: 'absolute', backgroundColor: '#2E8898', opacity: 0.55 },
  orb: { width: 147, height: 147, borderRadius: 74, backgroundColor: '#0E5068', borderWidth: 2, borderColor: '#8FEFE6',
    alignItems: 'center', justifyContent: 'center', overflow: 'hidden', shadowColor: C.aqua, shadowOpacity: 0.7,
    shadowRadius: 24, shadowOffset: { width: 0, height: 0 } },
  orbDim: { opacity: 0.6 },
  orbHighlight: { width: 110, height: 70, borderRadius: 50, backgroundColor: '#398AA0', opacity: 0.34,
    position: 'absolute', top: -12, left: -20 },
  orbLetter: { color: '#DFFFFB', fontWeight: '200', fontSize: 80, letterSpacing: -5 },
  orbLabelWrap: { position: 'absolute', bottom: 3, backgroundColor: C.background, paddingHorizontal: 14 },
  orbLabel: { color: C.aqua, fontWeight: '800', fontSize: 10, letterSpacing: 2.3 },
  heroTitle: { color: '#F0F6FF', fontWeight: '700', fontSize: 25, textAlign: 'center', marginTop: 3, letterSpacing: -0.4 },
  heroAccent: { color: C.aqua },
  heroDescription: { color: C.muted, fontSize: 14, marginTop: 10, textAlign: 'center', lineHeight: 22 },
  transcript: { color: '#D6E7F3', fontSize: 14, fontStyle: 'italic', textAlign: 'center', marginTop: 15,
    paddingHorizontal: 16, lineHeight: 21 },
  primaryButton: { backgroundColor: C.aqua, borderRadius: 16, minHeight: 60,
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 13, marginTop: 9 },
  pressed: { opacity: 0.8 },
  primaryIcon: { color: '#083B4B', fontSize: 18 },
  primaryText: { color: '#082B37', fontSize: 16, fontWeight: '800' },
  muteButton: { borderWidth: 1, borderColor: '#345D68', borderRadius: 12, paddingVertical: 13, marginTop: 12 },
  muteText: { color: C.aqua, fontWeight: '700', textAlign: 'center', fontSize: 12 },
  card: { backgroundColor: C.card, borderColor: C.border, borderWidth: 1, borderRadius: 19, padding: 18, marginTop: 17 },
  sectionHeader: { marginBottom: 14 },
  eyebrow: { color: C.aqua, fontWeight: '800', fontSize: 9, letterSpacing: 2.1, marginBottom: 8 },
  sectionTitle: { color: '#EDF3FC', fontWeight: '700', fontSize: 18 },
  optionRows: { gap: 9 },
  choice: { backgroundColor: '#142238', borderColor: '#263751', borderWidth: 1, borderRadius: 13,
    minHeight: 66, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 15 },
  choiceSelected: { backgroundColor: '#1A3441', borderColor: '#5DDDC5' },
  choiceCopy: { gap: 4 },
  choiceTitle: { color: '#E3ECF8', fontSize: 14, fontWeight: '700' },
  choiceDetail: { color: C.muted, fontSize: 12 },
  selectedText: { color: C.aqua },
  selectCircle: { borderWidth: 2, borderColor: '#53657F', width: 17, height: 17, borderRadius: 9 },
  selectCircleOn: { borderColor: C.aqua, backgroundColor: C.aqua },
  voiceRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  voiceChip: { paddingVertical: 12, paddingHorizontal: 16, borderRadius: 11,
    borderColor: '#30425D', borderWidth: 1, backgroundColor: '#142238' },
  voiceChipOn: { borderColor: C.aqua, backgroundColor: '#1C3541' },
  voiceChipText: { color: '#C8D4E6', textTransform: 'capitalize', fontSize: 13, fontWeight: '700' },
  helper: { color: '#8497B2', fontSize: 11, lineHeight: 17, marginTop: 13 },
  listeningChoice: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingVertical: 13, paddingHorizontal: 13, marginBottom: 8, borderWidth: 1,
    borderColor: '#263751', borderRadius: 12, backgroundColor: '#142238' },
  listeningChoiceOn: { borderColor: '#5DDDC5', backgroundColor: '#1A3441' },
  locked: { opacity: 0.65 },
  setupHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  expand: { color: C.aqua, fontSize: 26, fontWeight: '300' },
  setupFields: { marginTop: 18 },
  fieldLabel: { color: '#B3C4D8', fontWeight: '800', fontSize: 9, letterSpacing: 1.5, marginTop: 7, marginBottom: 8 },
  input: { backgroundColor: '#081424', borderWidth: 1, borderColor: '#30435B', borderRadius: 11,
    color: '#F0F5FF', minHeight: 48, fontSize: 13, paddingHorizontal: 13, marginBottom: 11 },
  footer: { textAlign: 'center', color: '#658198', fontWeight: '800', fontSize: 9, marginTop: 26, letterSpacing: 1.2 },
  footerSmall: { textAlign: 'center', color: '#6D7E96', fontSize: 11, lineHeight: 17,
    marginTop: 11, paddingHorizontal: 15 },
  errorBox: { backgroundColor: '#3B222B', borderWidth: 1, borderColor: '#BA6270', padding: 13, borderRadius: 12, marginBottom: 7 },
  errorTitle: { color: '#FFB6B8', fontWeight: '800', marginBottom: 5 },
  errorText: { color: '#FFD5D5', fontSize: 12, lineHeight: 18 }
});

