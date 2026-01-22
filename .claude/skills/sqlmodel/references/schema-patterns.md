# Schema Patterns

Patterns for API validation schemas using SQLModel without `table=True`.

## Overview

Schemas are SQLModel classes **without** `table=True`. They're used for:
- API request validation (Create, Update)
- API response formatting (Read)
- Data transfer between layers

## Basic Schema Pattern

```python
from sqlmodel import SQLModel, Field

# Database model
class Task(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str
    description: str | None = Field(default=None)
    is_completed: bool = Field(default=False)
    owner_id: int = Field(foreign_key="user.id")

# Create schema - fields needed to create
class TaskCreate(SQLModel):
    title: str
    description: str | None = None
    owner_id: int

# Read schema - fields returned by API
class TaskRead(SQLModel):
    id: int
    title: str
    description: str | None
    is_completed: bool
    owner_id: int

# Update schema - all fields optional
class TaskUpdate(SQLModel):
    title: str | None = None
    description: str | None = None
    is_completed: bool | None = None
```

## Schema Inheritance

**Reduce duplication with a base schema.**

```python
# Shared fields
class TaskBase(SQLModel):
    title: str
    description: str | None = None

# Create inherits base
class TaskCreate(TaskBase):
    owner_id: int

# Read adds id and computed fields
class TaskRead(TaskBase):
    id: int
    is_completed: bool
    owner_id: int

# Update makes all optional
class TaskUpdate(SQLModel):
    title: str | None = None
    description: str | None = None
    is_completed: bool | None = None
```

## Nested Response Schemas

**Include related data in responses.**

```python
# User schemas
class UserBase(SQLModel):
    email: str
    name: str

class UserRead(UserBase):
    id: int

# Task with nested user
class TaskWithOwner(SQLModel):
    id: int
    title: str
    description: str | None
    is_completed: bool
    owner: UserRead  # Nested user data

# Usage in endpoint
@app.get("/tasks/{task_id}", response_model=TaskWithOwner)
def get_task(task_id: int, session: Session = Depends(get_session)):
    task = session.get(Task, task_id)
    return TaskWithOwner(
        id=task.id,
        title=task.title,
        description=task.description,
        is_completed=task.is_completed,
        owner=UserRead.model_validate(task.owner)
    )
```

### List of Nested Objects

```python
class TeamRead(SQLModel):
    id: int
    name: str

class HeroWithTeam(SQLModel):
    id: int
    name: str
    team: TeamRead | None

class TeamWithHeroes(SQLModel):
    id: int
    name: str
    heroes: list[HeroRead]  # List of nested objects
```

## Partial Update Pattern

**Handle PATCH requests with `exclude_unset=True`.**

```python
class TaskUpdate(SQLModel):
    title: str | None = None
    description: str | None = None
    is_completed: bool | None = None

@app.patch("/tasks/{task_id}", response_model=TaskRead)
def update_task(
    task_id: int,
    task_update: TaskUpdate,
    session: Session = Depends(get_session)
):
    task = session.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404)

    # Only update fields that were actually sent
    update_data = task_update.model_dump(exclude_unset=True)
    task.sqlmodel_update(update_data)

    session.add(task)
    session.commit()
    session.refresh(task)
    return task
```

**Key points:**
- `exclude_unset=True` ignores fields not in the request
- `sqlmodel_update()` applies partial updates
- Distinguishes between `None` sent explicitly vs field not sent

## Response Model Configuration

### Exclude Fields

```python
class UserRead(SQLModel):
    model_config = {"from_attributes": True}

    id: int
    email: str
    name: str
    # password_hash NOT included

# Usage
@app.get("/users/{user_id}", response_model=UserRead)
def get_user(user_id: int, session: Session = Depends(get_session)):
    return session.get(User, user_id)
```

### Computed Fields

```python
from pydantic import computed_field

class TaskRead(SQLModel):
    id: int
    title: str
    is_completed: bool
    created_at: datetime

    @computed_field
    @property
    def status_display(self) -> str:
        return "Done" if self.is_completed else "Pending"
```

## Pagination Schema

