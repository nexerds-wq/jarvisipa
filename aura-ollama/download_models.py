"""One-time free voice-model download from the Kokoro ONNX project's releases."""
from pathlib import Path
import os
import urllib.request

ROOT = Path(__file__).resolve().parent
MODELS = ROOT / "models"
BASE = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1"
FILES = ["kokoro-v1.0.int8.onnx", "voices-v1.0.bin"]


def download(filename):
    MODELS.mkdir(parents=True, exist_ok=True)
    target = MODELS / filename
    if target.exists() and target.stat().st_size > 1_000_000:
        print(f"Already present: {target.name}")
        return
    temporary = MODELS / (filename + ".partial")
    url = f"{BASE}/{filename}"
    print(f"Downloading free voice model: {filename}")
    try:
        with urllib.request.urlopen(url, timeout=60) as response, temporary.open("wb") as out:
            total = int(response.headers.get("Content-Length", "0"))
            current = 0
            while block := response.read(1024 * 1024):
                out.write(block)
                current += len(block)
                if total:
                    print(f"  {current * 100 // total}%", end="\r", flush=True)
        if temporary.stat().st_size < 1_000_000:
            raise RuntimeError("Download was unexpectedly small")
        os.replace(temporary, target)
        print(f"Saved: {target}")
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


if __name__ == "__main__":
    for name in FILES:
        download(name)
    print("Done. Whisper downloads its speech model automatically the first time you speak.")

