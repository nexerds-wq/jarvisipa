import unittest
from local_server.personality import Preferences, system_prompt, delivery_note, voice_speed
from local_server.phrases import PhraseBuffer


class PersonalityTests(unittest.TestCase):
    def test_invalid_choices_fall_back(self):
        self.assertEqual(Preferences.parse({"profile": "hacker", "voice": "fake"}), Preferences())

    def test_explicitly_no_tools(self):
        self.assertIn("NO function tools", system_prompt(Preferences()))

    def test_no_emotion_diagnosis_from_loud_voice(self):
        self.assertIn("do not assume", delivery_note(0.2, 4, 2))

    def test_quieter_response_speaks_more_slowly(self):
        prefs = Preferences(profile="expressive")
        self.assertLess(voice_speed(prefs, "Hello", True), voice_speed(prefs, "Hello", False))

    def test_phrase_buffer_streaming(self):
        buffer = PhraseBuffer(min_chars=10)
        self.assertEqual(buffer.add("Hello there, how "), ["Hello there,"])
        self.assertEqual(buffer.add("are you doing today?"), ["how are you doing today?"])
        self.assertEqual(buffer.finish(), [])


if __name__ == "__main__":
    unittest.main()

