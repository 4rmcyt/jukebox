"""Report rendering: channel text (Teams/!dj stats) and the admin stats page."""

from __future__ import annotations

from html import escape

from .store import Store, Summary

SOURCES = ("teams", "party", "other")


def _duration(seconds: int) -> str:
    hours, rest = divmod(seconds, 3600)
    return f"{hours}h {rest // 60}m"


def format_summary(s: Summary) -> str:
    sources = " · ".join(f"{name} {s.by_source.get(name, 0)}" for name in SOURCES)
    lines = [
        f"**Jukebox — last {s.days} days**",
        f"Plays: {s.plays} ({_duration(s.seconds)}) — {sources}",
        f"Requesters (Teams): {s.requesters}",
    ]
    if s.top_tracks:
        lines.append("**Top tracks**")
        lines += [f"{i}. {a} — {t} ({c})" if a else f"{i}. {t} ({c})"
                  for i, (t, a, c) in enumerate(s.top_tracks, 1)]
    if s.top_requesters:
        lines.append("**Top DJs**")
        lines += [f"{i}. {name} ({c})" for i, (name, c) in enumerate(s.top_requesters, 1)]
    if s.by_hour:
        hour, count = max(s.by_hour.items(), key=lambda kv: kv[1])
        lines.append(f"Busiest hour: {hour:02d}:00 ({count} plays)")
    return "\n\n".join(lines)


def _table(headers: tuple[str, ...], rows: list[tuple]) -> str:
    head = "".join(f"<th>{escape(h)}</th>" for h in headers)
    body = "".join(
        "<tr>" + "".join(f"<td>{escape(str(v))}</td>" for v in row) + "</tr>" for row in rows
    )
    return f"<table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table>"


def render_page(store: Store, days: int) -> str:
    # IT page: the leaderboard includes people who opted out of the public one.
    s = store.summary(days, public=False)
    hours = [(f"{h:02d}:00", c) for h, c in sorted(s.by_hour.items())]
    requests = [(ts, who, cmd, query, reply, "yes" if ok else "no")
                for ts, who, cmd, query, reply, ok in store.recent_requests(days)]
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Jukebox stats</title>
<style>
body{{font:14px system-ui,sans-serif;margin:1.5rem;max-width:72rem}}
table{{border-collapse:collapse;margin:.5rem 0 1.5rem;width:100%}}
th,td{{border-bottom:1px solid #ddd;padding:.3rem .5rem;text-align:left}}
th{{background:#f4f4f4}}
.summary{{white-space:pre-line}}
</style></head><body>
<h1>Jukebox — last {s.days} days</h1>
<p class="summary">{escape(format_summary(s).replace("**", "").replace(chr(10) * 2, chr(10)))}</p>
<p><a href="?days=1">1 day</a> · <a href="?days=7">7 days</a> · <a href="?days=30">30 days</a> · <a href="?days=90">90 days</a></p>
<h2>Top tracks</h2>{_table(("Track", "Artists", "Plays"), s.top_tracks)}
<h2>Top DJs</h2>{_table(("Name", "Requests"), s.top_requesters)}
<h2>Plays by hour</h2>{_table(("Hour", "Plays"), hours)}
<h2>Requests (Teams)</h2>{_table(("Time", "Who", "Command", "Query", "Reply", "OK"), requests)}
<h2>Plays</h2>{_table(("Time", "Artists", "Track", "Source", "Requested by"), store.recent_plays(days))}
</body></html>"""
