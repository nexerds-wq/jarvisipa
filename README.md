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

## Startup stability investigation (V32)

- V31 was reported to show a white screen and crash on a physical iPhone even though the unsigned app compiled. The exact device crash log is not yet available, so this is a precautionary startup fix, not a confirmed root-cause diagnosis.
- V32 draws a minimal branded launch screen first, then loads the full command center. Microphone capture, accessory refresh, weather/location, health and HUD rendering begin in short delayed stages after the first visible frame. This reduces simultaneous startup work and overlapping permission requests.
- Decorative Canvas drawing now rejects non-finite layout sizes, and the animated core uses bounded rotation angles. These changes protect against pathological layout inputs without changing the glasses HUD rendering.
- The separate simulator launch workflow tests whether an iOS Simulator can boot, install, launch and keep Jarvis alive. Its boot and app-launch steps have timeouts to avoid hanging indefinitely on GitHub-hosted macOS runners.
- If V32 still crashes on your device, send the most recent **Settings → Privacy & Security → Analytics & Improvements → Analytics Data → SolosDirect** `.ips` crash file (or an Xcode Device Logs report). The exception and thread stack will allow us to identify which startup component is failing.

## JARVIS Command Center redesign + human-paced conversation (V31)

- New iPhone interface: midnight-blue atmospheric background, animated reactive central core, glass-style control panels, bright cyan controls, direct mic/voice actions, live conversation bubbles, redesigned glasses preview, connection diagnosis cards, and the full seven-module HUD switcher. The actual glasses output stays the same proven 428×240 high-contrast bitmap format.
- The existing strong vibrating outlines are kept separate: **blue for real user microphone activity**, **orange for Jarvis speech**. The phone's central orb uses these same live signals. Reduce Motion stops decorative movement.
- Jarvis uses **context-aware, sentence-level speech performance**, using local Apple voices. Spoken sentences can sound more reassuring, upbeat, playful or urgent based on their text. An urgent response stays direct; Jarvis avoids forced jokes about serious problems. This is pitch/rate/pause control, **not human emotion recognition or professional studio-quality neural TTS**. The free voices depend on iOS voice installations.
- Optional **Expressive speaking**, voice-expression strength, and **Patient listening** switches are in Advanced settings. Patient listening waits about 2.7 seconds after the last recognized word and waits for the microphone to quiet before replying. Saying **"that's all"** or **"I'm done"** at the end of a question finishes sooner. Wake-only acknowledgements now wait for the user to pause instead of interrupting immediately.
- Local Apple Foundation Models and optional Ollama conversation instructions now encourage natural humor when appropriate, useful emotional support when asked, and direct emergency guidance. Jarvis never claims to identify feelings from audio or replace real people or services.
- The seven HUD modules are accessible through the phone's next/back buttons and HUD workspace. Bluetooth *display* output still requires an authorized accessory protocol; visual UI improvements do not bypass that iOS limitation.
- **Interrupt now:** the core's right action changes to **STOP JARVIS** while speaking. The conversation card's **QUIET** button also stops speech. Voice 'stop talking' works when the microphone is listening, but the mic is paused during Jarvis playback to avoid echo and Bluetooth route problems; true hands-free barge-in while it is talking is not guaranteed.
- **Safety Watch:** the existing National Weather Service alerts and Open-Meteo rain forecast appear alongside an on-demand public news-headline search for traffic/crash/closures by city or area, auto-filled from location when available. Headlines are not verified road incidents, cannot show exact nearby danger or replace emergency alert systems, and must not be used as the only safety decision source. NWS warnings apply to the United States; the app cannot promise worldwide alerts or uninterrupted checks when suspended by iOS.
- **Research Lab:** free on-demand Wikipedia context and recent Google News RSS headlines with clickable original sources and no research subscription. For advanced natural-language questions, supported iPhones use Apple's on-device model or an optional configured Ollama setup. Availability depends on online public sources and user settings.
- **Life Organizer:** create local saved notes and timers, write authorized reminders directly into **Apple Reminders** using EventKit, and schedule true iOS 26 **AlarmKit** system alarms with visible alarm UI and a permission prompt. AlarmKit does **not** insert alarms into the Clock app's private list; Clock alarms can still be added through Clock/Siri. Voice commands support relative reminders, alarms, timers, note-taking and research when a clear command is recognized.

## Free, natural Jarvis voice (V30)

