from datetime import datetime, timezone

from sqlmodel import Field, SQLModel


# Database Table
class Todo(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str = Field(index=True)
    description: str | None = Field(default=None)
    completed: bool = Field(default=False)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


# API Schemas
class TodoCreate(SQLModel):
    title: str
    description: str | None = None


class TodoRead(SQLModel):
    id: int
    title: str
    description: str | None
    completed: bool
    created_at: datetime
    updated_at: datetime


class TodoUpdate(SQLModel):
    title: str | None = None
    description: str | None = None
    completed: bool | None = None
