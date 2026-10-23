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


## Voice HUD control and captions (October 22 update)
Enable **Settings → Listen for Hey Jarvis when possible** while you are on the Dashboard, Navigation, Messages, Jarvis, or Timers screen. Then say **“Hey Jarvis captions”**, **“Hey Jarvis navigation”**, or **“Hey Jarvis translation”** to switch HUD pages. You can also say **“Hey Jarvis dashboard”**, **“Hey Jarvis messages”**, and **“Hey Jarvis timers”**. Commands work in the English caption screen when recognized; the Spanish recognizer in Translation mode may not reliably catch an English-language command, so the on-screen BACK/NEXT buttons remain available. iOS may suspend speech in the background.

**Captions:** the app now displays the last fitting whole words on the 428×240 panel and sends a trailing update after speech stabilizes, instead of leaving only the first recognized fragment.

**Spanish translation:** set **TRANSLATE → Spoken language → Spanish**, allow Microphone and Speech Recognition, and choose **Retry / download translation models** if necessary. The app uses Apple's offline Translation language models. Download Spanish and English in Apple Translate first if prompted. The HUD shows heard Spanish while translating, then English once an actual translation is ready. You can opt into online speech *recognition* for better input accuracy (not a guaranteed translation improvement).

**8–10 foot conversation:** enable **Use iPhone microphone for people farther away** (default), face the iPhone toward the speaker, and minimize noise. Speech recognition accuracy is not guaranteed at this distance and may require a closer or external microphone.

The IPA remains unsigned and actual lens image transmission still depends on a supported Bluetooth data transport on iOS.

## Apple Music voice playback — token-free library mode

**Problem fixed:** The old Apple Music integration used a MusicKit catalog request and raised "Failed to request developer token" on sideloaded apps. This version does **not** call MusicKit when playing library songs.

1. Install the latest IPA and enable **Listen for Hey Jarvis when possible**, or tap **Listen** in Jarvis.
2. Say **"Hey Jarvis, play [song title] by [artist]"**. The app requests access to the **Media & Apple Music** library and searches for songs you have added to your Music library. If found, it uses Apple's built-in system music player to start playback directly, without a developer token.
3. Say **"Hey Jarvis pause music"**, **"Hey Jarvis resume music"**, **"Hey Jarvis next song"**, or **"Hey Jarvis previous song"** for playback controls.
4. If the requested song is not in your Music library, tap **OPEN IN APPLE MUSIC • SEARCH FULL CATALOG** in Jarvis. The Apple Music app opens the search; **select the song there yourself** to play it.

**Limit:** Songs not in your library cannot be automatically selected and played by voice through the full Apple Music catalog without a properly registered MusicKit App Service or another supported Apple playback workflow. Search links are not auto-play. For future full-catalog MusicKit access, register MusicKit App Service for the *exact* signed bundle ID with Apple Developer. The unsigned IPA does not register that app service automatically.

For playback through the Solos glasses' speakers, pair the glasses as a Bluetooth audio output in iOS. Image transmission on the 428×240 HUD is a separate connection. Continuous "Hey Jarvis" listening may be suspended by iOS while music plays or when the app is backgrounded. Siri can still control Apple Music using "Hey Siri, play ...".
