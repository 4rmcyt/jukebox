"""Music link verification: only single-track links from supported hosts become orders."""

from __future__ import annotations

import re
from urllib.parse import parse_qs, urlsplit

# Host as it appears in a link -> the allowedDomains entry that enables it.
HOSTS = {
    "music.youtube.com": "music.youtube.com",
    "youtube.com": "youtube.com",
    "www.youtube.com": "youtube.com",
    "m.youtube.com": "youtube.com",
    "youtu.be": "youtu.be",
}
VIDEO_ID = re.compile(r"[A-Za-z0-9_-]{11}")
URL_IN_TEXT = re.compile(r"https?://\S+")


class LinkError(Exception):
    """A supported music link that is not a single track; the message is the reply."""


def music_domain(url: str) -> str | None:
    """Return the allowedDomains entry for a music link, None for any other link."""
    parts = urlsplit(url)
    return HOSTS.get((parts.hostname or "").lower()) if parts.scheme in ("http", "https") else None


def to_uri(url: str, allowed: frozenset[str]) -> str | None:
    """Return the Music Assistant URI of a single-track link; None if it is not an allowed music link."""
    domain = music_domain(url)
    if domain is None or domain not in allowed:
        return None
    parts = urlsplit(url)
    if parts.scheme != "https" or parts.username or parts.password or parts.port:
        raise LinkError("only plain https links are accepted")
    if domain == "youtu.be":
        video_id = parts.path.strip("/")
    elif parts.path.rstrip("/") == "/watch":
        video_id = (parse_qs(parts.query).get("v") or [""])[0]
    else:
        raise LinkError("only links to a single track are accepted (no playlists or channels)")
    if not VIDEO_ID.fullmatch(video_id):
        raise LinkError("the link has no valid track id")
    return f"ytmusic://track/{video_id}"


def first_music_link(links: tuple[str, ...], allowed: frozenset[str]) -> str | None:
    """Return the first allowed music link of a message, ignoring every other link."""
    return next((url for url in links if (d := music_domain(url)) and d in allowed), None)
