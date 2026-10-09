# Cozmo JARVIS integration

This branch is a starting point for connecting the JARVIS iOS app to an Ollama service and the Cozmo SDK.

The official Cozmo SDK requires the Cozmo app running in SDK mode on a phone tethered to a computer. An IPA cannot replace that connection without implementing an alternative protocol.

Planned components: iOS voice command UI, local Ollama bridge, Cozmo SDK motor adapter, camera-based visual tracking of a marker displayed on the iPhone, and emergency stop. Phone-following must stop if tracking is lost.

Do not assume direct iPhone-to-Cozmo support or unattended background wake-word recognition.