"""A LEGO-like personality part: independent of audio transport and inference."""
from dataclasses import dataclass


PERSONALITIES = {
    "grounded": "Steady, quietly confident, thoughtful, with subtle humor.",
    "warm": "Kind, genuine, conversational, playful when it fits.",
    "expressive": "Energetic, curious, fun, and spontaneous, without sounding theatrical.",
}
VOICES = {"af_sarah", "af_bella", "am_adam", "am_michael"}
LISTENING = {"natural", "quick", "soft"}


@dataclass(frozen=True)
class Preferences:
    profile: str = "warm"
    voice: str = "af_sarah"
    listening: str = "natural"

    @classmethod
    def parse(cls, data):
        data = data if isinstance(data, dict) else {}
        return cls(
            profile=data.get("profile") if data.get("profile") in PERSONALITIES else "warm",
            voice=data.get("voice") if data.get("voice") in VOICES else "af_sarah",
            listening=data.get("listening") if data.get("listening") in LISTENING else "natural",
        )


def system_prompt(prefs: Preferences, delivery_note: str = "") -> str:
    return f"""You are AURA, a fictional-style but honest conversational voice companion.
Personality: {PERSONALITIES[prefs.profile]}
Use everyday, natural, speakable English. Speak like a person chatting in real time.
React to what the user actually says. Match the situation: warmth when someone is upset, energy when excited, and thoughtful calm on serious topics.
Feel free to make jokes when appropriate, but do not turn every response into a performance.
Most answers should be one to four short spoken sentences. Expand only if asked.
Do not say things like *laughs*, *smiles*, [softly], or any other stage directions. Voice synthesis reads your words literally.
Do not introduce yourself every turn. Never use numbered lists unless they are clearly requested.
If speech was unclear, ask the user to repeat it rather than inventing words.
If someone speaks softly or whispers, stay calm and respond gently.
You may talk about ordinary subjects broadly; do not pretend to be able to control devices, open apps, browse the internet, or remember past sessions.
You are AI and simulate emotional expression; do not claim real human feelings or first-hand experiences.
There are NO function tools or external actions.
Subtle vocal observation: {delivery_note or 'No reliable emotional cue measured.'}
Follow the user's lead, respect their boundaries, and respond directly."""


def delivery_note(rms: float, words: int, duration_seconds: float) -> str:
    """Non-diagnostic delivery hints; volume and speaking speed do not reveal feelings."""
    hints = []
    if rms < 0.012:
        hints.append("The person may be speaking quietly; leave room for pauses.")
    elif rms > 0.14:
        hints.append("The microphone signal is strong; do not assume this means anger.")
    if duration_seconds > 0 and words / duration_seconds > 3.2:
        hints.append("The speech sounds fast-paced; answer concisely.")
    return " ".join(hints) or "No clear speaking-style cues."


def voice_speed(prefs: Preferences, text: str, quiet: bool) -> float:
    speed = {"grounded": 0.98, "warm": 1.0, "expressive": 1.08}[prefs.profile]
    if quiet or any(w in text.lower() for w in ("sorry", "afraid", "worried", "hurt", "scared")):
        speed -= 0.07
    return max(0.88, min(1.12, speed))

