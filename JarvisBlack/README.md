# JarvisBlack — offline voice assistant for iPhone 16 Pro Max

JarvisBlack is a black-screen, voice-only iPhone app. **The AI runs on the iPhone** using Apple's MLX Swift libraries. No Ollama server, OpenAI API, home computer or cloud inference is needed.

The existing Solos Jarvis bundle ID is **`com.nexer.solosjarvisbg`**, version `26.0` build `28`. This project lives on a separate branch and does not change the original JarvisGlasses source or workflow. Installing a correctly signed version with that same bundle ID replaces the old installed app and does not preserve the glasses HUD features.

## What works

- Completely black interface, without buttons or labels.
- Wakes to **"Hey Jarvis," "Hello Jarvis," "Hi Jarvis,"** or just **"Jarvis"** while speech recognition is running.
- Uses Apple speech recognition for commands and Apple's built-in text-to-speech for answers.
- Runs **Qwen3 8B 4-bit** locally through MLX. The app downloads model weights from Hugging Face on first AI use and caches them for later offline use. Allow several gigabytes of free storage, Wi-Fi, and time for the initial download.
- Keeps conversational context in memory while the app is running.
- Apple Music commands such as play, pause, resume, next and stop run locally using MusicKit. Apple Music playback may still require internet and a subscription.

## Important limitations

- **First model download needs internet.** After the download, AI generation itself is on-device. No speech transcripts or questions are sent to an AI server. Apple speech recognition may use Apple's online speech service if on-device recognition is unavailable.
- The 8B model uses substantial memory and can generate responses slowly or be terminated under memory pressure. This target is untested on the physical iPhone 16 Pro Max, so a smaller quantized model may be required.
- A black screen does not remove the microphone permission prompt or iOS privacy indicator.
- iOS does not allow a normal third-party app to act as a guaranteed, system-wide, always-on Siri replacement. The system can suspend recording in the background, particularly after the app is force-quit.
- Jarvis cannot know live weather, news or other changing facts offline. Music commands rely on Apple's MusicKit and are handled separately.

## Build on GitHub

1. Open the **Build JarvisBlack IPA** workflow on the `feature/jarvisblack-voice-ipa` branch of `nexerds-wq/jarvisipa`.
2. The macOS workflow uses XcodeGen to generate the project and Xcode to compile the iPhone app with MLX packages.
3. Download the `JarvisBlack-unsigned-IPA` artifact and unzip it. The enclosed `JarvisBlack-unsigned.ipa` needs an Apple signature and provisioning profile before installation.
4. To update the old Jarvis app, sign with a compatible team and the existing `com.nexer.solosjarvisbg` bundle ID.

The app automatically asks for microphone and speech recognition access. Speak a wake phrase followed by a command. The first AI request starts the model download, which may take a while; the screen stays black throughout.

## Source implementation

- `JarvisBlack/VoiceBackend.swift`: local MLX Qwen3 8B inference and cached model loading.
- `JarvisBlack/WakeListener.swift`: microphone audio and all four wake phrases.
- `JarvisBlack/VoiceSpeaker.swift`: local Apple speech output.
- `JarvisBlack/MusicCommands.swift`: on-device MusicKit commands.
- `project.yml`: MLX package dependencies and existing bundle identifier.

The `com.apple.developer.kernel.increased-memory-limit` entitlement requests additional available memory but is not a guarantee of enough memory for every model or firmware configuration. Test on an actual device before relying on background listening or continuous sessions.
