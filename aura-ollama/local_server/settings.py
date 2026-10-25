"""Configuration stays on the user's computer, never in the phone app."""
from dataclasses import dataclass
from pathlib import Path
import os

ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class Settings:
    pairing_code: str
    host: str = "0.0.0.0"
    port: int = 8787
    ollama_url: str = "http://127.0.0.1:11434"
    ollama_model: str = "qwen3:1.7b"
    whisper_model: str = "base"
    whisper_device: str = "cpu"
    whisper_compute_type: str = "int8"
    kokoro_model_path: str = str(ROOT / "models" / "kokoro-v1.0.int8.onnx")
    kokoro_voices_path: str = str(ROOT / "models" / "voices-v1.0.bin")

    @classmethod
    def from_env(cls):
        from dotenv import load_dotenv
        load_dotenv(ROOT / ".env")
        def path(name, default):
            raw = Path(os.getenv(name, default))
            return str(raw if raw.is_absolute() else ROOT / raw)

        code = os.getenv("PAIRING_CODE", "")
        if len(code) < 12 or code == "change-this-to-a-long-random-secret":
            raise ValueError("Set a unique PAIRING_CODE of at least 12 characters in .env")
        return cls(
            pairing_code=code,
            host=os.getenv("HOST", "0.0.0.0"),
            port=int(os.getenv("PORT", "8787")),
            ollama_url=os.getenv("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/"),
            ollama_model=os.getenv("OLLAMA_MODEL", "qwen3:1.7b"),
            whisper_model=os.getenv("WHISPER_MODEL", "base"),
            whisper_device=os.getenv("WHISPER_DEVICE", "cpu"),
            whisper_compute_type=os.getenv("WHISPER_COMPUTE_TYPE", "int8"),
            kokoro_model_path=path("KOKORO_MODEL_PATH", "models/kokoro-v1.0.int8.onnx"),
            kokoro_voices_path=path("KOKORO_VOICES_PATH", "models/voices-v1.0.bin"),
        )

