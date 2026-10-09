# Follow iPhone mode

1. Install Python and the official Cozmo SDK dependencies on a computer: `pip install cozmo opencv-python numpy pillow`.
2. Connect Cozmo using the official Cozmo app in SDK mode, with the phone/device tethered to the computer as required by the SDK.
3. Open `phone_target.html` on the iPhone you want Cozmo to follow. Increase brightness.
4. Run `python follow_phone.py` on the computer.
5. Hold the phone screen toward Cozmo while walking slowly.

**Important:** This is an experimental visual tracker, not Bluetooth/GPS tracking. Cozmo must see the phone screen. The magenta color may be confused with other objects. Cozmo has no reliable obstacle or stair avoidance in this program. Test on a clear floor with close supervision. Press Ctrl+C to stop.

A single iPhone generally cannot both display the target in a normal browser and run the official Cozmo SDK app in SDK mode simultaneously. A second iOS/Android device for Cozmo SDK connectivity may be required. The phone target can also be displayed on another screen. This is not a standalone IPA.
