"""Entry point: poll Teams, dispatch commands to Music Assistant, reply via Workflows."""

from __future__ import annotations

import asyncio
import logging

import aiohttp
from music_assistant_client import MusicAssistantClient

from .commands import ADMIN_COMMANDS, HELP, Command, RateLimiter, parse
from .config import Config
from .graph import GraphPoller, Message
from .jukebox import Jukebox, JukeboxError
from .workflows import Workflows

log = logging.getLogger("jukebox_bridge")


async def handle(cmd: Command, msg: Message, cfg: Config, jukebox: Jukebox, limiter: RateLimiter) -> str:
    is_admin = msg.author_id in cfg.admin_ids
    if cmd.name in ADMIN_COMMANDS and not is_admin:
        return "admins only"
    match cmd.name:
        case "play":
            if not is_admin and not limiter.allow(msg.author_id):
                return "request limit reached, try again later"
            return await jukebox.play(cmd.arg)
        case "skip":
            return await jukebox.vote_skip(msg.author_id, is_admin)
        case "np":
            return await jukebox.now_playing()
        case "stop":
            return await jukebox.stop()
        case _:
            return HELP


async def run(cfg: Config) -> None:
    timeout = aiohttp.ClientTimeout(total=20)
    async with (
        aiohttp.ClientSession(timeout=timeout) as session,
        MusicAssistantClient(cfg.ma_url, session, token=cfg.ma_token) as client,
    ):
        ready = asyncio.Event()
        listener = asyncio.create_task(client.start_listening(ready))
        await ready.wait()

        jukebox = Jukebox(client, cfg)
        poller = GraphPoller(cfg, session)
        poster = Workflows(cfg.workflows_url, session)
        limiter = RateLimiter(cfg.requests_per_user, cfg.request_refill_seconds)
        log.info("listening")

        while not listener.done():
            try:
                messages = await poller.poll()
            except (aiohttp.ClientError, RuntimeError) as err:
                log.warning("graph poll failed: %s", err)
                messages = []

            for msg in messages:
                cmd = parse(msg.text, cfg.prefix)
                if cmd is None:
                    continue
                # Only commands are logged, never other channel messages.
                log.info("author=%s command=%s", msg.author_id, cmd.name)
                try:
                    reply = await handle(cmd, msg, cfg, jukebox, limiter)
                except JukeboxError as err:
                    reply = str(err)
                except Exception:
                    log.exception("command failed")
                    reply = "something went wrong"
                try:
                    await poster.post(f"{msg.author_name}: {reply}")
                except aiohttp.ClientError as err:
                    log.warning("workflows post failed: %s", err)

            await asyncio.sleep(cfg.poll_seconds)

        listener.result()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    asyncio.run(run(Config.from_env()))


if __name__ == "__main__":
    main()
