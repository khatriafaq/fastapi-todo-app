from datetime import datetime, timezone

from sqlmodel import Field, SQLModel


# Database Table
class Todo(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str = Field(index=True)
    description: str | None = Field(default=None)
    completed: bool = Field(default=False)
    owner_id: int | None = Field(default=None, foreign_key="user.id")
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


# User Models
class User(SQLModel, table=True):
    """User account with hashed password."""
    id: int | None = Field(default=None, primary_key=True)
    name: str | None = Field(default=None)
    email: str = Field(unique=True, index=True)
    hashed_password: str
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class UserCreate(SQLModel):
    """Request model for user signup."""
    name: str | None = None
    email: str
    password: str


class UserRead(SQLModel):
    """Response model - excludes password."""
    id: int
    name: str | None
    email: str
