# Offline Jarvis Voice

Jarvis can speak using on-device FluidAudio PocketTTS voice cloning.

1. Export the Jarvis VoiceStudio voice and extract ref_audio.wav from the .ovsvoice archive.
2. Put ref_audio.wav in the iPhone Files app.
3. Open Jarvis settings > Natural Jarvis Voice > IMPORT JARVIS REF_AUDIO.WAV and select that file.
4. Tap PREVIEW JARVIS VOICE. The first use downloads PocketTTS CoreML models over the internet (hundreds of MB). Following speech works locally without your PC.

The reference sample is stored in the app's private Application Support folder. Do not commit voice recordings to a public GitHub repository. Errors fall back to installed iPhone voices. A 2.64-second sample may sound different from the original VoiceStudio engine, so a longer clean reference may sound better.

FluidAudio SDK is Apache-2.0 licensed; the PocketTTS models are CC BY 4.0 with attribution required to Kyutai. VoiceStudio voice samples may have separate personal-use restrictions.
