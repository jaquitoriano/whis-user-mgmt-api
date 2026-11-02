import json

import asyncpg

from app.config import get_settings

pool: asyncpg.Pool | None = None


async def connect() -> None:
    global pool

    async def init(connection: asyncpg.Connection) -> None:
        await connection.set_type_codec(
            "jsonb", encoder=json.dumps, decoder=json.loads, schema="pg_catalog"
        )

    pool = await asyncpg.create_pool(
        get_settings().database_url, min_size=1, max_size=10, init=init
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
