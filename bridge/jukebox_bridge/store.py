"""SQLite request/play log for reports. Times are stored as local day/hour for grouping."""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS requests (
    id INTEGER PRIMARY KEY,
    ts TEXT NOT NULL,
    day TEXT NOT NULL,
    hour INTEGER NOT NULL,
    author_id TEXT NOT NULL,
    author_name TEXT NOT NULL,
    command TEXT NOT NULL,
    query TEXT NOT NULL,
    reply TEXT NOT NULL,
    ok INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS plays (
    id INTEGER PRIMARY KEY,
    ts TEXT NOT NULL,
    day TEXT NOT NULL,
    hour INTEGER NOT NULL,
    track TEXT NOT NULL,
    artists TEXT NOT NULL,
    uri TEXT,
    duration INTEGER NOT NULL,
    source TEXT NOT NULL,
    author_id TEXT,
    author_name TEXT
);
CREATE TABLE IF NOT EXISTS optouts (
    author_id TEXT PRIMARY KEY,
    ts TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS requests_day ON requests(day);
CREATE INDEX IF NOT EXISTS plays_day ON plays(day);
"""


def _now() -> tuple[str, str, int]:
    now = datetime.now().astimezone()
    return now.isoformat(timespec="seconds"), now.date().isoformat(), now.hour


@dataclass(frozen=True)
class Summary:
    days: int
    plays: int
    seconds: int
    by_source: dict[str, int]
    requesters: int
    top_tracks: list[tuple[str, str, int]]
    top_requesters: list[tuple[str, int]]
    by_hour: dict[int, int]


class Store:
    def __init__(self, path: Path) -> None:
        self._db = sqlite3.connect(path)
        # Bridge writes while the weekly report reads from another process.
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.execute("PRAGMA busy_timeout=5000")
        self._db.executescript(SCHEMA)

    def add_request(
        self, author_id: str, author_name: str, command: str, query: str, reply: str, ok: bool
    ) -> None:
        ts, day, hour = _now()
        with self._db:
            self._db.execute(
                "INSERT INTO requests (ts, day, hour, author_id, author_name, command, query, reply, ok)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (ts, day, hour, author_id, author_name, command, query, reply, int(ok)),
            )

    def add_play(
        self,
        track: str,
        artists: str,
        uri: str | None,
        duration: int,
        source: str,
        author_id: str | None = None,
        author_name: str | None = None,
    ) -> None:
        ts, day, hour = _now()
        with self._db:
            self._db.execute(
                "INSERT INTO plays (ts, day, hour, track, artists, uri, duration, source, author_id, author_name)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (ts, day, hour, track, artists, uri, duration, source, author_id, author_name),
            )

    def set_optout(self, author_id: str, optout: bool) -> None:
        """Opted-out people are hidden from the public leaderboard; the IT log keeps them."""
        with self._db:
            if optout:
                self._db.execute(
                    "INSERT OR IGNORE INTO optouts (author_id, ts) VALUES (?, ?)", (author_id, _now()[0])
                )
            else:
                self._db.execute("DELETE FROM optouts WHERE author_id = ?", (author_id,))

    def prune(self, retention_days: int) -> None:
        cutoff = (date.today() - timedelta(days=retention_days)).isoformat()
        with self._db:
            self._db.execute("DELETE FROM requests WHERE day < ?", (cutoff,))
            self._db.execute("DELETE FROM plays WHERE day < ?", (cutoff,))

    def summary(self, days: int, public: bool = True) -> Summary:
        since = (date.today() - timedelta(days=days - 1)).isoformat()
        q = self._db.execute
        plays, seconds = q(
            "SELECT COUNT(*), COALESCE(SUM(duration), 0) FROM plays WHERE day >= ?", (since,)
        ).fetchone()
        by_source = dict(
            q("SELECT source, COUNT(*) FROM plays WHERE day >= ? GROUP BY source", (since,)).fetchall()
        )
        (requesters,) = q(
            "SELECT COUNT(DISTINCT author_id) FROM requests WHERE day >= ? AND command = 'play'", (since,)
        ).fetchone()
        top_tracks = q(
            "SELECT track, artists, COUNT(*) c FROM plays WHERE day >= ?"
            " GROUP BY track, artists ORDER BY c DESC LIMIT 10",
            (since,),
        ).fetchall()
        hide_optouts = " AND author_id NOT IN (SELECT author_id FROM optouts)" if public else ""
        top_requesters = q(
            "SELECT MAX(author_name), COUNT(*) c FROM requests"
            " WHERE day >= ? AND command = 'play' AND ok = 1" + hide_optouts +
            " GROUP BY author_id ORDER BY c DESC LIMIT 10",
            (since,),
        ).fetchall()
        by_hour = dict(
            q("SELECT hour, COUNT(*) FROM plays WHERE day >= ? GROUP BY hour", (since,)).fetchall()
        )
        return Summary(days, plays, seconds, by_source, requesters, top_tracks, top_requesters, by_hour)

    def recent_requests(self, days: int, limit: int = 200) -> list[tuple]:
        since = (date.today() - timedelta(days=days - 1)).isoformat()
        return self._db.execute(
            "SELECT ts, author_name, command, query, reply, ok FROM requests"
            " WHERE day >= ? ORDER BY id DESC LIMIT ?",
            (since, limit),
        ).fetchall()

    def recent_plays(self, days: int, limit: int = 200) -> list[tuple]:
        since = (date.today() - timedelta(days=days - 1)).isoformat()
        return self._db.execute(
            "SELECT ts, artists, track, source, COALESCE(author_name, '') FROM plays"
            " WHERE day >= ? ORDER BY id DESC LIMIT ?",
            (since, limit),
        ).fetchall()
