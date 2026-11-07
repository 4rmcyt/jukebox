"""Music Assistant side: search, enqueue, vote-skip, now playing."""

from __future__ import annotations

from music_assistant_client import MusicAssistantClient
from music_assistant_models.enums import MediaType, QueueOption
from music_assistant_models.errors import MusicAssistantError
from music_assistant_models.media_items import Track

from .config import Config
from .links import LinkError, to_uri
from .tracker import PlayTracker


class JukeboxError(Exception):
    """User-facing error; the message is posted back to the channel."""


class Jukebox:
    def __init__(self, client: MusicAssistantClient, cfg: Config, tracker: PlayTracker) -> None:
        self._client = client
        self._cfg = cfg
        self._tracker = tracker
        self._skip_votes: dict[str, set[str]] = {}

    def _queue_id(self) -> str:
        for queue in self._client.player_queues:
            if queue.display_name == self._cfg.ma_player:
                return queue.queue_id
        raise JukeboxError("the speaker is offline (outside work hours?)")

    async def _resolve_link(self, url: str) -> Track:
        try:
            uri = to_uri(url, self._cfg.allowed_domains)
        except LinkError as err:
            raise JukeboxError(str(err)) from err
        if uri is None:
            raise JukeboxError("links are accepted only from: " + ", ".join(sorted(self._cfg.allowed_domains)))
        try:
            item = await self._client.music.get_item_by_uri(uri)
        except MusicAssistantError as err:
            raise JukeboxError("track not found") from err
        if not isinstance(item, Track) or not any(m.available for m in item.provider_mappings):
            raise JukeboxError("this track is not available")
        return item

    async def play(self, query: str, author_id: str, author_name: str) -> str:
        if not query:
            raise JukeboxError("usage: play <song or link>")
        queue_id = self._queue_id()
        if query.startswith(("http://", "https://")):
            track = await self._resolve_link(query)
        else:
            results = await self._client.music.search(query, [MediaType.TRACK], limit=1)
            if not results.tracks:
                raise JukeboxError(f"nothing found for “{query}”")
            track = results.tracks[0]
        # Results may be ItemMapping (no duration/artists) as well as full Track objects.
        duration = getattr(track, "duration", 0) or 0
        if duration > self._cfg.max_track_seconds:
            raise JukeboxError(f"“{track.name}” is longer than {self._cfg.max_track_seconds // 60} min")
        self._tracker.expect(track.uri, author_id, author_name)
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
