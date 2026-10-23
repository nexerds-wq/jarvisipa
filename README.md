# Jarvis Solos HUD — Original Display (V25)

This is the iPhone-native SolosDirect HUD app for the original Solos 428 x 240 waveguide display, restored from the proven-compiling `jarvis-hud-first-ios-v25-20261022` codebase.

## Features
- 7 HUD pages: Dashboard, Navigation, Live Captions, Translation to English, Messages, Jarvis AI, Timers/Reminders
- Front/back on-phone HUD controls and optional hardware control learning when packets reach the app
- Phone time/date, pedometer steps/distance, battery, optional Apple Health heart rate
- English captions from on-device speech recognition, offline language packs for Apple Translation
- Manually pinned messages and iOS Shortcuts relay (iOS doesn't expose all iMessages)
- Local iPhone Foundation Models where supported, and optional network-accessible Ollama server with optional search
- Cached 428 x 240 HUD rendering with reduced refresh load

## IPA
[Build Jarvis Solos HUD IPA](https://github.com/nexerds-wq/jarvisipa/actions/workflows/main.yml). After a successful run, open **Artifacts** and download **Jarvis-Solos-HUD-V25-unsigned-IPA**. Extract the IPA and sign/sideload it using your own Apple account with Sideloadly or another legitimate signer.

The IPA is unsigned and requires iOS 26 or newer for the Apple Foundation Models / Translation features.

## Original Solos connection limits
The original Solos LCD/OLED display uses a proprietary Bluetooth Classic RFCOMM image channel (428 x 240 RLE565). Normal iOS Bluetooth pairing and audio do **not** enable access to that channel. The app includes ExternalAccessory connection testing and the display packet renderer, but physical display delivery works only when the glasses expose a compatible authorized ExternalAccessory data stream. A prior successful IPA build confirms compilation, *not* glass-lens display operation.

The existing `JarvisGlasses/` folder remains in this repository as an older separate M02S app; the current IPA workflow builds `SolosDirectiOS/` instead.
