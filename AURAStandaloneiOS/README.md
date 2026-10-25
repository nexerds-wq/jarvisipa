# JARVIS AURA — Standalone iPhone 16 IPA

This is a real iOS app project that does **not** require Ollama, Python, Wi-Fi
pairing, an IP address, or a computer running in the background.

## Requirements

- iPhone 16, running iOS 26 or newer.
- Apple Intelligence enabled under iPhone Settings and its system language
  model fully downloaded. This is Apple's own on-device model, so it is not
  bundled in the IPA. Apple Intelligence may be unavailable in some regions,
  languages, or device configurations.
- Microphone and Speech Recognition permissions for the app.
- An offline speech-recognition locale installed/supported by iOS. The app
  only uses recognition with `requiresOnDeviceRecognition = true`.
- Sign the unsigned IPA using an authorized iOS signing method.

## How it works

1. Tap **Talk to JARVIS**, speak, and tap **Finish Talking**.
2. Apple's on-device speech recognizer creates a live transcript.
3. Apple's on-device `FoundationModels` model generates a streamed reply,
   with conversational context preserved in memory until you reset it.
4. `AVSpeechSynthesizer` speaks sentences while later text is still generated.
5. Tap **Interrupt** to stop the voice or response. You can also type if
   microphone permission or offline speech recognition isn't ready.

Warm, Natural, and Expressive modes change the model instructions and vocal
rate/pitch. The app doesn't claim genuine emotions or provide automation tools.

## What “standalone” means

There are **no servers and no external paid APIs**. The operating system
supplies the local Apple Intelligence language model, speech recognition,
and synthesized voice. On first setup, iOS may have to download Apple
Intelligence or higher-quality voice assets through Settings. Once those
assets are ready, ordinary chat can run without an internet connection.

The IPA itself does **not** contain a multi-gigabyte model. The Apple system
model is a device dependency. This gives an iPhone 16 a substantially better
chance of responsive, private chat than a huge third-party model embedded
in an IPA, but availability and quality are still limited by iOS.

## Limits

- Not a movie-perfect JARVIS/FRIDAY voice. Uses iOS system voice quality.
- Not guaranteed to understand every whisper, voice, accent, or noise level.
- Tap-to-talk rather than always listening in the background.
- Text is streamed; audible speech starts at sentence boundaries, not literally
  word-by-word.
- The system model won't answer every topic and may be wrong. No live internet
  knowledge or external skills.
- Real on-device behavior must be verified on a physical iPhone 16.

## Build

The `.github/workflows/build-aura-ondevice-ipa.yml` workflow uses a macOS
runner, Xcode 26, and XcodeGen to compile a device `.app` with signing disabled
and package `AURA_On_Device_Unsigned.ipa`. Download the artifact, extract
the IPA, sign it, and install.

The original PC-hosted AURA and existing Jarvis HUD project are unaffected.
