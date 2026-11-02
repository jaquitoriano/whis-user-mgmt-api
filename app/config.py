from functools import lru_cache
from urllib.parse import quote

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", populate_by_name=True)

    database_url: str | None = Field(
        default=None,
        validation_alias=AliasChoices(
            "DATABASE_URL",
            "POSTGRES_URL",
            "POSTGRES_PRISMA_URL",
            "POSTGRES_URL_NON_POOLING",
        ),
    )
    postgres_host: str | None = Field(default=None, validation_alias="POSTGRES_HOST")
    postgres_database: str | None = Field(default=None, validation_alias="POSTGRES_DATABASE")
    postgres_user: str | None = Field(default=None, validation_alias="POSTGRES_USER")
    postgres_password: str | None = Field(default=None, validation_alias="POSTGRES_PASSWORD")
    postgres_port: int = 5432
    jwt_secret: str = "development-only-secret-change-me"
    cookie_secure: bool = False
    cors_origins: list[str] = ["http://localhost:3000"]

    def resolved_database_url(self) -> str:
        if self.database_url:
            return self.database_url
        if all((self.postgres_host, self.postgres_database, self.postgres_user, self.postgres_password)):
            user = quote(str(self.postgres_user), safe="")
            password = quote(str(self.postgres_password), safe="")
            return (
                f"postgresql://{user}:{password}@"
                f"{self.postgres_host}:{self.postgres_port}/{self.postgres_database}"
            )
        return "postgresql://postgres:postgres@localhost:5432/user_management"


@lru_cache
def get_settings() -> Settings:
    return Settings()
