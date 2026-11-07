"""Configuration: plain settings from env, secrets from systemd credentials."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _credential(name: str) -> str:
    return (Path(os.environ["CREDENTIALS_DIRECTORY"]) / name).read_text().strip()


def db_path() -> Path:
    return Path(os.environ["STATE_DIRECTORY"]) / "jukebox.db"


def workflows_url() -> str:
    return _credential("workflows-url")


def retention_days() -> int:
    return int(_env("RETENTION_DAYS", "90"))


def _env(name: str, default: str | None = None) -> str:
    value = os.environ.get(f"JUKEBOX_{name}", default)
    if value is None:
        raise KeyError(f"JUKEBOX_{name} is not set")
    return value


def _env_list(name: str) -> tuple[str, ...]:
    return tuple(v.strip() for v in _env(name, "").split(",") if v.strip())


@dataclass(frozen=True)
class Config:
    tenant_id: str
    client_id: str
    team_id: str
    channel_id: str
    graph_key: str
    graph_thumbprint: str
    ma_url: str
    ma_token: str
    ma_player: str
    workflows_url: str
    prefix: str
    admin_ids: frozenset[str]
    allowed_domains: tuple[str, ...]
    poll_seconds: float
    max_track_seconds: int
    skip_votes: int
    requests_per_user: int
    request_refill_seconds: int
    db_path: Path
    stats_port: int
    retention_days: int

    @classmethod
    def from_env(cls) -> Config:
        return cls(
            tenant_id=_env("TENANT_ID"),
            client_id=_env("CLIENT_ID"),
            team_id=_env("TEAM_ID"),
            channel_id=_env("CHANNEL_ID"),
            graph_key=_credential("graph-key"),
            graph_thumbprint=_credential("graph-thumbprint"),
            ma_url=_env("MA_URL", "http://127.0.0.1:8095"),
            ma_token=_credential("ma-token"),
            ma_player=_env("MA_PLAYER", "Jukebox"),
            workflows_url=workflows_url(),
            prefix=_env("PREFIX", "!dj"),
            admin_ids=frozenset(_env_list("ADMIN_IDS")),
            allowed_domains=_env_list("ALLOWED_DOMAINS"),
            poll_seconds=float(_env("POLL_SECONDS", "3")),
            max_track_seconds=int(_env("MAX_TRACK_SECONDS", "480")),
            skip_votes=int(_env("SKIP_VOTES", "3")),
            requests_per_user=int(_env("REQUESTS_PER_USER", "3")),
            request_refill_seconds=int(_env("REQUEST_REFILL_SECONDS", "600")),
            db_path=db_path(),
            stats_port=int(_env("STATS_PORT", "8096")),
            retention_days=retention_days(),
        )
