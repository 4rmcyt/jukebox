"""Records every track that starts playing on the jukebox queue, with its source."""

from __future__ import annotations

from collections import OrderedDict

from music_assistant_client import MusicAssistantClient
from music_assistant_models.event import MassEvent

from .store import Store

# Set by the Party plugin on guest-requested queue items (providers/party: ATTR_PARTY_GUEST).
PARTY_GUEST = "party_guest"
MAX_PENDING = 200


class PlayTracker:
    def __init__(self, client: MusicAssistantClient, store: Store, player: str) -> None:
        self._client = client
        self._store = store
        self._player = player
        self._last_item: str | None = None
        # uri -> (author_id, author_name) for tracks queued from Teams, matched when they start.
        self._pending: OrderedDict[str, tuple[str, str]] = OrderedDict()

    def expect(self, uri: str, author_id: str, author_name: str) -> None:
        self._pending[uri] = (author_id, author_name)
        while len(self._pending) > MAX_PENDING:
            self._pending.popitem(last=False)

    def on_queue_event(self, event: MassEvent) -> None:
        queue = self._client.player_queues.get(event.object_id or "")
        if queue is None or queue.display_name != self._player:
            return
        item = queue.current_item
        if item is None or item.queue_item_id == self._last_item:
            return
        self._last_item = item.queue_item_id

        media = item.media_item
        uri = getattr(media, "uri", None)
        artists = ", ".join(a.name for a in getattr(media, "artists", []))
        track = getattr(media, "name", None) or item.name
        author = self._pending.pop(uri, None) if uri else None
        if author:
            source = "teams"
        elif item.extra_attributes.get(PARTY_GUEST):
            source = "party"
        else:
            source = "other"
        self._store.add_play(
            track, artists, uri, item.duration or 0, source, *(author or (None, None))
        )