```python
from typing import Generic, TypeVar

T = TypeVar("T")

class PaginatedResponse(SQLModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int
    pages: int

    @classmethod
    def create(
        cls,
        items: list[T],
        total: int,
        page: int,
        page_size: int
    ) -> "PaginatedResponse[T]":
        return cls(
            items=items,
            total=total,
            page=page,
            page_size=page_size,
            pages=(total + page_size - 1) // page_size
        )

# Usage
@app.get("/tasks", response_model=PaginatedResponse[TaskRead])
def list_tasks(
    page: int = 1,
    page_size: int = 10,
    session: Session = Depends(get_session)
):
    offset = (page - 1) * page_size

    total = session.exec(select(func.count(Task.id))).one()
    tasks = session.exec(
        select(Task).offset(offset).limit(page_size)
    ).all()

    return PaginatedResponse.create(
        items=tasks,
        total=total,
        page=page,
        page_size=page_size
    )
```

## Validation Patterns

### Field Constraints

```python
from pydantic import EmailStr, field_validator

class UserCreate(SQLModel):
    email: EmailStr  # Email validation
    name: str = Field(min_length=1, max_length=100)
    age: int = Field(ge=0, le=150)  # 0 <= age <= 150

    @field_validator("name")
    @classmethod
    def name_must_not_be_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Name cannot be empty or whitespace")
        return v.strip()
```

### Cross-Field Validation

```python
from pydantic import model_validator

class DateRangeCreate(SQLModel):
    start_date: date
    end_date: date

    @model_validator(mode="after")
    def validate_date_range(self) -> "DateRangeCreate":
        if self.end_date < self.start_date:
            raise ValueError("end_date must be after start_date")
        return self
```

## Schema Factory Pattern

**Generate schemas dynamically for consistency.**

```python
from typing import Type

def create_schemas(
    model: Type[SQLModel],
    create_fields: list[str],
    read_fields: list[str],
    update_fields: list[str]
) -> tuple[Type[SQLModel], Type[SQLModel], Type[SQLModel]]:
    """Generate Create, Read, Update schemas from a model."""

    model_fields = model.model_fields

    # Create schema
    create_annotations = {
        name: model_fields[name].annotation
        for name in create_fields
    }
    CreateSchema = type(
        f"{model.__name__}Create",
        (SQLModel,),
        {"__annotations__": create_annotations}
    )

    # Read schema
    read_annotations = {
        name: model_fields[name].annotation
        for name in read_fields
    }
    ReadSchema = type(
        f"{model.__name__}Read",
        (SQLModel,),
        {"__annotations__": read_annotations}
    )

    # Update schema (all optional)
    update_annotations = {
        name: model_fields[name].annotation | None
        for name in update_fields
    }
    update_defaults = {name: None for name in update_fields}
    UpdateSchema = type(
        f"{model.__name__}Update",
        (SQLModel,),
        {"__annotations__": update_annotations, **update_defaults}
    )

    return CreateSchema, ReadSchema, UpdateSchema
```

## Complete Example

```python
from datetime import datetime
from enum import Enum
from pydantic import EmailStr, field_validator

from sqlmodel import Field, SQLModel

# Enums
class TaskPriority(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"

# Database model
class Task(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str = Field(max_length=200)
    description: str | None = Field(default=None)
    priority: TaskPriority = Field(default=TaskPriority.MEDIUM)
    is_completed: bool = Field(default=False)
    due_date: datetime | None = Field(default=None)
    owner_id: int = Field(foreign_key="user.id")
    created_at: datetime = Field(default_factory=datetime.utcnow)

# Schemas
class TaskBase(SQLModel):
    title: str = Field(max_length=200)
    description: str | None = None
    priority: TaskPriority = TaskPriority.MEDIUM
    due_date: datetime | None = None

    @field_validator("title")
    @classmethod
    def title_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Title cannot be empty")
        return v.strip()

class TaskCreate(TaskBase):
    owner_id: int

class TaskRead(TaskBase):
    id: int
    is_completed: bool
    owner_id: int
    created_at: datetime

class TaskUpdate(SQLModel):
    title: str | None = None
    description: str | None = None
    priority: TaskPriority | None = None
    is_completed: bool | None = None
    due_date: datetime | None = None

# Nested response
class UserRead(SQLModel):
    id: int
    email: str
    name: str

class TaskWithOwner(TaskRead):
    owner: UserRead

# List response
class TaskListResponse(SQLModel):
    tasks: list[TaskRead]
    total: int
```
