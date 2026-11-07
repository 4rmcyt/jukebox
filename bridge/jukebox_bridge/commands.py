"""Command parsing and per-user rate limiting."""

from __future__ import annotations

import time
from dataclasses import dataclass, field

COMMANDS = frozenset({"play", "skip", "np", "help", "stop"})
ADMIN_COMMANDS = frozenset({"stop"})
MAX_ARG_LENGTH = 200

HELP = "play <song or link> · skip (vote) · np (now playing) · help"


@dataclass(frozen=True)
class Command:
    name: str
    arg: str


def parse(text: str, prefix: str) -> Command | None:
    """Return a Command for messages addressed to the bot, None for everything else."""
    head, _, rest = text.strip().partition(" ")
    if head.lower() != prefix.lower():
        return None
    name, _, arg = rest.strip().partition(" ")
    name = name.lower()
    if name not in COMMANDS:
        return Command("help", "")
    return Command(name, arg.strip()[:MAX_ARG_LENGTH])


@dataclass
class RateLimiter:
    """Token bucket per user: `capacity` requests, one back every `refill_seconds`."""

    capacity: int
    refill_seconds: int
    _buckets: dict[str, tuple[float, float]] = field(default_factory=dict)

    def allow(self, user_id: str) -> bool:
        now = time.monotonic()
        tokens, last = self._buckets.get(user_id, (float(self.capacity), now))
        tokens = min(self.capacity, tokens + (now - last) / self.refill_seconds)
        if tokens < 1:
            self._buckets[user_id] = (tokens, now)
            return False
        self._buckets[user_id] = (tokens - 1, now)
        return True
