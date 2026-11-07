"""Music Assistant side: search, enqueue, vote-skip, now playing."""

from __future__ import annotations

from urllib.parse import urlparse

from music_assistant_client import MusicAssistantClient
from music_assistant_models.enums import MediaType, QueueOption

from .config import Config


class JukeboxError(Exception):
    """User-facing error; the message is posted back to the channel."""


class Jukebox:
    def __init__(self, client: MusicAssistantClient, cfg: Config) -> None:
        self._client = client
        self._cfg = cfg
        self._skip_votes: dict[str, set[str]] = {}

    def _queue_id(self) -> str:
        for queue in self._client.player_queues:
            if queue.display_name == self._cfg.ma_player:
                return queue.queue_id
        raise JukeboxError("the speaker is offline (outside work hours?)")

    def _check_url(self, url: str) -> None:
        host = (urlparse(url).hostname or "").lower()
        if not any(host == d or host.endswith(f".{d}") for d in self._cfg.allowed_domains):
            raise JukeboxError("links are accepted only from: " + ", ".join(self._cfg.allowed_domains))

    async def play(self, query: str) -> str:
        if not query:
            raise JukeboxError("usage: play <song or link>")
        queue_id = self._queue_id()
        if query.startswith(("http://", "https://")):
            self._check_url(query)
            # TODO: verify MA resolves YT Music URLs to tracks; duration is not checked for links.
            await self._client.player_queues.play_media(queue_id, query, option=QueueOption.ADD)
            return "added link to the queue"

        results = await self._client.music.search(query, [MediaType.TRACK], limit=1)
        if not results.tracks:
            raise JukeboxError(f"nothing found for “{query}”")
        track = results.tracks[0]
        # Results may be ItemMapping (no duration/artists) as well as full Track objects.
        duration = getattr(track, "duration", 0) or 0
        if duration > self._cfg.max_track_seconds:
            raise JukeboxError(f"“{track.name}” is longer than {self._cfg.max_track_seconds // 60} min")
        await self._client.player_queues.play_media(queue_id, track, option=QueueOption.ADD)
        artists = ", ".join(a.name for a in getattr(track, "artists", []))
        return f"queued {artists} — {track.name}" if artists else f"queued {track.name}"

    async def vote_skip(self, user_id: str, is_admin: bool) -> str:
        queue_id = self._queue_id()
        current = self._client.player_queues.get(queue_id).current_item
        if current is None:
            raise JukeboxError("nothing is playing")
        votes = self._skip_votes.setdefault(current.queue_item_id, set())
        votes.add(user_id)
        if is_admin or len(votes) >= self._cfg.skip_votes:
            self._skip_votes.clear()
            await self._client.player_queues.next(queue_id)
            return f"skipped {current.name}"
        return f"skip vote {len(votes)}/{self._cfg.skip_votes} for {current.name}"

    async def now_playing(self) -> str:
        current = self._client.player_queues.get(self._queue_id()).current_item
        return f"now playing: {current.name}" if current else "nothing is playing"

    async def stop(self) -> str:
        await self._client.player_queues.stop(self._queue_id())
        return "stopped"
