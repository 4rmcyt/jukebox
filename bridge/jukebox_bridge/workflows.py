"""Posts replies to the channel through a Teams Workflows webhook."""

from __future__ import annotations

import aiohttp


class Workflows:
    def __init__(self, url: str, session: aiohttp.ClientSession) -> None:
        self._url = url
        self._session = session

    async def post(self, text: str) -> None:
        payload = {
            "type": "message",
            "attachments": [
                {
                    "contentType": "application/vnd.microsoft.card.adaptive",
                    "content": {
                        "type": "AdaptiveCard",
                        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                        "version": "1.4",
                        "body": [{"type": "TextBlock", "text": text, "wrap": True}],
                    },
                }
            ],
        }
        async with self._session.post(self._url, json=payload) as resp:
            resp.raise_for_status()
