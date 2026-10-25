"""Start AURA on the computer after installing Ollama, Python, and free models."""
import uvicorn
from local_server.settings import Settings


if __name__ == "__main__":
    settings = Settings.from_env()
    print(f"AURA Local Voice on http://127.0.0.1:{settings.port}")
    print("No paid API. Keep port 8787 on your trusted private network only.")
    uvicorn.run("local_server.app:app_factory", factory=True, host=settings.host,
                port=settings.port, log_level="info")

