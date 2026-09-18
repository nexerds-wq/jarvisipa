# Jarvis Glasses V2 — Background “Hey Jarvis”

This is the upgraded version of the working M02S Jarvis app.

## What changed

- Detects the phrase **“Hey Jarvis”** inside the app.
- Keeps the microphone session active with the iOS `audio` background mode.
- Keeps the M02S BLE connection/restoration active with `bluetooth-central` background mode.
- Prefers a Bluetooth HFP microphone (the glasses mic) when iOS exposes one.
- Falls back to the iPhone microphone if the glasses do not expose an HFP input.
- Automatically reconnects to the saved glasses.
- Sends the already-confirmed M02S wake packet when “Hey Jarvis” is detected.
- Still includes the **Wake Jarvis** App Intent, so iOS Vocal Shortcuts can be used as a second fallback.

## Why the phone handles “Hey Jarvis”

The HeyCyan iOS SDK files you provided show that the glasses have an onboard wake-word switch, but the documented onboard phrase is **“Hey Cyan.”** The SDK exposes enable/disable for that detector, not a way to replace its model with “Hey Jarvis.”

The same SDK research also confirms the glasses microphone can appear to iOS as a normal Bluetooth HFP input. V2 uses that route when it is available and performs the custom “Hey Jarvis” detection on the iPhone.

## Build the IPA on GitHub

1. Create a new GitHub repository.
2. Upload **everything inside this folder**, including `.github`.
3. Open the repository's **Actions** tab.
4. Run **Build Jarvis Glasses V2 IPA**.
5. Open the finished workflow.
6. Download the artifact named `JarvisGlasses-V2-unsigned-ipa`.
7. Extract it. Inside is `JarvisGlasses-V2-unsigned.ipa`.
8. Install that IPA with Sideloadly.

## First setup

1. Open **Jarvis Glasses**.
2. Allow Bluetooth.
3. Tap **Scan**.
4. Select the M02S.
5. Wait until it says **M02S ready ✓**.
6. Tap **Test Jarvis** and make sure the glasses enter the same AI/listening mode as before.
7. Turn on **Listen for Hey Jarvis**.
8. Allow **Microphone** and **Speech Recognition**.
9. Look at **Microphone** in the app. If the glasses expose HFP, the glasses/Bluetooth route should appear there.
10. Say **Hey Jarvis**. The app should immediately send the BLE wake command.

## Background / locked test

1. Keep **Listen for Hey Jarvis** turned on.
2. Leave the app normally. Do **not** swipe-force-close it.
3. Lock the iPhone.
4. Wait a few seconds.
5. Say **Hey Jarvis**.
6. Check whether the M02S goes into AI/listening mode.

The project requests both `audio` and `bluetooth-central` iOS background modes. That gives the app the correct mechanisms to continue listening and keep BLE alive while backgrounded/locked. iOS still controls process lifetime, so a force-close, reboot, permission change, or system resource pressure can stop it. Reopening the app restarts the services.

## Most reliable fallback if iOS suspends the listener

The app still exposes an App Intent named **Wake Jarvis**.

On the iPhone:

`Settings > Accessibility > Vocal Shortcuts > Add Action > Wake Jarvis`

Train the phrase:

`Hey Jarvis`

That lets the iPhone's own system-level Vocal Shortcuts detector trigger the same BLE wake action.

## BLE values used

- Service: `DE5BF728-D711-4E47-AF26-65E3012A5DC7`
- Write characteristic: `DE5BF72A-D711-4E47-AF26-65E3012A5DC7`
- Write type: without response
- Wake packet: `BC4103009052020107`

## Sideloading

With normal free Apple-ID signing, the app usually needs to be resigned periodically. Sideloadly can be used again when the signature expires.
