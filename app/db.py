import json
from urllib.parse import urlparse, urlunparse

import asyncpg

from app.config import get_settings

pool: asyncpg.Pool | None = None


async def connect() -> None:
    global pool

    async def init(connection: asyncpg.Connection) -> None:
        await connection.set_type_codec(
            "jsonb", encoder=json.dumps, decoder=json.loads, schema="pg_catalog"
        )

    database_url = get_settings().resolved_database_url().replace("postgres://", "postgresql://", 1)
    parsed = urlparse(database_url)
    normalized_url = urlunparse(parsed._replace(scheme="postgresql", query=""))
    local_host = parsed.hostname in {"localhost", "127.0.0.1", "::1"}
    ssl = None if local_host else "require"

    pool = await asyncpg.create_pool(
        normalized_url,
        min_size=1,
        max_size=10,
        init=init,
        ssl=ssl,
        statement_cache_size=0,
    )


async def disconnect() -> None:
    global pool
    if pool is not None:
        await pool.close()
        pool = None


def get_pool() -> asyncpg.Pool:
    if pool is None:
        raise RuntimeError("Database pool is not initialized")
    return pool
