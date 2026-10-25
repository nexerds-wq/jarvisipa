# Build your unsigned AURA `.ipa`

You said you'll sign the app yourself, so the included GitHub Actions workflow intentionally disables code signing.

1. Extract the ZIP and create a GitHub repository containing the project files at the repository root. Include the hidden `.github` directory.
2. In your GitHub repository, open **Actions**.
3. Select **Build unsigned AURA iPhone IPA** and press **Run workflow**.
4. After the macOS job succeeds, download **AURA_Local_Unsigned_IPA** from the run's **Artifacts** section.
5. Extract GitHub's outer artifact ZIP. You should find **AURA_Local_Unsigned.ipa** inside.
6. Sign the resulting IPA with your own Apple signing method. It cannot be installed unsigned.

The build uses `xcodebuild` with `CODE_SIGNING_ALLOWED=NO`, packages the compiled device `.app` under `Payload/`, and zips that directory as an IPA. This workflow **has not run on a macOS runner here**. If it fails, the Actions log will show the Xcode, Expo or CocoaPods error to fix.

You do not need to upload Ollama models, your `.env` file, or API credentials. The iPhone app is only a remote microphone/speaker client; your Windows PC runs all the local AI models.

For Windows, GitHub's standard macOS runners can be used without having a Mac locally. Standard runners are free for public GitHub repositories; private repositories have included usage allowances and possible overage charges. Don't enable paid overages if you need to stay at $0.

