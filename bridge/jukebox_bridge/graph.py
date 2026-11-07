"""Polls the jukebox channel via Microsoft Graph (app-only, RSC ChannelMessage.Read.Group)."""

from __future__ import annotations

import asyncio
import logging
from collections import deque
from dataclasses import dataclass
from datetime import UTC, datetime
from html import unescape
from html.parser import HTMLParser

import aiohttp
import msal

from .config import Config

GRAPH = "https://graph.microsoft.com/v1.0"
SCOPE = "https://graph.microsoft.com/.default"

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class Message:
    id: str
    author_id: str
    author_name: str
    text: str


class _TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


def html_to_text(content: str) -> str:
    parser = _TextExtractor()
    parser.feed(content)
    return unescape(" ".join("".join(parser.parts).split()))


class GraphPoller:
    def __init__(self, cfg: Config, session: aiohttp.ClientSession) -> None:
        self._session = session
        self._app = msal.ConfidentialClientApplication(
            cfg.client_id,
            authority=f"https://login.microsoftonline.com/{cfg.tenant_id}",
            client_credential={"private_key": cfg.graph_key, "thumbprint": cfg.graph_thumbprint},
        )
        self._url = f"{GRAPH}/teams/{cfg.team_id}/channels/{cfg.channel_id}/messages?$top=20"
        # Ignore history on start: only messages posted while the bridge runs are commands.
        self._started = datetime.now(UTC)
        self._seen: deque[str] = deque(maxlen=500)

    async def _token(self) -> str:
        # msal caches the token in memory and refreshes it when it expires.
        result = await asyncio.to_thread(self._app.acquire_token_for_client, scopes=[SCOPE])
        if "access_token" not in result:
            raise RuntimeError(result.get("error_description", "token request failed"))
        return result["access_token"]

    async def poll(self) -> list[Message]:
        headers = {"Authorization": f"Bearer {await self._token()}"}
        async with self._session.get(self._url, headers=headers) as resp:
            if resp.status == 429:
                delay = int(resp.headers.get("Retry-After", "10"))
                log.warning("graph throttled, sleeping %ss", delay)
                await asyncio.sleep(delay)
                return []
            resp.raise_for_status()
            data = await resp.json()

        messages: list[tuple[datetime, Message]] = []
        for item in data.get("value", []):
            created = datetime.fromisoformat(item["createdDateTime"])
            if created < self._started or item["id"] in self._seen:
                continue
            self._seen.append(item["id"])
            if item.get("messageType") != "message" or item.get("deletedDateTime"):
                continue
            # Applications (incl. our own Workflows posts) carry from.application, not from.user.
            user = (item.get("from") or {}).get("user")
            if not user:
                continue
            text = html_to_text(item["body"]["content"])
            messages.append(
                (created, Message(item["id"], user["id"], user.get("displayName", ""), text))
            )
        return [m for _, m in sorted(messages, key=lambda pair: pair[0])]