- In **Advanced → AI • Privacy • Speech → Natural Jarvis Voice**, choose **Automatic** to use the best English voice currently installed on the iPhone, or pick one of the listed voices. The voice list labels Apple's standard, enhanced and premium quality tiers.
- Choose a **Natural**, **Calm** or **Bright** delivery and adjust the speaking pace. Tap **PREVIEW JARVIS VOICE** to hear the selected voice. The main screen's **VOICE TEST** uses the same setting.
- All Jarvis responses, including the Hey Jarvis acknowledgement, use the selected voice. Text-to-speech runs locally with Apple's built-in speech synthesizer. There are **no voice subscriptions, online TTS API calls or charges**.
- To install additional free higher-quality voices, look in iPhone **Settings → Accessibility → Spoken Content → Voices** (menu names can vary by iOS version). Downloaded voices appear in the app after reopening it. A particular TikTok narrator voice is not included or guaranteed; voice quality depends on what iOS provides and which voices are downloaded.

## Clearer, continuous voice capture (V29)

- The preferred microphone on a fresh installation is the **iPhone mic**, which avoids forcing audio through the lower-quality Bluetooth hands-free call route. An existing saved mic choice is respected. Choose **Advanced → Jarvis microphone → iPhone** if an older installation is still using the headset mic. Keep the phone close enough to hear you clearly.
- **Bluetooth headset** remains available for hands-free use. On iOS 26, Jarvis enables Apple's high-quality Bluetooth recording option for compatible AirPods; unsupported headsets fall back to their normal recording route. The microphone name and actual audio format sample rate appear in the listening status.
- Jarvis waits for a more natural pause before submitting a question. It also watches microphone activity so a short thinking pause doesn't cut your sentence in half, and it keeps collecting words across speech recognizer session rotations instead of discarding your question.
- Live speech requests use dictation mode without automatic punctuation insertion. The system speech recognizer can still revise uncertain words; an app cannot guarantee perfect transcription or disable every language-model correction.
- The captions/conversation screen also defaults to the iPhone microphone for nearby speech. Its existing switch can select a headset when you need hands-free capture.

**Quick test:** With the app open, look at its microphone name, sample rate and blue speaking outline. Say "Hey Jarvis, I need to ask something, and I'm going to pause, because I don't want you to cut me off, what time is it?" If it still misses words, try the iPhone mic up close, then the Bluetooth headset mode, and compare the "Last heard" transcript. Online speech recognition remains opt-in because it may send audio to Apple; it is not enabled by this update.

## Voice reply and reactive outlines (V28)

- A **blue inner outline** vibrates with actual iPhone/headset microphone energy when you are talking, including in captions/conversation mode. An independent **orange outer outline** pulses while the iOS speech synthesizer is actually speaking. Both remain faint while idle. Reduce Motion keeps the outlines static.
- You can say **"Hey Jarvis"**, wait for **"Yes, I'm listening"**, and then ask your question without repeating the wake phrase (within 12 seconds). You can also say **"Hey Jarvis, what time is it?"** in one sentence. Wake-only phrases from the separate captions/conversation mode use the same acknowledgement.
- Jarvis temporarily pauses microphone capture while replying, then resumes listening if continuous wake is enabled. This prevents Jarvis from recognizing its own speech as a new question.
- The **Any Bluetooth headset** microphone option now falls back to the iPhone microphone when no Bluetooth headset microphone is available. Selecting **Solos only** still requires that specific microphone. Captions/conversation mode also accepts Solos, a regular Bluetooth headset, or the iPhone mic instead of requiring Solos.
- Jarvis shows its microphone status and last recognized words on the main screen. In Advanced settings, keep **Speak Jarvis answers** enabled for audible responses. If offline speech recognition isn't installed, enable online recognition deliberately or download a language pack; the app does not silently enable cloud speech.
- Local AI questions require an iOS 26 device with Apple Intelligence ready. If the model is unavailable or fails, Jarvis now gives a brief spoken explanation rather than leaving you with silence. For time and date questions, Jarvis uses the iPhone clock directly.
- If a configured Ollama conversation server cannot be reached, Jarvis reports the connection problem and tries the iPhone's local AI path. It does not pretend that an unavailable server answered.

**Test after sideloading:** Open Jarvis, allow Microphone and Speech Recognition, check the voice-status text, say "Hey Jarvis" and wait for its spoken acknowledgement. Ask "What time is it?" and watch the blue ring while you speak and orange ring while Jarvis replies. Use the **VOICE TEST** button if audio is still silent, then verify the iPhone/Bluetooth audio output in Control Center. The outlines are only visible inside this app; iOS does not allow a third-party always-on outline over the Home Screen or other apps. A successful unsigned IPA build does not prove microphone or Bluetooth hardware behavior on a physical phone.


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
