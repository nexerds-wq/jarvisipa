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

## Apple Music voice playback — full catalog attempt without MusicKit tokens

Say **"Hey Jarvis, play Blinding Lights by The Weeknd"**, or another song and artist. Jarvis uses Apple's *public iTunes Store search* to find a track identifier and sends it to the iPhone's system Music player using `MPMusicPlayerController.setQueue(with: [storeID])`. Apple's documented store-ID queue does not use MusicKit's developer token. This attempts to play tracks **even if they have not been added to your library**, provided your Apple Music subscription and storefront permit the track.

**Setup:** Enable *Listen for Hey Jarvis when possible* in Jarvis Settings; allow Media & Apple Music permissions; have an active Apple Music subscription; connect the iPhone to the internet. Songs may not be available in all regions, and the iTunes Store result must match an Apple Music-playable store ID. Playback is verified using the iOS Music player's state rather than assumed to succeed.

**Fallback:** If the full-catalog request fails or playback is unavailable, Jarvis checks the Music library. If that also doesn't work, the *Open in Apple Music* button takes you to search; you must tap the desired song. The fallback never claims it auto-played a song when it didn't.

**Controls:** "Hey Jarvis pause music", "Hey Jarvis resume music", "Hey Jarvis next song", and "Hey Jarvis previous song". The current music selection/status is displayed on Jarvis HUD. Note that iOS may suspend third-party wake-word recognition while playing music or in the background; you can use Siri or the on-screen controls.

For the original Solos display, Bluetooth audio output is separate from the authorized HUD image data connection. A passing GitHub IPA compile does not prove real-lens image delivery.


## Voice shutdown and stop commands + Apple Music audio stability

Jarvis recognizes locally spoken phrases such as "Hey Jarvis stop", "Hey Jarvis stop everything", "Hey Jarvis quit", "Hey Jarvis exit", "Hey Jarvis power off", "Hey Jarvis shutdown", "Hey Jarvis go to sleep", "Hey Jarvis wake up", "Hey Jarvis stop listening", "Hey Jarvis start listening", "Hey Jarvis be quiet", "Hey Jarvis stop music", "Hey Jarvis stop navigation", "Hey Jarvis stop captions", "Hey Jarvis stop translation" and "Hey Jarvis cancel timer", plus related common variations. These commands do not use Ollama. The bare "stop" command stops the current HUD function rather than arbitrarily stopping all functions. "Stop everything" stops navigation, captions, translation, music, speech and timers.

"Power off", "shutdown", "sleep" and related commands **black out the 428×240 HUD** (when an authorized accessory display is connected) and pause active features. They DO NOT switch off the glasses' electronics or shut down the iPhone. "Quit" also turns off Jarvis's microphone; to wake after quit, tap WAKE JARVIS in the iPhone app. "Wake up" works by voice only while iOS still permits microphone speech recognition.

**Music pause fix**: Previous releases installed callbacks for headset play/pause/next/previous as HUD page buttons. That can intercept Apple Music remote controls. This release does NOT install those callbacks by default; the optional setting *Use Bluetooth headset track controls for HUD navigation* re-enables them (not recommended while playing music). This release also suspends Jarvis microphone recognition on music requests by default, because opening a .voiceChat audio session during Apple Music playback can change the audio route or interrupt streaming. For voice commands **while music is playing**, opt into *Keep Jarvis microphone active during music*; music interruptions can recur on some iPhone/Bluetooth routes. With the default (mic suspended), use headset controls, the phone UI or Siri to pause, skip or resume; "Hey Jarvis stop" cannot be heard while the mic is suspended. The app does not claim true always-on custom wake words in iOS background.

**Any-song catalog**: The app still uses public iTunes Store song lookup and MediaPlayer store-ID queues to try directly playing songs not saved in the library, without MusicKit developer-token requests. Apple does not guarantee every Store ID is playable on every Apple Music subscription, iPhone, or storefront. For unavailable tracks, the Apple Music search fallback remains available. Full MusicKit-backed catalog access requires registering MusicKit App Service for the signed app ID.
