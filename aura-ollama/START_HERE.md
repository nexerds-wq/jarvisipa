# AURA Local Voice — completely free AI setup

This is a **source-code project**, not an already compiled `.ipa`. It includes a Windows-hosted local voice service, a working desktop browser interface, a native iPhone app project, and a **GitHub Actions workflow to compile an unsigned `.ipa`** for you to sign yourself.

There are no paid AI APIs or subscriptions in the code. Models run on your own computer after free one-time downloads. Hardware power and electricity still matter.

## What AURA does

- Talks about everyday subjects with a consistent personality and context within each conversation.
- Listens through a microphone, detects when you finish speaking, and tries to handle softer speech.
- Uses a local Whisper speech recognizer, local Ollama language model, and local Kokoro voice synthesizer.
- Starts speech from complete phrases as Ollama generates text, rather than waiting for the full response.
- Lets you interrupt its speech with your own voice (with microphone echo cancellation provided by the device).
- Supports Grounded, Warm, and Expressive personalities, four offline voices, and Natural / Fast / Soft listening modes.
- Contains no task tools, web-search access, camera, automations, or device controls.

**Real limits:** It isn't guaranteed to hear every whisper or accent, accurately detect emotion, or respond instantly. A small CPU-only model can feel slower and less expressive than cloud speech-to-speech. Audio comes in 20 ms WebRTC packets but generated speech is synthesized in phrase chunks, not instantly word by word. The actual performance must be measured on your computer.

## Part 1: Run it free on Windows right now

1. Install [Ollama](https://ollama.com/download) and [Python 3.12](https://www.python.org/downloads/) if needed.
2. In a PowerShell window, install the small default brain model:

   ```powershell
   ollama pull qwen3:1.7b
   ```

   This model download is roughly 1.4 GB. You may use `qwen3:0.6b` for a weaker computer by changing `OLLAMA_MODEL` in `.env` and downloading that model instead.

3. Open PowerShell inside the unzipped `aura-ollama` folder and run:

   ```powershell
   py -3.12 -m venv .venv
   .\.venv\Scripts\python.exe -m pip install -r requirements.txt
   .\.venv\Scripts\python.exe download_models.py
   Copy-Item .env.example .env
   ```

4. Edit `.env` and replace `PAIRING_CODE` with a long secret of your own (12 characters minimum). No API key is needed.
5. Start the PC voice server:

   ```powershell
   .\.venv\Scripts\python.exe run_local.py
   ```

6. On that same computer, open [http://localhost:8787](http://localhost:8787), choose the voice and personality, enter your pairing code, and tap **Start conversation**.

The first conversation might be slow because Whisper loads/downloads its free speech recognition model and Kokoro loads its voice weights. Later conversations should be faster, depending on your hardware. Internet is needed for initial software/model downloads but not for normal voice processing once all models are installed.

## Part 2: Make an unsigned `.ipa` for yourself to sign

The native iPhone project uses Expo/React Native with the WebRTC native module. An actual iPhone binary **must be compiled using Xcode on macOS**. Since you said you will handle signing, I included an unsigned build workflow that does not ask for your signing certificate.

1. Make a new GitHub repository and upload the **contents of this `aura-ollama` folder** (including its hidden `.github/workflows` folder). Do not upload `.env`, `.venv`, `node_modules`, or downloaded voice models. If your repository is public, check the files before uploading; the included `.gitignore` protects the standard local secrets.
2. In GitHub, open **Actions** and choose **Build unsigned AURA iPhone IPA**.
3. Click **Run workflow**.
4. Wait for the macOS runner to generate the native project, compile the app, and package `Payload/*.app` into `AURA_Local_Unsigned.ipa`.
5. Download the workflow artifact named **AURA_Local_Unsigned_IPA**. Extract its outer GitHub artifact ZIP. The `.ipa` is inside.
6. Sign that `.ipa` with your own certificate/provisioning or compatible signing method, then install it on your iPhone.

The workflow is included and configured, but **has not been run on a macOS build runner in this environment**, so native compile issues are still possible. The unsigned archive is not directly installable before signing. GitHub Actions standard hosted runners are generally free for public repositories; private repositories have usage quotas.

If you have access to a Mac, you can also run `npm ci`, `npx expo prebuild --platform ios`, then build locally in Xcode. Apple allows free on-device Xcode testing with a Personal Team, but free provisioning expires after 7 days.

## Part 3: Connect the signed iPhone app to your PC

1. Start Ollama and AURA's Python server on your computer.
2. Run `ipconfig` in Windows PowerShell to find your PC's local IPv4 address (like `192.168.1.20`).
3. Allow inbound TCP port **8787** in Windows Firewall on the **Private network only**.
4. Connect the iPhone and computer to the same trusted Wi-Fi.
5. In the iPhone app's **Your computer** section, enter `http://YOUR-PC-IP:8787` and your pairing code.
6. Choose your voice and profile, start the conversation, and accept microphone access.

This local network connection uses HTTP and its pairing code can be exposed to people monitoring that LAN. Don't use public Wi-Fi or forward port 8787 to the internet. Add HTTPS and stronger device authentication if you ever use it outside your trusted home network.

## What each free piece does

| Module | Purpose | Cost |
| --- | --- | --- |
| Ollama + Qwen3 1.7B | Generates personality-driven responses, streams tokens | Free download / local CPU or GPU |
| Faster-Whisper `base` | Turns speech into text | Free, local |
| Kokoro ONNX (quantized) | Generates a natural-sounding offline voice | Free, local |
| WebRTC + aiortc | Two-way audio connection and interruptions | Free, open source |
| Expo + React Native | iPhone interface | Free source; building/signing are separate |

The Kokoro voice is not identical to an actor's voice. Do not expect a perfect JARVIS/FRIDAY recreation. AURA has no real feelings; personality and emotion are simulated in language, pacing, and mild voice-speed changes.

## Troubleshooting

| Problem | Try this |
| --- | --- |
| Ollama won't answer | Confirm Ollama is running, then run `ollama list` and check the model name in `.env`. |
| Speech takes a long time | Start with `qwen3:0.6b`, change `WHISPER_MODEL=tiny`, or use a stronger GPU/CPU. |
| Soft speech isn't detected | Select Soft voice mode, use a close microphone, reduce noise. That mode can create false detections. |
| App connects but no sound | Check headphones/phone output routing and microphone permission. iOS playback still needs a device test. |
| Desktop microphone is blocked | Open `http://localhost:8787` on the hosting PC; browsers don't allow microphone on insecure remote HTTP pages. |
| Phone can't connect | Both on same trusted Wi-Fi, correct PC IP, firewall port 8787, Python server running, pairing code correct. |
| Workflow fails on macOS | Open the GitHub Actions log. Expo, WebRTC, Xcode, and CocoaPods can change; native compilation has not been verified here. |

## Privacy

The PC server processes your audio locally. This code doesn't call paid AI providers, retain transcripts on disk, or make external tool calls. The temporary conversation history lives in RAM and is cleared on disconnect. Model installers contact their download sites once. Your Windows firewall and network security still matter.

## References

- [Ollama chat API](https://docs.ollama.com/api/chat)
- [Faster-Whisper](https://github.com/SYSTRAN/faster-whisper)
- [Kokoro ONNX](https://github.com/thewh1teagle/kokoro-onnx)
- [Expo local iOS development builds](https://docs.expo.dev/develop/development-builds/introduction/)
- [Apple free developer account limitations](https://developer.apple.com/help/account/basics/about-your-developer-account/)

