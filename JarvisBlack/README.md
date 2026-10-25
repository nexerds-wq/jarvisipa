# JarvisBlack — voice-only iPhone assistant

An iPhone app with a black screen, no controls, and the wake phrase **“Hey Jarvis.”**
It uses speech recognition to listen for that phrase, sends ordinary questions to a private AI server, speaks responses using a natural AI voice, and controls Apple Music by voice.

This is a **buildable source project**, not yet a tested or signed IPA. The GitHub Actions workflow compiles the iOS app on a Mac runner and packages an **unsigned** IPA.

## What it does

- Black launch screen and black app screen. No visible buttons or text.
- Automatically asks for microphone and speech recognition permission the first time it opens.
- Recognizes “Hey Jarvis” (including a few common speech-recognition spellings), followed by a spoken command.
- Uses Apple's on-device speech recognition when the device supports it. Otherwise speech recognition may use Apple's online service.
- Attempts to keep listening while the app is running; restarts speech-recognition sessions as needed.
- Answers general questions using an OpenAI model and speaks with OpenAI's `marin` voice; falls back to the iPhone's built-in voice if the server's speech generation fails.
- Uses Apple Music for “play [song or artist],” “pause music,” “resume music,” “next song,” and “stop music.” Music authorization and an eligible Apple Music account are required.
- The cloud OpenAI API key stays on the server, never inside the IPA.

## Important iOS limitations

This is **not** a replacement for Siri's system-level always-on wake word. iOS can interrupt or suspend background recording; the app cannot secretly listen after you force-quit it, restart the phone, or revoke permission. An iPhone microphone privacy indicator and the initial system permission prompts cannot be hidden. A blank app UI does not remove those iOS privacy indicators.

Long-running microphone use has a battery cost and the background audio mode must correspond to a real, active audio feature. Actual background operation and music/recording coexistence need testing on an iPhone 16. Recognition accuracy depends on the microphone, noise level, and Apple's speech engine; no implementation can guarantee perfect detection.

## 1. Run the private voice server

Use any Node.js 20+ host with HTTPS in front of the server. The supplied server binds to `127.0.0.1`; put it behind a TLS reverse proxy or private HTTPS tunnel.

Set these environment variables on the server (never commit their real values):

| Variable | Purpose |
| --- | --- |
| `OPENAI_API_KEY` | Your OpenAI API key, server-side only |
| `JARVIS_CLIENT_TOKEN` | Long random access token used by the iPhone client (at least 20 characters) |
| `JARVIS_MODEL` | Optional text model; default `gpt-5.1` |
| `PORT` | Optional local port; default `3000` |

Run `cd server && npm start`.

There is also a local mock mode for backend testing: set `JARVIS_MOCK=1`, set a long `JARVIS_CLIENT_TOKEN`, and run `npm start` without an OpenAI key.

This starter server includes a basic shared client token and rate limit. For real public deployment, add device-specific authentication and abuse protection; the client token is extractable from an IPA, so do not treat it as strong protection against a determined attacker.

## 2. Configure the iPhone app

In `JarvisBlack/Info.plist`, change:

- `JARVIS_SERVER_URL` to your **HTTPS** server address (do not include `/chat`).
- `JARVIS_CLIENT_TOKEN` to the server's access token.

Open the project in Xcode. Set your own bundle identifier and select your Apple developer team under **Signing & Capabilities**. Enable MusicKit for that App ID in your developer account if required by your Apple Music setup.

On the iPhone, grant microphone, speech recognition, and Apple Music access when prompted. Ask “Hey Jarvis, play [song]” to authorize Apple Music on first use.

## 3. Build with GitHub Actions

1. In `nexerds-wq/jarvisipa`, this app lives in a separate `JarvisBlack/` folder, with its build workflow at the repository root: `.github/workflows/jarvisblack-ipa.yml`. The existing `JarvisGlasses` app and its workflow remain unchanged.
2. Open **Actions → Build JarvisBlack IPA** to run the workflow, or push to the feature branch to trigger its build.
3. Wait for the macOS job to compile.
4. Download the `JarvisBlack-unsigned-IPA` workflow artifact and unzip the download.
5. You will find `JarvisBlack-unsigned.ipa` inside.

This IPA is not directly installable because it has no Apple code signature. A signing or sideloading process must sign it using an Apple ID / provisioning profile for the target iPhone, or use Xcode on a Mac with your signing team. Follow the rules for whichever installation method you choose.

If you prefer a signed IPA from GitHub Actions, that requires Apple certificates, a provisioning profile, the exact app identifier, and the target device's registration; none are bundled here.

## 4. Test checklist on an iPhone 16

- The launch screen and entire app screen are black.
- The microphone and speech permission prompts appear once and can be granted.
- “Hey Jarvis, what's the weather?” triggers an answer when the AI server is configured.
- Saying just “Hey Jarvis,” waiting briefly, then asking a question works.
- A normal conversation without the wake phrase does not trigger commands.
- “Hey Jarvis, play [song name]” requests music permission and plays a matching Apple Music track.
- Music pause, resume, skip, and stop work.
- Test with headphones and in noisy environments; compare false positives and missed wake phrases.
- Lock and unlock the phone and test background interruptions. Do not assume indefinite listening.

## Privacy

Wake detection starts locally where on-device recognition is supported. Once you speak a command, its recognized text and recent conversation history are sent to the configured server for AI replies. The server sends text to OpenAI and may synthesize voice there. No voice recordings are saved by this starter code. Do not expose the server without HTTPS and authentication.

## Technical notes

- iOS 17+ target, SwiftUI, AVAudioEngine, Speech, MusicKit.
- The app has no visual controls; if permission is denied, enable it manually in iOS Settings.
- The no-screen layout is intentional, so initial configuration happens through the app build rather than on-device fields.
- `server/server.test.js` can be checked with `cd server && npm test`.
- Requires Xcode on GitHub's macOS runner; this Linux workspace cannot compile or sign an actual IPA.
