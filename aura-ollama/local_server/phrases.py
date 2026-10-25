"""Turn streamed language-model tokens into natural phrase-sized speech units."""
import re


class PhraseBuffer:
    def __init__(self, min_chars=28, max_chars=130):
        self.pending = ""
        self.min_chars = min_chars
        self.max_chars = max_chars

    def add(self, token):
        self.pending += token
        ready = []
        while True:
            end = self._boundary()
            if end is None:
                break
            ready.append(self.pending[:end].strip())
            self.pending = self.pending[end:].lstrip()
        return [value for value in ready if value]

    def finish(self):
        tail = self.pending.strip()
        self.pending = ""
        return [tail] if tail else []

    def _boundary(self):
        if len(self.pending) < self.min_chars:
            return None
        # Speak at natural sentence / clause breaks. Do not voice one token at a time.
        m = re.search(r"[.!?](?:\s|$)|[,;:](?:\s)", self.pending)
        if m:
            return m.end()
        if len(self.pending) >= self.max_chars:
            split = self.pending.rfind(" ", 0, self.max_chars)
            return (split + 1) if split >= self.min_chars else self.max_chars
        return None

