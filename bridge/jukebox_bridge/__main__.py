"""Entry point: poll Teams, dispatch commands to Music Assistant, reply via Workflows.

`jukebox-bridge report` posts the weekly summary to the channel and exits.
"""

from __future__ import annotations

import asyncio
import logging
import sys

import aiohttp
from aiohttp import web
from music_assistant_client import MusicAssistantClient
from music_assistant_models.enums import EventType

from . import config
from .commands import ADMIN_COMMANDS, HELP, Command, RateLimiter, parse
from .config import Config
from .graph import GraphPoller, Message
from .jukebox import Jukebox, JukeboxError
from .links import first_music_link
from .report import format_summary, render_page
from .store import Store
from .tracker import PlayTracker
from .workflows import Workflows

log = logging.getLogger("jukebox_bridge")

STATS_DAYS = 7
PRUNE_EVERY_POLLS = 1200


async def handle(
    cmd: Command, msg: Message, cfg: Config, jukebox: Jukebox, limiter: RateLimiter, store: Store
) -> str:
    is_admin = msg.author_id in cfg.admin_ids
    if cmd.name in ADMIN_COMMANDS and not is_admin:
        raise JukeboxError("admins only")
    match cmd.name:
        case "play":
            if not is_admin and not limiter.allow(msg.author_id):
                raise JukeboxError("request limit reached, try again later")
            # Teams sends links as anchors; the href beats the visible text.
            query = first_music_link(msg.links, cfg.allowed_domains) or cmd.arg
            return await jukebox.play(query, msg.author_id, msg.author_name)
        case "skip":
            return await jukebox.vote_skip(msg.author_id, is_admin)
        case "np":
            return await jukebox.now_playing()
        case "stats" if cmd.arg.lower() in ("optout", "optin"):
            store.set_optout(msg.author_id, cmd.arg.lower() == "optout")
            if cmd.arg.lower() == "optout":
                return "you are hidden from the public top DJs (IT still keeps the request log)"
            return "you are back in the public top DJs"
        case "stats":
            return format_summary(store.summary(STATS_DAYS))
        case "stop":
            return await jukebox.stop()
        case _:
            return HELP


async def start_stats_page(store: Store, port: int) -> web.AppRunner:
    async def stats(request: web.Request) -> web.Response:
        try:
            days = min(max(int(request.query.get("days", STATS_DAYS)), 1), 365)
        except ValueError:
            days = STATS_DAYS
        return web.Response(text=render_page(store, days), content_type="text/html")

    app = web.Application()
    app.router.add_get("/stats", stats)
    runner = web.AppRunner(app)
    await runner.setup()
    # Loopback only; Caddy exposes /stats to the admin nets.
    await web.TCPSite(runner, "127.0.0.1", port).start()
    return runner


async def run(cfg: Config) -> None:
    store = Store(cfg.db_path)
    store.prune(cfg.retention_days)
    timeout = aiohttp.ClientTimeout(total=20)
    async with (
        aiohttp.ClientSession(timeout=timeout) as session,
        MusicAssistantClient(cfg.ma_url, session, token=cfg.ma_token) as client,
    ):
        ready = asyncio.Event()
        listener = asyncio.create_task(client.start_listening(ready))
        await ready.wait()

        tracker = PlayTracker(client, store, cfg.ma_player)
        client.subscribe(tracker.on_queue_event, EventType.QUEUE_UPDATED)
        jukebox = Jukebox(client, cfg, tracker)
        poller = GraphPoller(cfg, session)
        poster = Workflows(cfg.workflows_url, session)
        limiter = RateLimiter(cfg.requests_per_user, cfg.request_refill_seconds)
        runner = await start_stats_page(store, cfg.stats_port)
        log.info("listening")

        polls = 0
        try:
            while not listener.done():
                try:
                    messages = await poller.poll()
                except (aiohttp.ClientError, RuntimeError) as err:
                    log.warning("graph poll failed: %s", err)
                    messages = []

                for msg in messages:
                    cmd = parse(msg.text, cfg.prefix)
                    if cmd is None:
                        # A bare music link is an order; any other chatter is ignored.
                        link = first_music_link(msg.links, cfg.allowed_domains)
                        if link is None:
                            continue
                        cmd = Command("play", link)
                    log.info("author=%s command=%s", msg.author_id, cmd.name)
                    ok = True
                    try:
                        reply = await handle(cmd, msg, cfg, jukebox, limiter, store)
                    except JukeboxError as err:
                        reply, ok = str(err), False
                    except Exception:
                        log.exception("command failed")
                        reply, ok = "something went wrong", False
                    store.add_request(msg.author_id, msg.author_name, cmd.name, cmd.arg, reply, ok)
                    try:
                        await poster.post(f"{msg.author_name}: {reply}")
                    except aiohttp.ClientError as err:
                        log.warning("workflows post failed: %s", err)

                polls += 1
                if polls % PRUNE_EVERY_POLLS == 0:
                    store.prune(cfg.retention_days)
                await asyncio.sleep(cfg.poll_seconds)
        finally:
            await runner.cleanup()

        listener.result()


async def weekly_report() -> None:
    store = Store(config.db_path())
    store.prune(config.retention_days())
    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=20)) as session:
        await Workflows(config.workflows_url(), session).post(format_summary(store.summary(STATS_DAYS)))


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    if sys.argv[1:] == ["report"]:
        asyncio.run(weekly_report())
    else:
        asyncio.run(run(Config.from_env()))


if __name__ == "__main__":
    main()
