# User Management API

FastAPI service for PostgreSQL-native identity, ReBAC authorization, configuration, metering, and job queues. Business mutations live in SQL functions under `sql/001_user_management.sql`.

## Start PostgreSQL

```bash
docker compose up -d postgres
```

The SQL file initializes the database on first container startup. Docker is optional if you already run PostgreSQL; create the database and apply the migration with:

```bash
psql "$DATABASE_URL" -f sql/001_user_management.sql
```

## Run the API

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
cp .env.example .env
uvicorn app.main:app --reload
```

API docs: `http://127.0.0.1:8000/docs`

## Deploy on Vercel

Set these environment variables in the Vercel project:

- `DATABASE_URL`: PostgreSQL connection string reachable from Vercel, including SSL-compatible credentials.
- `JWT_SECRET`: a random value of at least 32 characters.
- `COOKIE_SECURE=true` for production HTTPS deployments.
- `CORS_ORIGINS`: a JSON array of allowed origins, for example `["https://example.com"]`.

Apply [sql/001_user_management.sql](sql/001_user_management.sql) to the hosted PostgreSQL database before testing the API. Vercel loads the application from the `app.main:app` entrypoint configured in `pyproject.toml`.

## Main endpoints

- `POST /api/auth/signup`
- `POST /api/auth/login`
- `POST /api/auth/logout`
- `POST /api/auth/reset-password`
- `GET /api/permissions/check`
- `POST /api/permissions/grant`
- `GET|PUT /api/config`
- `GET /api/meter/usage`
- `POST /api/meter/reserve`
- `POST /api/jobs`
- `GET /api/jobs/status`

Sessions are opaque tokens stored only as SHA-256 hashes in PostgreSQL and returned through an HttpOnly cookie. Passwords are bcrypt-hashed by PostgreSQL functions.
